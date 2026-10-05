import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createMusicProvider, MusicProviderError} from '../music-provider.mjs';

const requestId = '11111111-1111-1111-1111-111111111111';
const trackId = '22222222-2222-2222-2222-222222222222';
const now = 1700000000000;
const project = () => ({version:1, request_id:requestId, tempo_bpm:100, loop_beats:4,
  track:{id:trackId,kind:'midi',instrument:'Piano',volume:0.5,muted:false,solo:false,length_beats:4,audible:true},capabilities:['gain']});
const credentials = () => ({activationId:'activation-1',profileId:'profile-1',subject:'person-1',
  scopes:['resource.invoke','chatgpt.tokens.use.direct'],credentials:{tokenType:'Bearer',accessToken:'SYNTHETIC-NOT-A-TOKEN',expiresAt:now+3600000}});
const models = () => ({models:[{slug:'preferred',display_name:'Preferred',visibility:'list'},
  {slug:'hidden',display_name:'Hidden',visibility:'hide'},{slug:'other',display_name:'Other',visibility:'list'}]});
const json = (value, status=200) => new Response(JSON.stringify(value),{status});
const proposal = () => ({operations:[{kind:'gain',track_id:trackId,value:0.7}]});
const deferred = () => { let resolve;let reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject}; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function fixture(overrides={}) {
  const calls=[];const reservations=[];const parsed=[];let selected=credentials();
  const api=createMusicProvider({now:()=>now,getActiveSession:()=>selected,
    reserveRequest:async x=>{reservations.push(x);return true;},
    readProposal:async (body,options)=>{parsed.push(options);await body.cancel();return proposal();},
    fetchImpl:async (url,init)=>{calls.push({url,init});return url.endsWith('/models')?json(models()):new Response('synthetic stream');},...overrides});
  return {api,calls,reservations,parsed,setSession:x=>selected=x};
}
const gain = (overrides={}) => ({requestId,userText:'Make this track louder',project:project(),model:'preferred',...overrides});
async function rejectCode(operation, code) { await assert.rejects(operation,e=>e instanceof MusicProviderError&&e.code===code); }

test('catalog uses SIWC models list, preserves server order and hides non-list entries',async()=>{
  const f=fixture();const result=await f.api.listModels();
  assert.deepEqual(result,[{slug:'preferred',displayName:'Preferred'},{slug:'other',displayName:'Other'}]);
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].url,'https://api.openai.com/v1/models');
  assert.equal(f.calls[0].init.redirect,'error');assert.equal(f.calls[0].init.method,'GET');
  assert.equal(f.calls[0].init.headers.authorization,'Bearer SYNTHETIC-NOT-A-TOKEN');
  assert.equal(f.reservations.length,0);
});
test('one authorized gain request uses fixed endpoint and exact narrow tools without API key fallback',async()=>{
  const f=fixture();await f.api.listModels();const result=await f.api.proposeGain(gain());
  assert.deepEqual(result,{requestId,proposal:proposal()});assert.equal(f.calls.length,2);
  const {url,init}=f.calls[1];assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(init.method,'POST');assert.equal(init.redirect,'error');
  const body=JSON.parse(init.body);assert.equal(body.store,false);assert.equal(body.stream,true);assert.equal(body.model,'preferred');
  assert.deepEqual(Object.keys(body).sort(),['model','store','stream','instructions','input','tools'].sort());
  assert.deepEqual(JSON.parse(body.input[0].content),{request:'Make this track louder',project:project()});
  assert.equal(body.tools.length,1);assert.equal(body.tools[0].name,'loopa_music');assert.equal(body.tools[0].type,'namespace');
  const tool=body.tools[0].tools[0];assert.equal(tool.name,'propose_gain');assert.equal(tool.strict,true);
  assert.deepEqual(tool.parameters.required,['track_id','gain']);assert.equal(tool.parameters.additionalProperties,false);
  assert.deepEqual(f.reservations,[{requestId,activationId:'activation-1',profileId:'profile-1'}]);
  assert.equal(f.parsed[0].expectedTrackId,trackId);
  assert.ok(!JSON.stringify(result).includes('TOKEN'));
});
test('audio tracks use same volume-only contract without exposing recorded files',async()=>{
  const f=fixture();await f.api.listModels();const p=project();p.track.kind='audio';p.track.instrument='Vocals';
  await f.api.proposeGain(gain({project:p}));assert.equal(JSON.parse(JSON.parse(f.calls[1].init.body).input[0].content).project.track.kind,'audio');
});
test('input project is captured before awaits and returned catalog cannot alter allowed models',async()=>{
  const gate=deferred();let block=false;const f=fixture({getActiveSession:()=>block?gate.promise:credentials()});
  const catalog=await f.api.listModels();catalog[0].slug='injected';catalog.push({slug:'injected'});
  await rejectCode(f.api.proposeGain(gain({model:'injected'})),'choose_model');
  const p=project();block=true;const pending=f.api.proposeGain(gain({project:p}));p.track.volume=0.99;gate.resolve(credentials());
  await pending;assert.equal(JSON.parse(JSON.parse(f.calls[1].init.body).input[0].content).project.track.volume,0.5);
});
for (const [name,alter] of [
  ['request mismatch',p=>p.request_id='33333333-3333-3333-3333-333333333333'],
  ['unknown root data',p=>p.audio='private recording'],['track file path',p=>p.track.filename='/private.wav'],
  ['unsupported midi capability',p=>p.capabilities.push('midi_region')],['invalid gain',p=>p.track.volume=NaN],
  ['gain above bound',p=>p.track.volume=1.1],['unknown track type',p=>p.track.kind='unknown'],
  ['nonboolean state',p=>p.track.muted=1],['invalid uuid',p=>p.track.id='unsafe'],['zero loop',p=>p.loop_beats=0],
  ['oversized label',p=>p.track.instrument='x'.repeat(121)],['control character label',p=>p.track.instrument='a\nb'],
]) test(`invalid context rejected before reserving or sending: ${name}`,async()=>{
  const f=fixture();await f.api.listModels();const p=project();alter(p);
  await rejectCode(f.api.proposeGain(gain({project:p})),'invalid_request');assert.equal(f.calls.length,1);assert.equal(f.reservations.length,0);
});
test('UTF8 request size counts bytes rather than characters',async()=>{
  const f=fixture();await f.api.listModels();await rejectCode(f.api.proposeGain(gain({userText:'🎵'.repeat(513)})),'invalid_request');assert.equal(f.calls.length,1);
});
test('no catalog means no request and hidden models cannot be selected',async()=>{
  const f=fixture();await rejectCode(f.api.proposeGain(gain()),'choose_model');await f.api.listModels();
  await rejectCode(f.api.proposeGain(gain({model:'hidden'})),'choose_model');assert.equal(f.reservations.length,0);assert.equal(f.calls.length,1);
});
for (const [name,value,code] of [
  ['disconnected',null,'not_connected'],
  ['identity-only',{...credentials(),scopes:['openid']},'permission_required'],
  ['expired',{...credentials(),credentials:{...credentials().credentials,expiresAt:now+44999}},'reconnect'],
  ['header injection',{...credentials(),credentials:{...credentials().credentials,accessToken:'x\r\nsecret'}},'not_connected'],
]) test(`unusable session prevents network: ${name}`,async()=>{
  const f=fixture({getActiveSession:()=>value});await rejectCode(f.api.listModels(),code);assert.equal(f.calls.length,0);
});
for(const status of [401,403,429,500]) test(`HTTP ${status} fails safely once without retry or body disclosure`,async()=>{
  let count=0;const f=fixture({fetchImpl:async()=>{count++;return new Response('SECRET AUTH PRIVATE PROJECT',{status});}});
  const code=status===401?'reconnect':[403,429].includes(status)?'usage_unavailable':'service_unavailable';
  await rejectCode(f.api.listModels(),code);assert.equal(count,1);
});
test('network failure is sanitized without retry',async()=>{
  let count=0;const f=fixture({fetchImpl:async()=>{count++;throw new Error('SECRET TOKEN');}});
  await assert.rejects(f.api.listModels(),e=>e.code==='service_unavailable'&&!String(e).includes('SECRET')&&!e.cause);assert.equal(count,1);
});
for(const value of [{data:[]},{models:[]},{models:Array(101).fill(models().models[0])},
  {models:[models().models[0],models().models[0]]},{models:[{...models().models[0],slug:'../../bad'}]},
  {models:[{...models().models[0],display_name:'one\ntwo'}]}]) test(`malformed catalog rejected: ${JSON.stringify(value).slice(0,65)}`,async()=>{
  const f=fixture({fetchImpl:async()=>json(value)});await rejectCode(f.api.listModels(),'invalid_response');
});
test('invalid UTF8 or oversized catalog is rejected',async()=>{
  for(const body of [new Uint8Array([0xff]),'x'.repeat(262145)]) {
    const f=fixture({fetchImpl:async()=>new Response(body)});await rejectCode(f.api.listModels(),'invalid_response');
  }
});
test('redirected response URL is rejected even if transport did not enforce redirects',async()=>{
  const response=json(models());Object.defineProperty(response,'url',{value:'https://different.example/models'});
  const f=fixture({fetchImpl:async()=>response});await rejectCode(f.api.listModels(),'invalid_response');
});
test('second request is busy and is never queued',async()=>{
  const gate=deferred();const f=fixture({fetchImpl:()=>gate.promise});const one=f.api.listModels();
  await rejectCode(f.api.listModels(),'busy');gate.resolve(json(models()));await one;
});
test('already cancelled request makes no credential or network call',async()=>{
  let reads=0;const f=fixture({getActiveSession:()=>{reads++;return credentials();}});const c=new AbortController();c.abort();
  await rejectCode(f.api.listModels({signal:c.signal}),'cancelled');assert.equal(reads,0);assert.equal(f.calls.length,0);
});
test('cancel bounds an uncooperative session repository and releases busy state',async()=>{
  let hang=true;const f=fixture({getActiveSession:()=>hang?new Promise(()=>{}):credentials()});const pending=f.api.listModels();
  f.api.cancel();await rejectCode(pending,'cancelled');hang=false;assert.equal((await f.api.listModels()).length,2);
});
test('timeout bounds uncooperative fetch',async()=>{
  const f=fixture({timeoutMs:10,fetchImpl:()=>new Promise(()=>{})});await rejectCode(f.api.listModels(),'timeout');
});
test('timeout bounds hanging catalog stream without waiting for hanging cancel',async()=>{
  const f=fixture({timeoutMs:10,fetchImpl:async()=>new Response(new ReadableStream({pull:()=>new Promise(()=>{}),cancel:()=>new Promise(()=>{})}))});
  await rejectCode(f.api.listModels(),'timeout');
});
test('account switch during catalog discovery discards catalog',async()=>{
  const gate=deferred();const f=fixture({fetchImpl:()=>gate.promise});const pending=f.api.listModels();await tick();
  f.setSession({...credentials(),activationId:'new'});gate.resolve(json(models()));await rejectCode(pending,'account_changed');
  await rejectCode(f.api.proposeGain(gain()),'choose_model');
});
test('account switch after catalog requires explicit refreshed selection',async()=>{
  const f=fixture();await f.api.listModels();f.setSession({...credentials(),activationId:'new'});
  await rejectCode(f.api.proposeGain(gain()),'choose_model');assert.equal(f.reservations.length,0);
});
test('switch during reservation consumes reservation but sends nothing',async()=>{
  const f=fixture({reserveRequest:async()=>{f.setSession({...credentials(),activationId:'new'});return true;}});
  await f.api.listModels();await rejectCode(f.api.proposeGain(gain()),'account_changed');assert.equal(f.calls.length,1);
});
for(const result of [false,undefined,'yes']) test(`no explicit reservation means no POST: ${result}`,async()=>{
  const f=fixture({reserveRequest:async()=>result});await f.api.listModels();await rejectCode(f.api.proposeGain(gain()),'request_not_reserved');assert.equal(f.calls.length,1);
});
test('reservation failure never POSTs or refunds uncertain write',async()=>{
  let attempts=0;const f=fixture({reserveRequest:async()=>{attempts++;throw new Error('secret disk state');}});
  await f.api.listModels();await rejectCode(f.api.proposeGain(gain()),'request_not_reserved');assert.equal(attempts,1);assert.equal(f.calls.length,1);
});
test('cancellation while reservation runs prevents POST even if reservation completes late',async()=>{
  const gate=deferred();const entered=deferred();const f=fixture({reserveRequest:()=>{entered.resolve();return gate.promise;}});
  await f.api.listModels();const pending=f.api.proposeGain(gain());await entered.promise;f.api.cancel();await rejectCode(pending,'cancelled');
  gate.resolve(true);await tick();assert.equal(f.calls.length,1);
});
test('stream parser failures never return a proposal or retry',async()=>{
  const f=fixture({readProposal:async()=>{throw new Error('TOKEN RAW STREAM');}});await f.api.listModels();
  await assert.rejects(f.api.proposeGain(gain()),e=>e.code==='invalid_response'&&!String(e).includes('TOKEN'));
  assert.equal(f.calls.length,2);assert.equal(f.reservations.length,1);
});
test('account switch during response parsing discards otherwise valid proposal',async()=>{
  const f=fixture({readProposal:async body=>{await body.cancel();f.setSession({...credentials(),activationId:'new'});return proposal();}});
  await f.api.listModels();await rejectCode(f.api.proposeGain(gain()),'account_changed');assert.equal(f.calls.length,2);
});
test('cancel while parser ignores abort remains bounded and never returns late proposal',async()=>{
  const gate=deferred();const entered=deferred();const f=fixture({readProposal:()=>{entered.resolve();return gate.promise;}});
  await f.api.listModels();const pending=f.api.proposeGain(gain());await entered.promise;f.api.cancel();await rejectCode(pending,'cancelled');
  gate.resolve(proposal());await tick();await rejectCode(f.api.proposeGain(gain()),'choose_model');assert.equal(f.calls.length,2);
});
test('unsafe or incomplete configuration fails closed',()=>{
  assert.throws(()=>createMusicProvider(),{code:'invalid_configuration'});
  for(const timeoutMs of [0,45001,NaN,1.5]) assert.throws(()=>fixture({timeoutMs}),{code:'invalid_configuration'});
});
test('a fetch that resolves after timeout has its body cancelled',async()=>{
  const gate=deferred();let cancelled=0;
  const f=fixture({timeoutMs:10,fetchImpl:()=>gate.promise});await rejectCode(f.api.listModels(),'timeout');
  gate.resolve(new Response(new ReadableStream({cancel(){cancelled++;}})));await tick();assert.equal(cancelled,1);
});
test('an infinite zero-byte catalog stream cannot starve its deadline',async()=>{
  let chunks=0;const f=fixture({fetchImpl:async()=>new Response(new ReadableStream({pull(c){chunks++;c.enqueue(new Uint8Array());}}))});
  await rejectCode(f.api.listModels(),'invalid_response');assert.ok(chunks<=4098);
});
for (const hops of [3,4,5]) for (const finalRead of [2,5]) test(`terminal cancellation at read ${finalRead}, microtask ${hops} cannot return or restore eligibility`,async()=>{
  let reads=0;let cancelled=false;let f;
  const later=n=>n===0?(cancelled=true,f.api.cancel()):queueMicrotask(()=>later(n-1));
  f=fixture({getActiveSession:()=>{if(++reads===finalRead)later(hops);return credentials();}});
  if(finalRead===2) await rejectCode(f.api.listModels(),'cancelled');
  else {await f.api.listModels();await rejectCode(f.api.proposeGain(gain()),'cancelled');}
  assert.equal(cancelled,true);assert.equal(f.calls.length,finalRead===2?1:2);
  await rejectCode(f.api.proposeGain(gain()),'choose_model');
  assert.equal(f.reservations.length,finalRead===2?0:1,'No retry or refund after cancellation');
});
for (const stage of ['session','fetch','reservation','parser']) test(`synchronous ${stage} cancellation observes rejected dependency without process crash or raw stderr`,()=>{
  const program=`
    import assert from 'node:assert/strict';
    import {createMusicProvider} from ${JSON.stringify(new URL('../music-provider.mjs',import.meta.url).href)};
    const stage=${JSON.stringify(stage)};const c=new AbortController();let armed=false;
    const failure=()=>{c.abort();return Promise.reject(new Error('SYNTHETIC-RAW-DEPENDENCY-ERROR'));};
    const api=createMusicProvider({now:()=>${now},
      getActiveSession:()=>stage==='session'&&armed?failure():${JSON.stringify(credentials())},
      reserveRequest:()=>stage==='reservation'&&armed?failure():true,
      readProposal:()=>stage==='parser'&&armed?failure():${JSON.stringify(proposal())},
      fetchImpl:async url=>stage==='fetch'&&armed?failure():url.endsWith('/models')?new Response(${JSON.stringify(JSON.stringify(models()))}):new Response('synthetic')});
    if(stage==='session'||stage==='fetch'){armed=true;await assert.rejects(api.listModels({signal:c.signal}),{code:'cancelled'});}
    else {await api.listModels();armed=true;await assert.rejects(api.proposeGain({...${JSON.stringify(gain())},signal:c.signal}),{code:'cancelled'});}
    await new Promise(r=>setTimeout(r,10));
  `;
  const child=spawnSync(process.execPath,['--input-type=module','--eval',program],{encoding:'utf8',timeout:5000,env:{PATH:process.env.PATH}});
  assert.equal(child.status,0,child.stderr);assert.equal(child.signal,null);assert.equal(child.stderr,'');assert.equal(child.stdout,'');
});
