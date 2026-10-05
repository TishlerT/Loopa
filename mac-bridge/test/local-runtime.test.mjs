import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, realpath, writeFile, chmod, readFile, lstat, rm, unlink, symlink, mkdir, rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startLocalAssistant, LocalRuntimeError} from '../local-runtime.mjs';

const now = 1_791_200_000_000;
const capability = Buffer.alloc(32,7).toString('base64url');
function deferred() { let resolve,reject; const promise=new Promise((a,b)=>{resolve=a;reject=b;}); return {promise,resolve,reject}; }
async function fixture(t) {
  const directory = await mkdtemp(join(await realpath(tmpdir()),'loopa-runtime-test-'));
  const helperPath = join(directory,'synthetic-helper');
  await writeFile(helperPath,'#!/bin/sh\nexit 1\n',{mode:0o700});
  const pairingFile = join(directory,'loopa-assistant-pair.json');
  const stateDirectory = join(directory,'state');
  let session; let runtime;
  const calls = []; const captured = {};
  const repository = {
    async initialize(){calls.push('initialize');return {hostId:'urn:uuid:00000000-0000-4000-8000-000000000001'};},
    async getRegistration(){return undefined;}, async savePendingRegistration(){},
    async activateVerified(record,{signal}={}){session=record;signal?.addEventListener('abort',()=>{if(session===record)session=undefined;},{once:true});},
    getActiveSession(){return session;}, async reserveRequest(value){calls.push('reserve');captured.reservation=value;return true;},
  };
  const provider = {cancel(){calls.push('cancelProvider');},async listModels(){return [{slug:'visible',display_name:'Visible'}];},
    async proposeGain(){return {operations:[]};}};
  const server = {pairing:{endpoint:'http://127.0.0.1:52341/',capability,expiresAt:now+900000},async stop(){calls.push('stopServer');}};
  const factories = {
    repository(options){calls.push('repository');captured.repository=options;return repository;},
    grant(options){captured.grant=options;return {async start(args){
      calls.push('startGrant');captured.grantArguments=args;
      const controller = new AbortController();
      const signal = AbortSignal.any([args.signal,controller.signal]);
      const record={scopes:['resource.invoke','chatgpt.tokens.use.direct'],credentials:{accessToken:'SYNTHETIC_PRIVATE',expiresAt:now+3600000}};
      return {completion:Promise.resolve().then(async()=>{if(signal.aborted)throw Error('cancelled');await options.repository.activateVerified(record,{signal});return {identity:{email:'private@example.invalid'},credentials:record.credentials};}),
        cancel(){calls.push('cancelGrant');controller.abort();}};
    }};},
    provider(options){captured.provider=options;return provider;},
    readProposal(){},
    async server(options){captured.server=options;calls.push('server');return server;},
  };
  const options={helperPath,pairingFile,stateDirectory,factories,now:()=>now,openBrowser:async()=>{calls.push('browser');}};
  const f={directory,helperPath,pairingFile,stateDirectory,factories,repository,provider,server,calls,captured,options,
    setSession(value){session=value;},async start(){runtime=await startLocalAssistant(options);return runtime;}};
  t.after(async()=>{try{await runtime?.stop();}catch{}await rm(directory,{recursive:true,force:true});});
  return f;
}
const code = expected => error => {assert.ok(error instanceof LocalRuntimeError);assert.equal(error.code,expected);return true;};

test('private pairing contains only capability, not credentials, and construction does not connect',async t=>{
  const f=await fixture(t);const runtime=await f.start();
  assert.deepEqual(runtime.status(),{status:'disconnected',sharing:false});
  assert.deepEqual(Object.keys(runtime).sort(),['connect','pairingExpiresAt','status','stop']);
  const record=JSON.parse(await readFile(f.pairingFile,'utf8'));
  assert.deepEqual(record,{version:1,endpoint:f.server.pairing.endpoint,capability,expires_at:now+900000});
  assert.equal((await lstat(f.pairingFile)).mode&0o777,0o600);
  assert.equal((await lstat(f.stateDirectory)).mode&0o777,0o700);
  assert.deepEqual(f.calls,['repository','initialize','server']);
  assert.equal(f.captured.repository.helperPath,f.helperPath);
});
test('second runtime cannot initialize repository while first owns lock',async t=>{
  const f=await fixture(t);await f.start();
  await assert.rejects(startLocalAssistant(f.options),code('busy'));
  assert.equal(f.calls.filter(x=>x==='initialize').length,1);
});
test('fresh successful grant provides only safe connection state and exact protected dependencies',async t=>{
  const f=await fixture(t);const runtime=await f.start();
  const value=await runtime.connect();assert.deepEqual(value,{status:'connected',sharing:true});
  assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
  assert.equal(f.captured.grant.appName,'Loopa');assert.equal(f.captured.grantArguments.port,0);
  assert.equal(f.captured.provider.readProposal,f.factories.readProposal);
  assert.equal(f.captured.provider.getActiveSession().credentials.accessToken,'SYNTHETIC_PRIVATE');
  const reservation={requestId:'fixture'};assert.equal(await f.captured.provider.reserveRequest(reservation),true);
  assert.deepEqual(f.captured.reservation,reservation);
});
test('stop revokes completed grant and closes server before releasing lock',async t=>{
  const f=await fixture(t);const runtime=await f.start();await runtime.connect();await runtime.stop();
  assert.deepEqual(runtime.status(),{status:'disconnected',sharing:false});
  assert.equal(f.repository.getActiveSession(),undefined);assert.equal(f.captured.provider.getActiveSession(),undefined);
  await assert.rejects(lstat(f.pairingFile),{code:'ENOENT'});await assert.rejects(lstat(join(f.stateDirectory,'bridge.lock')),{code:'ENOENT'});
  assert.ok(f.calls.indexOf('cancelGrant')<f.calls.indexOf('stopServer'));
  await assert.rejects(runtime.connect(),code('stopped'));
  assert.throws(()=>f.captured.provider.reserveRequest({}),code('stopped'));
});
test('consumed pairing file is normal at shutdown',async t=>{
  const f=await fixture(t);const runtime=await f.start();await unlink(f.pairingFile);await runtime.stop();
  await assert.rejects(lstat(join(f.stateDirectory,'bridge.lock')),{code:'ENOENT'});
});
test('replaced pairing is preserved and prevents unsafe unlock',async t=>{
  const f=await fixture(t);const runtime=await f.start();await rename(f.pairingFile,f.pairingFile+'.old');await writeFile(f.pairingFile,'replacement',{mode:0o600});
  await assert.rejects(runtime.stop(),code('cleanup_required'));assert.equal(await readFile(f.pairingFile,'utf8'),'replacement');
  assert.ok((await lstat(join(f.stateDirectory,'bridge.lock'))).isDirectory());
});
test('unknown lock contents are not recursively deleted',async t=>{
  const f=await fixture(t);const runtime=await f.start();const extra=join(f.stateDirectory,'bridge.lock','unexpected');await writeFile(extra,'retained');
  await assert.rejects(runtime.stop(),code('cleanup_required'));assert.equal(await readFile(extra,'utf8'),'retained');
});
test('preexisting pairing file is never overwritten',async t=>{
  const f=await fixture(t);await writeFile(f.pairingFile,'retained',{mode:0o600});await assert.rejects(f.start(),code('connection_failed'));
  assert.equal(await readFile(f.pairingFile,'utf8'),'retained');assert.ok(f.calls.includes('stopServer'));
});
test('helper must be an owned non-writable-by-others regular executable',async t=>{
  for(const mode of [0o600,0o777]){const f=await fixture(t);await chmod(f.helperPath,mode);await assert.rejects(f.start(),code('invalid_configuration'));assert.deepEqual(f.calls,[]);}
});
test('helper and pairing parent symlinks cannot redirect private state',async t=>{
  const f=await fixture(t);const link=f.helperPath+'.link';await symlink(f.helperPath,link);f.options.helperPath=link;
  await assert.rejects(f.start(),code('invalid_configuration'));
  f.options.helperPath=f.helperPath;const parent=join(f.directory,'alias');await symlink(f.directory,parent);f.options.pairingFile=join(parent,'pair.json');
  await assert.rejects(f.start(),code('storage_unavailable'));assert.deepEqual(f.calls,[]);
});
test('state directory with broad access is rejected before constructing repository',async t=>{
  const f=await fixture(t);await mkdir(f.stateDirectory,{mode:0o755});await assert.rejects(f.start(),code('storage_unavailable'));assert.deepEqual(f.calls,[]);
});
test('server cannot supply remote, oversized-lifetime, or malformed pairing',async t=>{
  for(const pair of [{endpoint:'http://example.invalid:52341/'},{expiresAt:now+900001},{expiresAt:now},{capability:'X'.repeat(43)}]){
    const f=await fixture(t);Object.assign(f.server.pairing,pair);await assert.rejects(f.start(),code('invalid_configuration'));
    await assert.rejects(lstat(f.pairingFile),{code:'ENOENT'});assert.ok(f.calls.includes('stopServer'));
  }
});
test('connect refuses overlap and stop cancels a pending grant',async t=>{
  const f=await fixture(t);const done=deferred();const entered=deferred();
  f.factories.grant=()=>({async start(){entered.resolve();return {completion:done.promise,cancel(){done.reject(Error('SYNTHETIC_PRIVATE'));}};}});
  const runtime=await f.start();const connect=runtime.connect();void connect.catch(()=>{});await entered.promise;
  assert.equal(runtime.status().status,'connecting');await assert.rejects(runtime.connect(),code('busy'));
  await runtime.stop();await assert.rejects(connect,code('stopped'));
});
test('stop before delayed grant handle cancels it and rejects connection',async t=>{
  const f=await fixture(t);const entered=deferred(), ready=deferred();let cancelled=0;
  f.factories.grant=()=>({async start(){entered.resolve();return ready.promise;}});
  const runtime=await f.start();const connect=runtime.connect();void connect.catch(()=>{});await entered.promise;await runtime.stop();
  ready.resolve({completion:Promise.resolve(),cancel(){cancelled++;}});await assert.rejects(connect,code('stopped'));assert.equal(cancelled,1);
});
test('underlying credential write remains owned after OAuth promise cancellation',async t=>{
  const f=await fixture(t);const write=deferred(),entered=deferred();f.repository.activateVerified=async()=>{entered.resolve();await write.promise;};
  const runtime=await f.start();const connect=runtime.connect();void connect.catch(()=>{});await entered.promise;
  let stopped=false;const stopping=runtime.stop().then(()=>{stopped=true;});await new Promise(resolve=>setImmediate(resolve));
  assert.equal(stopped,false);await assert.rejects(startLocalAssistant(f.options),code('busy'));
  write.resolve();await stopping;await assert.rejects(connect,code('stopped'));
});
test('uncertain credential write preserves process lock without exposing native error',async t=>{
  const f=await fixture(t);f.repository.activateVerified=async()=>{throw Object.assign(Error('SYNTHETIC_PRIVATE'),{code:'timeout'});};
  const runtime=await f.start();await assert.rejects(runtime.connect(),code('connection_failed'));
  await assert.rejects(runtime.stop(),code('cleanup_required'));await assert.rejects(startLocalAssistant(f.options),code('busy'));
});
test('initialization failure retains lock for protected storage inspection',async t=>{
  const f=await fixture(t);f.repository.initialize=async()=>{throw Error('SYNTHETIC_PRIVATE');};
  await assert.rejects(f.start(),code('cleanup_required'));await assert.rejects(startLocalAssistant(f.options),code('busy'));
});
test('expired and identity-only grants cannot imply usable allowance',async t=>{
  const f=await fixture(t);const runtime=await f.start();
  f.setSession({scopes:['openid'],credentials:{expiresAt:now+3600000}});assert.deepEqual(runtime.status(),{status:'connected',sharing:false});
  f.setSession({scopes:['resource.invoke','chatgpt.tokens.use.direct'],credentials:{expiresAt:now+45000}});
  assert.deepEqual(runtime.status(),{status:'reconnect_required',sharing:false});
});
test('usage failure is visible and does not trigger fallback or retry',async t=>{
  const f=await fixture(t);let calls=0;f.provider.proposeGain=async()=>{calls++;throw Object.assign(Error('bounded'),{code:'request_not_reserved'});};
  const runtime=await f.start();await runtime.connect();await assert.rejects(f.captured.server.provider.proposeGain({}),{code:'request_not_reserved'});
  assert.equal(calls,1);assert.equal(runtime.status().status,'usage_unavailable');
});
test('late provider success cannot cross stop',async t=>{
  const f=await fixture(t);const done=deferred();f.provider.listModels=()=>done.promise;const runtime=await f.start();
  const models=f.captured.server.provider.listModels({});void models.catch(()=>{});await runtime.stop();done.resolve([{slug:'old'}]);
  await assert.rejects(models,code('stopped'));
});
test('server stop failure retains lock and only fixed error escapes',async t=>{
  const f=await fixture(t);f.server.stop=async()=>{throw Error('SYNTHETIC_PRIVATE');};const runtime=await f.start();
  await assert.rejects(runtime.stop(),code('cleanup_required'));await assert.rejects(startLocalAssistant(f.options),code('busy'));
});
test('successful stop is idempotent',async t=>{
  const f=await fixture(t);const runtime=await f.start();await Promise.all([runtime.stop(),runtime.stop()]);await runtime.stop();
  assert.equal(f.calls.filter(x=>x==='stopServer').length,1);
});
test('reentrant provider cancellation receives the same stop promise',async t=>{
  const f=await fixture(t);let runtime,inner;
  f.provider.cancel=()=>{inner=runtime.stop();};runtime=await f.start();
  const outer=runtime.stop();await outer;assert.equal(inner,outer);
});
test('reconnect cancels active provider work before starting the new grant',async t=>{
  const f=await fixture(t);const pending=deferred();f.provider.proposeGain=()=>pending.promise;
  const runtime=await f.start();await runtime.connect();
  const operation=f.captured.server.provider.proposeGain({});void operation.catch(()=>{});
  const before=f.calls.filter(x=>x==='cancelProvider').length;
  await runtime.connect();assert.equal(f.calls.filter(x=>x==='cancelProvider').length,before+1);
  pending.resolve({operations:[]});await assert.rejects(operation,code('connection_changed'));
});
test('old account failure cannot change the new account usage state',async t=>{
  const f=await fixture(t);const pending=deferred();f.provider.proposeGain=()=>pending.promise;
  const runtime=await f.start();await runtime.connect();
  const operation=f.captured.server.provider.proposeGain({});void operation.catch(()=>{});
  await runtime.connect();pending.reject(Object.assign(Error('old denial'),{code:'usage_unavailable'}));
  await assert.rejects(operation,code('connection_changed'));
  assert.deepEqual(runtime.status(),{status:'connected',sharing:true});
});
test('provider cannot begin while a new grant is connecting',async t=>{
  const f=await fixture(t);const pending=deferred();const entered=deferred();let modelCalls=0;
  f.factories.grant=()=>({async start(){entered.resolve();return {completion:pending.promise,cancel(){pending.reject(Error('cancelled'));}};}});
  f.provider.listModels=async()=>{modelCalls++;return [];};
  const runtime=await f.start();const connect=runtime.connect();void connect.catch(()=>{});await entered.promise;
  await assert.rejects(f.captured.server.provider.listModels({}),code('connection_changed'));assert.equal(modelCalls,0);
  await runtime.stop();await assert.rejects(connect,code('stopped'));
});
