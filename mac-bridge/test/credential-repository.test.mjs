import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import {createCredentialRepository,CredentialRepositoryError} from '../credential-repository.mjs';

const requestId='11111111-1111-1111-1111-111111111111';
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
const tick=()=>new Promise(r=>setImmediate(r));
const rejects=(p,code)=>assert.rejects(p,e=>e instanceof CredentialRepositoryError&&e.code===code);
function nativeFixture(){
  let stored;let custom;const calls=[];const children=[];
  function spawnImpl(path,args,options){
    const child=new EventEmitter();child.stdin=new PassThrough();child.stdout=new PassThrough();child.stderr=new PassThrough();children.push(child);
    child.kill=signal=>{queueMicrotask(()=>child.emit('close',null,signal));return true;};
    let input='';child.stdin.on('data',x=>input+=x.toString());
    child.stdin.on('finish',()=>queueMicrotask(()=>{
      const req=JSON.parse(input);calls.push({path,args,options,req,input});
      const respond=(value,code=0)=>{child.stdout.emit('data',Buffer.from(JSON.stringify(value)+'\n'));child.emit('close',code,null);};
      const commit=()=>{if(req.op==='replace')stored=structuredClone(req.record);};
      const next=custom;custom=undefined;
      if(next){next({req,child,respond,commit});return;}
      if(req.op==='read')return stored?respond({ok:true,record:stored}):respond({ok:false,error:'missing'},1);
      commit();respond({ok:true});
    }));return child;
  }
  return {spawnImpl,calls,children,setStored:value=>stored=structuredClone(value),getStored:()=>structuredClone(stored),once:fn=>custom=fn,
    repository:(options={})=>createCredentialRepository({helperPath:'/synthetic/loopa-credential-helper',spawnImpl,...options})};
}
async function setup(){
  const f=nativeFixture();const repo=f.repository();const {hostId}=await repo.initialize();
  const registration={version:1,profileId:'profile-1',clientId:'client-1',hostId,issuer:'https://auth.openai.com'};
  const record={...registration,subject:'person-1',identity:{subject:'person-1',name:'Synthetic Person'},receivedAt:1000000,
    scopes:['resource.invoke','chatgpt.tokens.use.direct'],credentials:{accessToken:'SYNTHETIC-ACCESS',idToken:'SYNTHETIC-ID',refreshToken:'SYNTHETIC-REFRESH',tokenType:'Bearer',expiresAt:4600000}};
  async function activate(signal){await repo.savePendingRegistration(registration,{signal});await repo.activateVerified(record,{signal});return repo.getActiveSession();}
  return {...f,repo,hostId,registration,record,activate};
}
test('initialize creates an app-owned stable host and does not activate credentials',async()=>{
  const f=await setup();assert.match(f.hostId,/^urn:uuid:[0-9a-f-]{36}$/);assert.equal(f.repo.getActiveSession(),undefined);
  assert.deepEqual(await f.repo.initialize(),{hostId:f.hostId});assert.equal(f.calls.length,2);
  const second=f.repository();assert.deepEqual(await second.initialize(),{hostId:f.hostId});assert.equal(f.calls.length,3);
});
test('helper gets zero argv tokens, pipe-only IPC and a minimal environment',async()=>{
  const f=await setup();await f.activate();
  for(const c of f.calls){assert.equal(c.path,'/synthetic/loopa-credential-helper');assert.deepEqual(c.args,[]);assert.equal(c.options.shell,false);
    assert.deepEqual(c.options.stdio,['pipe','pipe','pipe']);assert.deepEqual(Object.keys(c.options.env).sort(),['HOME','PATH','TMPDIR']);
    assert.equal(c.options.cwd,'/synthetic');assert.ok(c.input.endsWith('\n'));}
});
test('pending registration preserves client identity without activating; verified storage activates only after write',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);assert.deepEqual(await f.repo.getRegistration('profile-1'),f.registration);
  assert.equal(f.repo.getActiveSession(),undefined);const entered=deferred();let finish;
  f.once(({commit,respond})=>{finish=()=>{commit();respond({ok:true});};entered.resolve();});
  const pending=f.repo.activateVerified(f.record);await entered.promise;assert.equal(f.repo.getActiveSession(),undefined);
  finish();await pending;assert.equal(f.repo.getActiveSession().credentials.accessToken,'SYNTHETIC-ACCESS');assert.match(f.repo.getActiveSession().activationId,/^[0-9a-f-]{36}$/);
});
test('restart never activates persisted tokens',async()=>{
  const f=await setup();await f.activate();const second=f.repository();await second.initialize();assert.equal(second.getActiveSession(),undefined);
  const m=await second.getRegistration('profile-1');assert.equal(m.subject,'person-1');assert.equal(m.credentials,undefined);
});
test('callers cannot mutate stored metadata or active credentials by reference',async()=>{
  const f=await setup();await f.activate();const active=f.repo.getActiveSession();active.credentials.accessToken='tampered';active.scopes.length=0;
  const m=await f.repo.getRegistration('profile-1');m.clientId='tampered';assert.equal(f.repo.getActiveSession().credentials.accessToken,'SYNTHETIC-ACCESS');
  assert.equal((await f.repo.getRegistration('profile-1')).clientId,'client-1');
});
test('aborted operations do not start a credential write',async()=>{
  const f=await setup();const c=new AbortController();c.abort();const before=f.calls.length;
  await rejects(f.repo.savePendingRegistration(f.registration,{signal:c.signal}),'cancelled');
  await rejects(f.repo.activateVerified(f.record,{signal:c.signal}),'cancelled');assert.equal(f.calls.length,before);
});
test('cancellation during atomic credential write can persist but never activates',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);const entered=deferred();let finish;const c=new AbortController();
  f.once(({commit,respond})=>{finish=()=>{commit();respond({ok:true});};entered.resolve();});
  const pending=f.repo.activateVerified(f.record,{signal:c.signal});await entered.promise;c.abort();finish();
  await rejects(pending,'cancelled');assert.equal(f.repo.getActiveSession(),undefined);assert.equal(f.getStored().payload.sessions.length,1);
  const second=f.repository();await second.initialize();assert.equal(second.getActiveSession(),undefined);
});
test('late grant cancellation deactivates only that activation',async()=>{
  const f=await setup();const c=new AbortController();await f.activate(c.signal);c.abort();assert.equal(f.repo.getActiveSession(),undefined);
  await f.repo.activateVerified(f.record);const id=f.repo.getActiveSession().activationId;c.abort();assert.equal(f.repo.getActiveSession().activationId,id);
});
test('disconnect racing an in-flight activation cannot resurrect inference authority',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);const entered=deferred();let finish;
  f.once(({commit,respond})=>{finish=()=>{commit();respond({ok:true});};entered.resolve();});
  const pending=f.repo.activateVerified(f.record);await entered.promise;await rejects(f.repo.disconnect(),'busy');finish();
  await rejects(pending,'cancelled');assert.equal(f.repo.getActiveSession(),undefined);
});
test('immediate disconnect fences activation before its first cached-state await completes',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);const before=f.calls.length;
  const pending=f.repo.activateVerified(f.record);const disconnect=f.repo.disconnect();
  await rejects(disconnect,'busy');await rejects(pending,'cancelled');assert.equal(f.repo.getActiveSession(),undefined);
  assert.equal(f.calls.length,before);assert.equal(f.getStored().payload.sessions.length,0);
});
test('disconnect during first initialization read prevents later activation write',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);const repo=f.repository();const entered=deferred();let finish;
  f.once(({req,respond})=>{assert.equal(req.op,'read');finish=()=>respond({ok:true,record:f.getStored()});entered.resolve();});
  const pending=repo.activateVerified(f.record);await entered.promise;const before=f.calls.length;
  await rejects(repo.disconnect(),'busy');finish();await rejects(pending,'cancelled');
  assert.equal(repo.getActiveSession(),undefined);assert.equal(f.calls.length,before);assert.equal(f.getStored().payload.sessions.length,0);
});
test('durable one-request allowance survives restart, disconnect and fresh activation',async()=>{
  const f=await setup();let active=await f.activate();const reservation={requestId,activationId:active.activationId,profileId:active.profileId};
  assert.equal(await f.repo.reserveRequest(reservation),true);assert.equal(await f.repo.reserveRequest(reservation),false);
  await f.repo.disconnect();assert.equal(f.getStored().payload.sessions.length,0);assert.equal(f.getStored().payload.requests.length,1);
  await f.repo.activateVerified(f.record);active=f.repo.getActiveSession();assert.equal(await f.repo.reserveRequest({...reservation,activationId:active.activationId}),false);
  const second=f.repository();await second.initialize();assert.equal(second.getActiveSession(),undefined);assert.equal(f.getStored().payload.requests.length,1);
});
test('mismatched or inactive reservation cannot spend test allowance',async()=>{
  const f=await setup();assert.equal(await f.repo.reserveRequest({requestId,activationId:requestId,profileId:'profile-1'}),false);
  const active=await f.activate();assert.equal(await f.repo.reserveRequest({requestId,activationId:requestId,profileId:active.profileId}),false);
  assert.equal(await f.repo.reserveRequest({requestId,activationId:active.activationId,profileId:'different'}),false);assert.equal(f.getStored().payload.requests.length,0);
});
test('uncertain committed reservation is retained, inactive and requires explicit read reconciliation',async()=>{
  const f=await setup();const active=await f.activate();
  f.once(({commit,child})=>{commit();child.emit('close',null,'SIGKILL');});
  await rejects(f.repo.reserveRequest({requestId,activationId:active.activationId,profileId:active.profileId}),'unavailable');
  assert.equal(f.repo.getActiveSession(),undefined);assert.equal(f.getStored().payload.requests.length,1);
  await rejects(f.repo.initialize(),'reconcile_required');await f.repo.reconcile();assert.equal(f.repo.getActiveSession(),undefined);
  await f.repo.activateVerified(f.record);const newer=f.repo.getActiveSession();assert.equal(await f.repo.reserveRequest({requestId,activationId:newer.activationId,profileId:newer.profileId}),false);
});
test('uncertain store absence never recreates state or resets allowance during reconcile',async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);
  f.once(({child})=>child.emit('close',null,'SIGKILL'));await rejects(f.repo.activateVerified(f.record),'unavailable');
  f.setStored(undefined);const before=f.calls.length;await rejects(f.repo.reconcile(),'missing');assert.equal(f.calls.length,before+1);assert.equal(f.calls.at(-1).req.op,'read');
  await rejects(f.repo.initialize(),'reconcile_required');
});
for(const error of ['denied','corrupt','conflict'])test(`failed read ${error} never overwrites existing bytes`,async()=>{
  const f=nativeFixture();f.once(({respond})=>respond({ok:false,error},1));const repo=f.repository();await rejects(repo.initialize(),error);
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].req.op,'read');
});
test('malformed stored payload never triggers a replacement',async()=>{
  const f=nativeFixture();f.setStored({version:1,payload:{hostId:'invalid'}});await rejects(f.repository().initialize(),'corrupt');assert.equal(f.calls.length,1);
});
for(const [name,mutate] of [
  ['wrong host',x=>x.hostId='urn:uuid:11111111-1111-1111-1111-111111111111'],
  ['wrong issuer',x=>x.issuer='https://evil.example'],['missing subject',x=>delete x.subject],
  ['token header newline',x=>x.credentials.accessToken='secret\r\nheader'],['expiration',x=>x.credentials.expiresAt=0],
  ['unknown credential',x=>x.credentials.apiKey='secret'],['non-bearer token',x=>x.credentials.tokenType='Other'],
  ['duplicate scopes',x=>x.scopes.push(x.scopes[0])],['oversized identity',x=>x.identity.name='x'.repeat(4097)]
])test(`invalid verified record does not enter helper: ${name}`,async()=>{
  const f=await setup();await f.repo.savePendingRegistration(f.registration);const value=structuredClone(f.record);mutate(value);const before=f.calls.length;
  await rejects(f.repo.activateVerified(value),'invalid_record');assert.equal(f.calls.length,before);assert.equal(f.repo.getActiveSession(),undefined);
});
test('unregistered profile, changed client and changed subject cannot activate',async()=>{
  const f=await setup();await rejects(f.repo.activateVerified(f.record),'conflict');await f.activate();const before=f.calls.length;
  await rejects(f.repo.activateVerified({...f.record,clientId:'different'}),'conflict');
  await rejects(f.repo.activateVerified({...f.record,subject:'different'}),'conflict');
  await rejects(f.repo.savePendingRegistration({...f.registration,clientId:'different'}),'conflict');assert.equal(f.calls.length,before);
});
test('registration cap and metadata-only lookup are bounded',async()=>{
  const f=await setup();for(let i=0;i<4;i++)await f.repo.savePendingRegistration({...f.registration,profileId:`profile-${i}`});
  await rejects(f.repo.savePendingRegistration({...f.registration,profileId:'profile-4'}),'invalid_record');assert.equal(await f.repo.getRegistration('absent'),undefined);
});
test('one slow helper refuses concurrent work rather than accumulating a queue',async()=>{
  const f=nativeFixture();const entered=deferred();let finish;
  f.once(({respond})=>{finish=()=>respond({ok:false,error:'denied'},1);entered.resolve();});const repo=f.repository();
  const pending=repo.initialize();await entered.promise;await rejects(repo.initialize(),'busy');finish();await rejects(pending,'denied');assert.equal(f.calls.length,1);
});
test('helper deadline kills process and reports no raw data',async()=>{
  const f=nativeFixture();f.once(()=>{});const repo=f.repository({timeoutMs:10});await rejects(repo.initialize(),'timeout');await tick();
  assert.equal(f.calls.length,1);
});
test('timeout while replacing marks storage uncertain and active unavailable',async()=>{
  const f=await setup();const repo=f.repository({timeoutMs:10});await repo.initialize();await repo.savePendingRegistration(f.registration);
  f.once(({commit})=>commit());await rejects(repo.activateVerified(f.record),'timeout');assert.equal(repo.getActiveSession(),undefined);await tick();
  await rejects(repo.initialize(),'reconcile_required');await repo.reconcile();assert.equal(repo.getActiveSession(),undefined);
});
for(const [name,bytes,code] of [
  ['extra line',Buffer.from('{"ok":true}\n{"secret":"TOKEN"}\n'),'corrupt'],
  ['bad utf8',Buffer.from([0xff,10]),'corrupt'],['oversized stdout',Buffer.alloc(65665,65),'corrupt'],
  ['unknown error',Buffer.from('{"ok":false,"error":"SECRET TOKEN"}\n'),'unavailable'],
  ['no newline',Buffer.from('{"ok":true}'),'corrupt']
])test(`invalid IPC ${name} is bounded and sanitized`,async()=>{
  const f=nativeFixture();f.once(({child})=>{child.stdout.emit('data',bytes);child.emit('close',name==='unknown error'?1:0,null);});
  await assert.rejects(f.repository().initialize(),e=>e.code===code&&!String(e).includes('TOKEN')&&!e.cause);
});
test('stderr content is never returned and unbounded stderr kills helper',async()=>{
  const f=nativeFixture();f.once(({child})=>child.stderr.emit('data',Buffer.from('SECRET'.repeat(1000))));
  await assert.rejects(f.repository().initialize(),e=>e.code==='unavailable'&&!String(e).includes('SECRET'));
});
test('unexpected success schema and signal exit fail closed',async()=>{
  for(const bad of [({respond})=>respond({ok:true,record:{},extra:'bad'}),({child})=>child.emit('close',null,'SIGTERM')]){
    const f=nativeFixture();f.once(bad);await assert.rejects(f.repository().initialize(),CredentialRepositoryError);
  }
});
test('no shell command, relative helper, infinite timeout or extra request allowance is accepted',()=>{
  assert.throws(()=>createCredentialRepository(),{code:'invalid_configuration'});
  for(const helperPath of ['relative','/tmp/bad\nname'])assert.throws(()=>createCredentialRepository({helperPath}),{code:'invalid_configuration'});
  for(const timeoutMs of [0,5001,Infinity,1.5])assert.throws(()=>createCredentialRepository({helperPath:'/test',timeoutMs}),{code:'invalid_configuration'});
});
