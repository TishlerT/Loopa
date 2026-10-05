import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {startLocalMusicServer} from '../local-server.mjs';
import {createMusicProvider} from '../music-provider.mjs';

const id='11111111-1111-1111-1111-111111111111',other='33333333-3333-3333-3333-333333333333';
const track='22222222-2222-2222-2222-222222222222';
const proposal={operations:[{kind:'gain',track_id:track,value:0.7}]};
const input=()=>({request_id:id,user_text:'Make this louder',model:'test-model',project:{version:1,request_id:id,tempo_bpm:120,loop_beats:4,
  track:{id:track,kind:'midi',instrument:'Piano',volume:0.5,muted:false,solo:false,length_beats:4,audible:true},capabilities:['gain']}});
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const tick=()=>new Promise(r=>setImmediate(r));
async function fixture(t,options={}) {
  const calls=[];let cancels=0;
  const provider={listModels:async options=>{calls.push({kind:'models',...options});return [{slug:'test-model',displayName:'Test model'}];},
    proposeGain:async options=>{calls.push({kind:'proposal',...options});return {requestId:options.requestId,proposal};},cancel:()=>{cancels++;}};
  const server=await startLocalMusicServer({provider,status:async options=>{calls.push({kind:'status',...options});return {status:'connected',sharing:true};},...options});
  t.after(()=>server.stop());
  return {...server,calls,get cancels(){return cancels;}};
}
function request(f,{path='/v1/status',method='GET',headers={},body,authorized=true}={}) {
  return new Promise((resolve,reject)=>{
    const base=new URL(f.pairing.endpoint);
    const requestHeaders={...(authorized?{authorization:'Bearer '+f.pairing.capability}:{}),...(body!==undefined?{'content-type':'application/json'}:{}),...headers};
    const req=http.request({hostname:'127.0.0.1',port:base.port,path,method,headers:requestHeaders,agent:false},res=>{
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('error',reject);res.on('end',()=>{
        const text=Buffer.concat(chunks).toString();let json;try{json=JSON.parse(text);}catch{}
        resolve({status:res.statusCode,headers:res.headers,text,json});
      });
    });
    req.on('error',reject);req.setTimeout(2000,()=>req.destroy(new Error('Test client deadline')));
    req.end(body===undefined?undefined:typeof body==='string'||Buffer.isBuffer(body)?body:JSON.stringify(body));
  });
}
function raw(f,headers,path='/v1/status',method='GET',body='') {
  return new Promise((resolve,reject)=>{
    const url=new URL(f.pairing.endpoint);const socket=net.connect({host:'127.0.0.1',port:Number(url.port)},()=>{
      socket.write(`${method} ${path} HTTP/1.1\r\nHost: 127.0.0.1:${url.port}\r\nAuthorization: Bearer ${f.pairing.capability}\r\n${headers}\r\n${body}`);
    });
    let data='';socket.on('data',chunk=>data+=chunk);socket.on('error',reject);socket.on('close',()=>resolve(data));
    socket.setTimeout(2000,()=>socket.destroy(new Error('Test socket deadline')));
  });
}

test('pairing is canonical random 32-byte capability on a nonprivileged IPv4 loopback port',async t=>{
  const a=await fixture(t),b=await fixture(t);const url=new URL(a.pairing.endpoint);
  assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/');assert.ok(Number(url.port)>=1024);
  assert.match(a.pairing.capability,/^[A-Za-z0-9_-]{43}$/);assert.equal(Buffer.from(a.pairing.capability,'base64url').length,32);
  assert.notEqual(a.pairing.capability,b.pairing.capability);assert.ok(a.pairing.expiresAt-Date.now()<=900000);
  assert.ok(Object.isFrozen(a.pairing));
});
test('status, model, proposal and unmatched cancellation match exact iOS schemas',async t=>{
  const f=await fixture(t);
  const status=await request(f);assert.equal(status.status,200);assert.deepEqual(status.json,{version:1,status:'connected',sharing:true});
  assert.equal(status.headers['cache-control'],'no-store');assert.equal(status.headers['access-control-allow-origin'],undefined);
  const models=await request(f,{path:'/v1/models'});assert.deepEqual(models.json,{version:1,models:[{slug:'test-model',display_name:'Test model'}]});
  const result=await request(f,{path:'/v1/proposals',method:'POST',body:input()});assert.equal(result.status,200);
  assert.deepEqual(result.json,{version:1,request_id:id,proposal});
  const called=f.calls.find(c=>c.kind==='proposal');assert.deepEqual(called.project,input().project);
  assert.equal(called.requestId,id);assert.equal(called.userText,input().user_text);assert.equal(called.model,'test-model');assert.ok(called.signal instanceof AbortSignal);
  assert.deepEqual((await request(f,{path:'/v1/proposals/'+id,method:'DELETE'})).json,{version:1,cancelled:false});
  assert.equal(f.cancels,0,'Success and idle requests must preserve provider catalog');
});
for(const state of ['connected','disconnected','connecting','reconnect_required','usage_unavailable']) test(`safe status enum: ${state}`,async t=>{
  const f=await fixture(t,{status:()=>({status:state,sharing:false})});assert.deepEqual((await request(f)).json,{version:1,status:state,sharing:false});
});
for(const options of [
  {authorized:false},{headers:{authorization:'Bearer invalid'}},{headers:{origin:'https://evil.example'}},
  {headers:{cookie:'session=private'}},{headers:{host:'localhost:1234'}},{headers:{'sec-fetch-site':'cross-site'}},
  {headers:{'sec-fetch-mode':'cors'}},{headers:{'content-encoding':'gzip'}},{path:'/v1/status?capability=anything'},
  {path:'/v1/status#fragment'},{path:'http://evil.example/v1/status'},{path:'/v1/credentials'},
]) test(`unauthorized/cross-site/unknown request does not invoke dependencies ${JSON.stringify(options)}`,async t=>{
  const f=await fixture(t);const result=await request(f,options);assert.notEqual(result.status,200);assert.equal(f.calls.length,0);assert.equal(f.cancels,0);
});
for(const header of ['Host: other\r\n','Authorization: Bearer other\r\n','X-Foo: one\r\nX-Foo: two\r\n','Accept: application/json\r\naccept: text/plain\r\n']) test('duplicate request headers rejected: '+header.split(':')[0],async t=>{
  const f=await fixture(t);const result=await raw(f,header);assert.match(result,/^HTTP\/1\.1 400/);assert.equal(f.calls.length,0);
});
for(const body of ['', '{', '[1]', JSON.stringify({...input(),unknown:'secret'}),JSON.stringify({...input(),request_id:'bad'}),JSON.stringify({...input(),user_text:'🎵'.repeat(513)})]) test('malformed/nonnarrow POST is rejected before provider: '+body.slice(0,24),async t=>{
  const f=await fixture(t);const result=await request(f,{path:'/v1/proposals',method:'POST',body});assert.equal(result.status,400);assert.equal(f.calls.length,0);
});
for(const type of ['text/plain','application/x-www-form-urlencoded','multipart/form-data']) test('browser simple content type rejected '+type,async t=>{
  const f=await fixture(t);const result=await request(f,{path:'/v1/proposals',method:'POST',headers:{'content-type':type},body:input()});assert.equal(result.status,400);assert.equal(f.calls.length,0);
});
test('invalid UTF8 body rejected instead of replacement decoding',async t=>{
  const f=await fixture(t);const result=await request(f,{path:'/v1/proposals',method:'POST',body:Buffer.from([0xff])});assert.equal(result.status,400);assert.equal(f.calls.length,0);
});
test('body overflow is rejected for content-length and chunked bodies',async t=>{
  const f=await fixture(t);
  for(const headers of [{'content-length':'16385'},{'transfer-encoding':'chunked'}]) {
    const result=await request(f,{path:'/v1/proposals',method:'POST',headers,body:'x'.repeat(16385)});
    assert.equal(result.status,413);assert.equal(f.calls.length,0);
  }
});
test('exact body byte limit permits a valid padded JSON object',async t=>{
  const f=await fixture(t);const body=JSON.stringify(input());const result=await request(f,{path:'/v1/proposals',method:'POST',body:body+' '.repeat(16384-Buffer.byteLength(body))});assert.equal(result.status,200);
});
test('headers are capped before any application callback',async t=>{
  const f=await fixture(t);assert.match(await raw(f,'X-Large: '+'x'.repeat(9000)+'\r\n'),/^HTTP\/1\.1 400/);assert.equal(f.calls.length,0);
});
test('Expect continue, upgrade and CONNECT never invoke dependencies',async t=>{
  const f=await fixture(t);assert.match(await raw(f,'Expect: 100-continue\r\nContent-Length: 2\r\nContent-Type: application/json\r\n','/v1/proposals','POST','{}'),/^HTTP\/1\.1 400/);
  assert.equal(await raw(f,'Connection: Upgrade\r\nUpgrade: websocket\r\n'),'');
  assert.equal(await raw(f,'','127.0.0.1:443','CONNECT'),'');assert.equal(f.calls.length,0);
});
test('one callback at a time; busy requests do not queue or cancel catalog',async t=>{
  const gate=deferred(),entered=deferred();let calls=0,cancels=0;
  const f=await fixture(t,{provider:{listModels:()=>{calls++;entered.resolve();return gate.promise;},proposeGain:()=>{calls++;},cancel:()=>cancels++}});
  const pending=request(f,{path:'/v1/models'});await entered.promise;
  assert.equal((await request(f)).status,409);assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).status,409);
  assert.equal(calls,1);assert.equal(cancels,0);gate.resolve([{slug:'test-model',displayName:'Test model'}]);assert.equal((await pending).status,200);
});
test('matching DELETE cancels active proposal once, wrong and repeated IDs do not',async t=>{
  const gate=deferred(),entered=deferred();let cancels=0,signal;
  const f=await fixture(t,{provider:{listModels:()=>[],proposeGain:options=>{signal=options.signal;entered.resolve();return gate.promise;},cancel:()=>cancels++}});
  const pending=request(f,{path:'/v1/proposals',method:'POST',body:input()});await entered.promise;
  assert.deepEqual((await request(f,{path:'/v1/proposals/'+other,method:'DELETE'})).json,{version:1,cancelled:false});assert.equal(signal.aborted,false);
  assert.deepEqual((await request(f,{path:'/v1/proposals/'+id.toUpperCase(),method:'DELETE'})).json,{version:1,cancelled:true});
  assert.equal((await pending).json.error,'cancelled');assert.equal(signal.aborted,true);assert.equal(cancels,1);
  assert.deepEqual((await request(f,{path:'/v1/proposals/'+id,method:'DELETE'})).json,{version:1,cancelled:false});
  gate.resolve({requestId:id,proposal});await tick();assert.equal(cancels,1);
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).json.error,'duplicate_request');
});
test('request UUID remains consumed after provider failure without replay',async t=>{
  let calls=0;const f=await fixture(t,{provider:{listModels:()=>[],proposeGain:()=>{calls++;throw new Error('synthetic secret');},cancel:()=>{}}});
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).status,503);
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).json.error,'duplicate_request');assert.equal(calls,1);
});
test('client disconnect aborts actual active provider signal and cancels once',async t=>{
  const entered=deferred(),gate=deferred();let signal,cancels=0;
  const f=await fixture(t,{provider:{listModels:()=>[],proposeGain:options=>{signal=options.signal;entered.resolve();return gate.promise;},cancel:()=>cancels++}});
  const u=new URL(f.pairing.endpoint);const req=http.request({host:'127.0.0.1',port:u.port,path:'/v1/proposals',method:'POST',headers:{authorization:'Bearer '+f.pairing.capability,'content-type':'application/json'}},()=>{});
  req.on('error',()=>{});req.end(JSON.stringify(input()));await entered.promise;
  const aborted=new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}));req.destroy();await aborted;
  assert.equal(cancels,1);gate.reject(new Error('synthetic late secret'));await tick();assert.equal((await request(f)).status,200);
});
test('aborted partial request body cannot crash or invoke provider',async t=>{
  const f=await fixture(t);const u=new URL(f.pairing.endpoint);
  const socket=net.connect({host:'127.0.0.1',port:u.port});await new Promise(r=>socket.once('connect',r));
  socket.write(`POST /v1/proposals HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\nAuthorization: Bearer ${f.pairing.capability}\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{`);
  await tick();socket.destroy();await tick();await tick();assert.equal(f.calls.length,0);assert.equal((await request(f)).status,200);
});
for(const stage of ['status','models','proposal']) test('absolute timeout bounds uncooperative '+stage,async t=>{
  const never=()=>new Promise(()=>{});let cancelled=0;let signal;
  const hang=options=>{signal=options.signal;return never();};
  const f=await fixture(t,{requestTimeoutMs:40,status:stage==='status'?hang:()=>({status:'connected',sharing:true}),provider:{listModels:stage==='models'?hang:()=>[],proposeGain:hang,cancel:()=>cancelled++}});
  const result=await request(f,{path:stage==='status'?'/v1/status':stage==='models'?'/v1/models':'/v1/proposals',method:stage==='proposal'?'POST':'GET',...(stage==='proposal'?{body:input()}:{})});
  assert.equal(result.status,504);assert.equal(signal.aborted,true);assert.equal(cancelled,stage==='status'?0:1);
});
test('partial body has an absolute timeout and no provider call',async t=>{
  const f=await fixture(t,{requestTimeoutMs:40});const result=await raw(f,'Content-Length: 100\r\nContent-Type: application/json\r\n','/v1/proposals','POST','{');assert.match(result,/^HTTP\/1\.1 504/);assert.equal(f.calls.length,0);
});
test('pairing expiry invalidates active work and refuses later callbacks',async t=>{
  let time=1000;const entered=deferred(),gate=deferred();let cancels=0;
  const f=await fixture(t,{now:()=>time,lifetimeMs:1000,provider:{listModels:()=>[],proposeGain:()=>{entered.resolve();return gate.promise;},cancel:()=>cancels++}});
  const pending=request(f,{path:'/v1/proposals',method:'POST',body:input()});await entered.promise;time=2000;
  assert.equal((await request(f)).status,401);assert.equal((await pending).json.error,'cancelled');assert.equal(cancels,1);
  gate.resolve({requestId:id,proposal});await tick();assert.equal((await request(f,{path:'/v1/models'})).status,401);
});
test('wall clock lifetime closes idle listening socket',async t=>{
  const f=await fixture(t,{lifetimeMs:25});await new Promise(r=>setTimeout(r,50));await assert.rejects(request(f));await f.stop();
});
test('stop closes sockets, is idempotent, bounds ignored abort and observes late rejection',async t=>{
  const entered=deferred(),gate=deferred();let cancels=0,signal;
  const f=await fixture(t,{provider:{listModels:options=>{signal=options.signal;entered.resolve();return gate.promise;},proposeGain:()=>{},cancel:()=>cancels++}});
  const pending=request(f,{path:'/v1/models'}).then(()=>assert.fail('No completed reply after stop'),()=>{});await entered.promise;
  await Promise.all([f.stop(),f.stop()]);await pending;assert.equal(signal.aborted,true);assert.equal(cancels,1);await assert.rejects(request(f));
  gate.reject(new Error('SYNTHETIC LATE PRIVATE VALUE'));await tick();
});
test('stop from dependency before returned rejection cannot leak unhandled rejection',async t=>{
  let f;f=await fixture(t,{status:()=>{void f.stop();return Promise.reject(new Error('SYNTHETIC PRIVATE VALUE'));}});
  await assert.rejects(request(f));await f.stop();await tick();
});
for(const bad of [{status:'connected',sharing:true,accessToken:'PRIVATE'}, {status:'reauth_required',sharing:true},{status:'connected',sharing:1}]) test('status output cannot leak extra keys or invalid values',async t=>{
  const f=await fixture(t,{status:()=>bad});const result=await request(f);assert.equal(result.status,502);assert.ok(!result.text.includes('PRIVATE'));
});
test('oversized or credential-bearing model output is rejected safely',async t=>{
  for(const models of [[{slug:'x',displayName:'x'.repeat(262145)}],[{slug:'x',displayName:'x',accessToken:'PRIVATE'}]]) {
    const f=await fixture(t,{provider:{listModels:()=>models,proposeGain:()=>{},cancel:()=>{}}});const result=await request(f,{path:'/v1/models'});assert.equal(result.status,502);assert.ok(result.text.length<1000);assert.ok(!result.text.includes('PRIVATE'));
  }
});
for(const returned of [{requestId:id,proposal,accessToken:'PRIVATE'},{requestId:other,proposal},{requestId:id,proposal:{operations:[{kind:'gain',track_id:other,value:0.7}]}},{requestId:id,proposal:{operations:[{kind:'gain',track_id:track,value:NaN}]}}]) test('invalid provider proposal cannot reach iOS',async t=>{
  const f=await fixture(t,{provider:{listModels:()=>[],proposeGain:()=>returned,cancel:()=>{}}});const result=await request(f,{path:'/v1/proposals',method:'POST',body:input()});assert.equal(result.status,502);assert.ok(!result.text.includes('PRIVATE'));
});
test('provider raw error text and causes never enter local reply',async t=>{
  const f=await fixture(t,{status:()=>{throw new Error('SYNTHETIC SECRET',{cause:'PRIVATE'});}});const result=await request(f);assert.equal(result.status,503);assert.ok(!/SECRET|PRIVATE|cause/.test(result.text));
});
test('real reviewed provider catalog survives status and successful proposal routes',async t=>{
  let posts=0,reservations=0;
  const selected={activationId:'fixture-active',profileId:'fixture-profile',subject:'fixture-subject',scopes:['resource.invoke','chatgpt.tokens.use.direct'],credentials:{tokenType:'Bearer',accessToken:'SYNTHETIC-NOT-A-TOKEN',expiresAt:Date.now()+3600000}};
  const provider=createMusicProvider({getActiveSession:()=>selected,reserveRequest:()=>{reservations++;return true;},readProposal:async body=>{await body.cancel();return proposal;},fetchImpl:async url=>{if(url.endsWith('/models'))return new Response(JSON.stringify({models:[{slug:'test-model',display_name:'Test model',visibility:'list'}]}));posts++;return new Response('synthetic');}});
  const f=await fixture(t,{provider});assert.equal((await request(f,{path:'/v1/models'})).status,200);assert.equal((await request(f)).status,200);
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).status,200);assert.equal(posts,1);assert.equal(reservations,1);
});
test('invalid factory configuration fails without listening',async()=>{
  for(const options of [{},{provider:{},status:()=>{}},{provider:{listModels(){},proposeGain(){},cancel(){}},status:()=>{},lifetimeMs:900001},{provider:{listModels(){},proposeGain(){},cancel(){}},status:()=>{},requestTimeoutMs:45001}]) await assert.rejects(startLocalMusicServer(options));
});


test('successful proposal UUID cannot be replayed even with different user text',async t=>{
  const f=await fixture(t);assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).status,200);
  const changed={...input(),user_text:'Different request'};
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:changed})).json.error,'duplicate_request');
  assert.equal(f.calls.filter(x=>x.kind==='proposal').length,1);
});
test('invalid local envelope does not consume a valid later request ID',async t=>{
  const f=await fixture(t);assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:{...input(),user_text:''}})).status,400);
  assert.equal((await request(f,{path:'/v1/proposals',method:'POST',body:input()})).status,200);assert.equal(f.calls.length,1);
});
test('old cancelled dependency completion cannot release a replacement active owner',async t=>{
  const first=deferred(),second=deferred(),enteredFirst=deferred(),enteredSecond=deferred();let calls=0;
  const f=await fixture(t,{provider:{listModels:()=>[],proposeGain:()=>{calls++;if(calls===1){enteredFirst.resolve();return first.promise;}enteredSecond.resolve();return second.promise;},cancel:()=>{}}});
  const old=request(f,{path:'/v1/proposals',method:'POST',body:input()});await enteredFirst.promise;
  await request(f,{path:'/v1/proposals/'+id,method:'DELETE'});assert.equal((await old).json.error,'cancelled');
  const nextInput=input();nextInput.request_id=other;nextInput.project.request_id=other;
  const current=request(f,{path:'/v1/proposals',method:'POST',body:nextInput});await enteredSecond.promise;
  first.resolve({requestId:id,proposal});await tick();assert.equal((await request(f)).json.error,'busy');assert.equal(calls,2);
  second.resolve({requestId:other,proposal});assert.equal((await current).status,200);
});
test('DELETE never cancels unrelated model discovery',async t=>{
  const entered=deferred(),gate=deferred();let cancels=0;
  const f=await fixture(t,{provider:{listModels:()=>{entered.resolve();return gate.promise;},proposeGain:()=>{},cancel:()=>cancels++}});
  const pending=request(f,{path:'/v1/models'});await entered.promise;
  assert.deepEqual((await request(f,{path:'/v1/proposals/'+id,method:'DELETE'})).json,{version:1,cancelled:false});assert.equal(cancels,0);
  gate.resolve([{slug:'test-model',displayName:'Test model'}]);assert.equal((await pending).status,200);
});
test('stop can be reentered by provider cancellation without deadlock',async t=>{
  const entered=deferred();let f,stops=0;
  f=await fixture(t,{provider:{listModels:()=>{entered.resolve();return new Promise(()=>{});},proposeGain:()=>{},cancel:()=>{stops++;return f.stop();}}});
  const pending=request(f,{path:'/v1/models'}).catch(()=>{});await entered.promise;await f.stop();await pending;assert.equal(stops,1);
});
test('idle stop and pairing expiry never clear an idle provider catalog',async t=>{
  const f=await fixture(t);await request(f,{path:'/v1/models'});await f.stop();assert.equal(f.cancels,0);
});
test('all incomplete header connections are closed when stop resolves',async t=>{
  const f=await fixture(t);const u=new URL(f.pairing.endpoint);const sockets=[];
  for(let i=0;i<4;i++){
    const socket=net.connect({host:'127.0.0.1',port:u.port});socket.on('error',()=>{});await new Promise(r=>socket.once('connect',r));socket.write('GET /v1/status HTTP/1.1\r\n');sockets.push(socket);
  }
  const closed=Promise.all(sockets.map(socket=>new Promise(r=>socket.once('close',r))));await f.stop();await closed;assert.equal(f.calls.length,0);
});
test('partial headers time out without invoking application callbacks',async t=>{
  const f=await fixture(t,{requestTimeoutMs:40});const u=new URL(f.pairing.endpoint);
  const socket=net.connect({host:'127.0.0.1',port:u.port});socket.on('error',()=>{});await new Promise(r=>socket.once('connect',r));
  const closed=new Promise(r=>socket.once('close',r));socket.write('GET /v1/status HTTP/1.1\r\n');await closed;assert.equal(f.calls.length,0);
});


test('model labels reject Unicode control/format characters as the iOS client does',async t=>{
  const f=await fixture(t,{provider:{listModels:()=>[{slug:'valid',displayName:'Hidden\u200bformat'}],proposeGain:()=>{},cancel:()=>{}}});
  assert.equal((await request(f,{path:'/v1/models'})).status,502);
});
test('GET and DELETE bodies are rejected before callbacks or cancellation',async t=>{
  const f=await fixture(t);
  for(const [method,path] of [['GET','/v1/status'],['DELETE','/v1/proposals/'+id]]){
    const result=await request(f,{method,path,headers:{'content-length':'2'},body:'{}'});assert.equal(result.status,400);
  }
  assert.equal(f.calls.length,0);assert.equal(f.cancels,0);
});
