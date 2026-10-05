import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runLocalPilot} from '../local-pilot.mjs';

const argv = ['--helper','/synthetic/helper','--pairing-file','/synthetic/pair.json'];
const moduleURL = new URL('../local-pilot.mjs',import.meta.url).href;
const deferred = () => { let resolve,reject; const promise = new Promise((a,b) => {resolve=a;reject=b;}); return {promise,resolve,reject}; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function fixture(overrides = {}) {
  const signals = new EventEmitter(), codes = [], calls = [];
  const connected = deferred();
  const runtime = {pairingExpiresAt:Date.now()+60_000,
    connect(){calls.push('connect');return Promise.resolve({status:'connected',sharing:true});},
    stop(){calls.push('stop');return Promise.resolve();}};
  let passed;
  const options = {signals,write:code=>{codes.push(code);if(code==='LOOPA_PILOT_CONNECTED')connected.resolve();},
    start:options=>{calls.push('start');passed=options;return runtime;},
    startupTimeoutMs:100,connectTimeoutMs:100,cleanupTimeoutMs:100,lifetimeMs:1000,...overrides};
  return {signals,codes,calls,runtime,options,connected,get passed(){return passed;},run:args=>runLocalPilot(args??argv,options)};
}

for (const args of [[],argv.slice(0,2),[...argv,'--remote','https://example.invalid'],
  ['--helper','relative','--pairing-file','/synthetic/pair.json'],
  ['--helper','/synthetic/../helper','--pairing-file','/synthetic/pair.json'],
  ['--helper','/synthetic/helper','--helper','/synthetic/other'],
  ['--helper','/synthetic/helper','--pairing-file','/synthetic/helper'],
  ['--state-directory','/synthetic/state','--pairing-file','/synthetic/pair.json'],
  ['--helper=/synthetic/helper','--pairing-file','/synthetic/pair.json','extra'],
  ['--helper','/synthetic/unsafe\npath','--pairing-file','/synthetic/pair.json']]) {
  test('invalid CLI shape never calls runtime: '+JSON.stringify(args),async()=>{
    const f=fixture();assert.equal(await f.run(args),2);assert.deepEqual(f.calls,[]);
    assert.deepEqual(f.codes,['LOOPA_PILOT_INVALID_ARGUMENTS']);assert.equal(f.signals.eventNames().length,0);
  });
}

test('valid paths are the only runtime options; successful connection waits for SIGINT and awaits stop',async()=>{
  const f=fixture(),stop=deferred();f.runtime.stop=()=>{f.calls.push('stop');return stop.promise;};
  const running=f.run();await f.connected.promise;
  assert.deepEqual(f.passed,{helperPath:'/synthetic/helper',pairingFile:'/synthetic/pair.json'});
  assert.deepEqual(f.calls,['start','connect']);assert.deepEqual(f.codes,['LOOPA_PILOT_STARTING','LOOPA_PILOT_CONNECTING','LOOPA_PILOT_CONNECTED']);
  f.signals.emit('SIGINT');let ended=false;void running.then(()=>ended=true);await tick();assert.equal(ended,false);
  stop.resolve();assert.equal(await running,130);assert.equal(f.codes.at(-1),'LOOPA_PILOT_INTERRUPTED');
  assert.deepEqual(f.calls,['start','connect','stop']);assert.equal(f.signals.eventNames().length,0);
});
test('flag order is independent and SIGTERM has its conventional status',async()=>{
  const f=fixture();const running=f.run(['--pairing-file','/synthetic/pair.json','--helper','/synthetic/helper']);
  await f.connected.promise;f.signals.emit('SIGTERM');assert.equal(await running,143);assert.equal(f.codes.at(-1),'LOOPA_PILOT_TERMINATED');
});
test('repeated signals during shutdown do not call stop twice or replace first signal',async()=>{
  const f=fixture(),done=deferred();f.runtime.stop=()=>{f.calls.push('stop');return done.promise;};
  const running=f.run();await f.connected.promise;f.signals.emit('SIGTERM');f.signals.emit('SIGINT');f.signals.emit('SIGTERM');
  await tick();done.resolve();assert.equal(await running,143);assert.equal(f.calls.filter(x=>x==='stop').length,1);
});
test('synchronous signal in starting status prevents runtime construction',async()=>{
  const f=fixture();f.options.write=code=>{f.codes.push(code);if(code==='LOOPA_PILOT_STARTING')f.signals.emit('SIGINT');};
  assert.equal(await f.run(),130);assert.deepEqual(f.calls,[]);
});
test('signal in connecting status prevents connect callback',async()=>{
  const f=fixture();f.options.write=code=>{f.codes.push(code);if(code==='LOOPA_PILOT_CONNECTING')f.signals.emit('SIGINT');};
  assert.equal(await f.run(),130);assert.deepEqual(f.calls,['start','stop']);
});
test('signal while startup is pending awaits late handle and stops it before returning',async()=>{
  const f=fixture(),gate=deferred();f.options.start=()=>{f.calls.push('start');return gate.promise;};
  const running=f.run();await tick();f.signals.emit('SIGTERM');await tick();gate.resolve(f.runtime);
  assert.equal(await running,143);assert.deepEqual(f.calls,['start','stop']);assert.equal(f.codes.includes('LOOPA_PILOT_CONNECTED'),false);
});
test('unsettled startup reaches bounded cleanup uncertainty; later handle is still stopped',async()=>{
  const f=fixture({startupTimeoutMs:5,cleanupTimeoutMs:5}),gate=deferred();f.options.start=()=>gate.promise;
  assert.equal(await f.run(),5);assert.equal(f.codes.at(-1),'LOOPA_PILOT_CLEANUP_REQUIRED');
  assert.equal(f.signals.eventNames().length,0);gate.resolve(f.runtime);await tick();await tick();
  assert.deepEqual(f.calls,['stop']);
});
test('startup deadline can end cleanly when handle arrives during cleanup',async()=>{
  const f=fixture({startupTimeoutMs:5}),gate=deferred();f.options.start=()=>gate.promise;
  const timer=setTimeout(()=>gate.resolve(f.runtime),15);
  try{assert.equal(await f.run(),4);assert.deepEqual(f.calls,['stop']);assert.equal(f.codes.at(-1),'LOOPA_PILOT_TIMEOUT');}finally{clearTimeout(timer);}
});
test('startup rejection is sanitized and does not invent a stop handle',async()=>{
  const f=fixture();f.options.start=()=>Promise.reject(new Error('SYNTHETIC_PRIVATE_START'));
  assert.equal(await f.run(),3);assert.deepEqual(f.calls,[]);assert.equal(f.codes.at(-1),'LOOPA_PILOT_START_FAILED');
  assert.equal(f.codes.join().includes('SYNTHETIC'),false);
});
test('runtime cleanup_required startup error preserves uncertainty exit',async()=>{
  const f=fixture();f.options.start=()=>Promise.reject(Object.assign(new Error('SYNTHETIC_PRIVATE'),{code:'cleanup_required'}));
  assert.equal(await f.run(),5);assert.equal(f.codes.at(-1),'LOOPA_PILOT_CLEANUP_REQUIRED');
});
test('connect rejection stops runtime and prints no error, cause, URL or credentials',async()=>{
  const f=fixture();f.runtime.connect=()=>Promise.reject(new Error('https://synthetic.invalid/?token=PRIVATE',{cause:{accessToken:'SYNTHETIC_PRIVATE'}}));
  assert.equal(await f.run(),3);assert.equal(f.codes.at(-1),'LOOPA_PILOT_CONNECTION_FAILED');
  assert.deepEqual(f.calls,['start','stop']);assert.doesNotMatch(f.codes.join(),/PRIVATE|https|cause/);
});
test('connect deadline stops runtime without waiting for an ignored cancellation',async()=>{
  const f=fixture({connectTimeoutMs:5}),gate=deferred();f.runtime.connect=()=>gate.promise;
  assert.equal(await f.run(),4);assert.deepEqual(f.calls,['start','stop']);gate.reject(new Error('SYNTHETIC_LATE_CONNECT'));await tick();
});
test('signal during connect dominates a late successful result',async()=>{
  const f=fixture(),entered=deferred(),gate=deferred();f.runtime.connect=()=>{entered.resolve();return gate.promise;};
  const running=f.run();await entered.promise;f.signals.emit('SIGINT');gate.resolve({status:'connected',sharing:true});
  assert.equal(await running,130);assert.equal(f.codes.includes('LOOPA_PILOT_CONNECTED'),false);
});
test('connect synchronously signals then rejects without an unhandled dependency error',async()=>{
  const f=fixture();f.runtime.connect=()=>{f.signals.emit('SIGINT');return Promise.reject(new Error('SYNTHETIC_PRIVATE'));};
  assert.equal(await f.run(),130);await tick();assert.equal(f.codes.includes('LOOPA_PILOT_CONNECTED'),false);
});
test('identity-only connection never prints connected or remains usable',async()=>{
  const f=fixture();f.runtime.connect=()=>({status:'connected',sharing:false});
  assert.equal(await f.run(),3);assert.equal(f.codes.at(-1),'LOOPA_PILOT_SHARING_REQUIRED');assert.equal(f.codes.includes('LOOPA_PILOT_CONNECTED'),false);
});
test('nonconnected terminal runtime status fails closed',async()=>{
  const f=fixture();f.runtime.connect=()=>({status:'reconnect_required',sharing:false});
  assert.equal(await f.run(),3);assert.equal(f.codes.at(-1),'LOOPA_PILOT_CONNECTION_FAILED');
});
test('overall active lifetime expires even with connected runtime',async()=>{
  const f=fixture({lifetimeMs:15});assert.equal(await f.run(),0);assert.equal(f.codes.at(-1),'LOOPA_PILOT_EXPIRED');
  assert.deepEqual(f.calls,['start','connect','stop']);
});
test('pairing expiry can shorten the pilot lifetime',async()=>{
  const f=fixture({now:()=>1000});f.runtime.pairingExpiresAt=1010;
  assert.equal(await f.run(),0);assert.equal(f.codes.at(-1),'LOOPA_PILOT_EXPIRED');
});
for(const expiresAt of [999,1000,901001,NaN,Infinity,'2000'])test('invalid pairing expiry never invokes connect: '+expiresAt,async()=>{
  const f=fixture({now:()=>1000});f.runtime.pairingExpiresAt=expiresAt;
  assert.equal(await f.run(),3);assert.deepEqual(f.calls,['start','stop']);assert.equal(f.codes.at(-1),'LOOPA_PILOT_START_FAILED');
});
test('throwing stop overrides signal with cleanup uncertainty',async()=>{
  const f=fixture();f.runtime.stop=()=>{throw new Error('SYNTHETIC_PRIVATE_STOP');};
  const running=f.run();await f.connected.promise;f.signals.emit('SIGINT');assert.equal(await running,5);
  assert.equal(f.codes.at(-1),'LOOPA_PILOT_CLEANUP_REQUIRED');assert.equal(f.signals.eventNames().length,0);
});
test('hung stop is bounded and a late rejection is observed',async()=>{
  const f=fixture({cleanupTimeoutMs:5}),gate=deferred();f.runtime.stop=()=>gate.promise;
  const running=f.run();await f.connected.promise;f.signals.emit('SIGTERM');assert.equal(await running,5);
  gate.reject(new Error('SYNTHETIC_PRIVATE_LATE_STOP'));await tick();
});
test('reentrant stop signal does not deadlock or replace prior outcome',async()=>{
  const f=fixture();f.runtime.stop=()=>{f.calls.push('stop');f.signals.emit('SIGTERM');};
  const running=f.run();await f.connected.promise;f.signals.emit('SIGINT');assert.equal(await running,130);assert.equal(f.calls.filter(x=>x==='stop').length,1);
});
test('diagnostic writer failure cannot skip cleanup',async()=>{
  const f=fixture({lifetimeMs:10,write:()=>{throw new Error('synthetic output failure');}});
  assert.equal(await f.run(),0);assert.deepEqual(f.calls,['start','connect','stop']);
});
for(const key of ['startupTimeoutMs','connectTimeoutMs','cleanupTimeoutMs','lifetimeMs'])test('test seam cannot remove upper deadline: '+key,async()=>{
  const f=fixture({[key]:Infinity});assert.equal(await f.run(),2);assert.deepEqual(f.calls,[]);
});
test('import is inert and executable invalid arguments produce only a static code',()=>{
  const imported=spawnSync(process.execPath,['--input-type=module','--eval','await import('+JSON.stringify(moduleURL)+');'],{encoding:'utf8',timeout:2000,env:{PATH:process.env.PATH}});
  assert.equal(imported.status,0);assert.equal(imported.stdout,'');assert.equal(imported.stderr,'');
  const direct=spawnSync(process.execPath,[fileURLToPath(moduleURL),'--bad-secret-flag=SYNTHETIC_PRIVATE'],{encoding:'utf8',timeout:2000,env:{PATH:process.env.PATH}});
  assert.equal(direct.status,2);assert.equal(direct.stdout,'LOOPA_PILOT_INVALID_ARGUMENTS\n');assert.equal(direct.stderr,'');
});
for(const signal of ['SIGINT','SIGTERM'])test('actual process signal exits after cleanup despite live dependency handles: '+signal,async()=>{
  const program=`import {main} from ${JSON.stringify(moduleURL)};
    await main(${JSON.stringify(argv)},{start:()=>({pairingExpiresAt:Date.now()+60000,
      connect:()=>{setInterval(()=>{},1000);return {status:'connected',sharing:true};},
      stop:()=>new Promise(()=>{})}),cleanupTimeoutMs:10});`;
  const result=await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,['--unhandled-rejections=strict','--input-type=module','--eval',program],{stdio:['ignore','pipe','pipe'],env:{PATH:process.env.PATH}});
    let stdout='',stderr='',sent=false;
    const timer=setTimeout(()=>{child.kill('SIGKILL');reject(new Error('synthetic CLI did not exit'));},2000);
    child.stdout.on('data',value=>{stdout+=value;if(!sent&&stdout.includes('LOOPA_PILOT_CONNECTED')){sent=true;child.kill(signal);}});
    child.stderr.on('data',value=>stderr+=value);child.on('error',reject);
    child.on('close',(code,terminated)=>{clearTimeout(timer);resolve({code,terminated,stdout,stderr});});
  });
  assert.equal(result.code,5);assert.equal(result.terminated,null);assert.equal(result.stderr,'');
  assert.equal(result.stdout,'LOOPA_PILOT_STARTING\nLOOPA_PILOT_CONNECTING\nLOOPA_PILOT_CONNECTED\nLOOPA_PILOT_CLEANUP_REQUIRED\n');
});
