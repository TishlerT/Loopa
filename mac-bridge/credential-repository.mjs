import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {isAbsolute, dirname} from 'node:path';
import {homedir, tmpdir} from 'node:os';

const ISSUER='https://auth.openai.com';
const messages={busy:'The local credential store is busy.',cancelled:'The connection was cancelled.',
  unavailable:'The protected credential store is unavailable.',missing:'No protected connection is stored.',
  denied:'macOS denied access to the protected connection.',corrupt:'The protected connection could not be read safely.',
  conflict:'The protected connection changed. Reconnect before continuing.',invalid_record:'The connection record is invalid.',
  timeout:'The protected credential store took too long.',reconcile_required:'The last credential write was uncertain. Reconcile storage before continuing.',
  invalid_configuration:'The protected credential helper is not configured.'};
export class CredentialRepositoryError extends Error {
  constructor(code){super(messages[code]??messages.unavailable);this.name='CredentialRepositoryError';this.code=Object.hasOwn(messages,code)?code:'unavailable';}
}
const fail=code=>new CredentialRepositoryError(code);
const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const exact=(x,keys)=>object(x)&&Object.keys(x).sort().join('|')===[...keys].sort().join('|');
const text=(x,n)=>typeof x==='string'&&x.length>0&&Buffer.byteLength(x)<=n&&!/[\u0000-\u001f\u007f]/.test(x);
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const host=x=>typeof x==='string'&&x.startsWith('urn:uuid:')&&uuid(x.slice(9));
const clone=x=>structuredClone(x);
function check(signal){if(signal?.aborted)throw fail('cancelled');}
function metadata(x,hostId){
  if(!object(x)||x.version!==1||!text(x.profileId,128)||!text(x.clientId,1024)||x.hostId!==hostId||x.issuer!==ISSUER||
    (x.subject!==undefined&&!text(x.subject,1024)))throw fail('invalid_record');
  return {version:1,profileId:x.profileId,clientId:x.clientId,hostId,issuer:ISSUER,...(x.subject?{subject:x.subject}:{})};
}
function verified(x,hostId){
  const base=metadata(x,hostId);const c=x.credentials;
  if(!text(x.subject,1024)||!object(x.identity)||Buffer.byteLength(JSON.stringify(x.identity))>4096||
    !Number.isSafeInteger(x.receivedAt)||x.receivedAt<=0||!Array.isArray(x.scopes)||x.scopes.length>32||
    x.scopes.some(s=>!text(s,128)||/\s/.test(s))||new Set(x.scopes).size!==x.scopes.length||
    !object(c)||!exact(c,['accessToken','idToken','tokenType','expiresAt',...(c.refreshToken!==undefined?['refreshToken']:[])])||
    c.tokenType!=='Bearer'||!text(c.accessToken,16384)||/\s/.test(c.accessToken)||!text(c.idToken,16384)||
    !Number.isSafeInteger(c.expiresAt)||c.expiresAt<=x.receivedAt||
    (c.refreshToken!==undefined&&(!text(c.refreshToken,16384)||/\s/.test(c.refreshToken))))throw fail('invalid_record');
  return {...base,subject:x.subject,identity:clone(x.identity),receivedAt:x.receivedAt,scopes:[...x.scopes],credentials:clone(c)};
}
function stateRecord(x){
  if(!exact(x,['version','payload'])||x.version!==1||!exact(x.payload,['hostId','registrations','sessions','requests']))throw fail('corrupt');
  const p=x.payload;
  if(!host(p.hostId)||![p.registrations,p.sessions,p.requests].every(Array.isArray)||p.registrations.length>4||p.sessions.length>4||p.requests.length>1)throw fail('corrupt');
  try{
    const registrations=p.registrations.map(r=>metadata(r,p.hostId));
    const sessions=p.sessions.map(r=>verified(r,p.hostId));
    if(new Set(registrations.map(x=>x.profileId)).size!==registrations.length||new Set(sessions.map(x=>x.profileId)).size!==sessions.length)throw fail('corrupt');
    for(const r of sessions){const m=registrations.find(m=>m.profileId===r.profileId);if(!m||m.clientId!==r.clientId||(m.subject&&m.subject!==r.subject))throw fail('corrupt');}
    for(const r of p.requests)if(!exact(r,['requestId','activationId','profileId'])||!uuid(r.requestId)||!uuid(r.activationId)||!text(r.profileId,128))throw fail('corrupt');
    if(Buffer.byteLength(JSON.stringify(x))>65536)throw fail('corrupt');
    return {version:1,payload:{hostId:p.hostId,registrations,sessions,requests:clone(p.requests)}};
  }catch{throw fail('corrupt');}
}

/**
 * One trusted Mac bridge process owns this repository and helper. A launcher must
 * enforce single-process ownership before using it; this is not an interprocess
 * read/modify/write transaction. helperPath is a reviewed app-owned executable,
 * never a URL, user request value or shell command. Tokens travel only in pipes.
 *
 * Persisted sessions are INACTIVE after restart/reconciliation. Only a fresh
 * successful activateVerified in this process grants provider access. Cancellation
 * during an atomic native write may leave a stored record but never activates it.
 */
export function createCredentialRepository({helperPath,spawnImpl=spawn,timeoutMs=5000}={}){
  if(!isAbsolute(helperPath??'')||!text(helperPath,4096)||typeof spawnImpl!=='function'||
    !Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>5000)throw fail('invalid_configuration');
  let childInFlight;let locked=false;let state;let active;let uncertain=false;let epoch=0;
  function helper(request){
    if(childInFlight)throw fail('busy');
    const input=Buffer.from(JSON.stringify(request)+'\n');if(input.length>66560)throw fail('invalid_record');
    return new Promise((resolve,reject)=>{
      let child;let settled=false;let bytes=0;let errorBytes=0;const chunks=[];
      const finish=(error,value)=>{if(settled)return;settled=true;clearTimeout(timer);error?reject(error):resolve(value);};
      const kill=code=>{finish(fail(code));try{child?.kill('SIGKILL');}catch{}};
      const timer=setTimeout(()=>kill('timeout'),timeoutMs);
      try{child=spawnImpl(helperPath,[],{stdio:['pipe','pipe','pipe'],shell:false,cwd:dirname(helperPath),
        env:{PATH:'/usr/bin:/bin',HOME:homedir(),TMPDIR:tmpdir()}});childInFlight=child;}
      catch{finish(fail('unavailable'));return;}
      child.once('error',()=>kill('unavailable'));
      child.once('close',(code,signal)=>{
        if(childInFlight===child)childInFlight=undefined;
        if(settled)return;
        if(signal||![0,1].includes(code)){finish(fail('unavailable'));return;}
        try{
          const raw=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
          if(!raw.endsWith('\n')||raw.slice(0,-1).includes('\n'))throw fail('corrupt');
          const reply=JSON.parse(raw);
          if(code===1&&exact(reply,['ok','error'])&&reply.ok===false){
            const mapped={missing:'missing',denied:'denied',corrupt:'corrupt',conflict:'conflict'};
            finish(fail(mapped[reply.error]??'unavailable'));return;
          }
          if(code!==0||!object(reply)||reply.ok!==true||!exact(reply,['ok',...(request.op==='read'?['record']:[])]))throw fail('corrupt');
          finish(undefined,reply.record);
        }catch(error){finish(error instanceof CredentialRepositoryError?error:fail('corrupt'));}
      });
      if(!child.stdin||!child.stdout||!child.stderr){kill('unavailable');return;}
      child.stdout.on('data',data=>{if(settled)return;bytes+=data.length;if(bytes>65664){kill('corrupt');return;}chunks.push(Buffer.from(data));});
      child.stdout.on('error',()=>kill('unavailable'));child.stderr.on('error',()=>kill('unavailable'));
      child.stderr.on('data',data=>{errorBytes+=data.length;if(errorBytes>4096)kill('unavailable');});
      child.stdin.on('error',()=>kill('unavailable'));
      child.stdin.end(input);
    });
  }
  async function lock(operation){
    if(locked||childInFlight)throw fail('busy');locked=true;
    try{return await operation();}finally{locked=false;}
  }
  async function write(next,signal){
    check(signal);if(uncertain)throw fail('reconcile_required');
    if(Buffer.byteLength(JSON.stringify(next))>65536)throw fail('invalid_record');
    // Once submitted, await native completion. Aborting cannot roll back SecItemUpdate.
    try{await helper({op:'replace',record:next});}
    catch(error){state=undefined;active=undefined;uncertain=true;throw error;}
    state=next;check(signal);
  }
  async function ensure(){
    if(uncertain)throw fail('reconcile_required');if(state)return;
    try{state=stateRecord(await helper({op:'read'}));}
    catch(error){
      if(error.code!=='missing')throw error;
      await write({version:1,payload:{hostId:`urn:uuid:${randomUUID()}`,registrations:[],sessions:[],requests:[]}});
    }
  }
  function bindActive(record,signal){
    check(signal);const value={...clone(record),activationId:randomUUID()};active=value;
    signal?.addEventListener('abort',()=>{if(active===value)active=undefined;},{once:true});
    return value;
  }
  const api={
    async initialize(){return lock(async()=>{await ensure();return {hostId:state.payload.hostId};});},
    async reconcile(){return lock(async()=>{
      epoch++;active=undefined;state=undefined;
      // Read first; absence after an uncertain write never recreates/reset allowance.
      const found=stateRecord(await helper({op:'read'}));state=found;uncertain=false;
      return {hostId:found.payload.hostId};
    });},
    async getRegistration(profileId){return lock(async()=>{
      await ensure();return clone(state.payload.registrations.find(x=>x.profileId===profileId));
    });},
    async savePendingRegistration(record,{signal}={}){return lock(async()=>{
      check(signal);await ensure();check(signal);epoch++;active=undefined;
      const value=metadata(record,state.payload.hostId);const next=clone(state);const list=next.payload.registrations;
      const index=list.findIndex(x=>x.profileId===value.profileId);const old=list[index];
      if(old&&(old.clientId!==value.clientId||(old.subject&&old.subject!==value.subject)))throw fail('conflict');
      if(index<0){if(list.length>=4)throw fail('invalid_record');list.push(value);}else list[index]=value;
      await write(next,signal);
    });},
    async activateVerified(record,{signal}={}){return lock(async()=>{
      check(signal);const activation=++epoch;active=undefined;
      await ensure();check(signal);if(activation!==epoch)throw fail('cancelled');
      const value=verified(record,state.payload.hostId);const next=clone(state);
      const index=next.payload.registrations.findIndex(x=>x.profileId===value.profileId);const m=next.payload.registrations[index];
      if(!m||m.clientId!==value.clientId||(m.subject&&m.subject!==value.subject))throw fail('conflict');
      next.payload.registrations[index]=metadata(value,next.payload.hostId);
      next.payload.sessions=next.payload.sessions.filter(x=>x.profileId!==value.profileId);next.payload.sessions.push(value);
      await write(next,signal);check(signal);if(activation!==epoch)throw fail('cancelled');bindActive(value,signal);
    });},
    getActiveSession(){return !uncertain&&active?clone(active):undefined;},
    async reserveRequest({requestId,activationId,profileId}={}){return lock(async()=>{
      if(!uuid(requestId)||!uuid(activationId)||!text(profileId,128))throw fail('invalid_record');
      if(uncertain||!active||active.activationId!==activationId||active.profileId!==profileId)return false;
      await ensure();
      if(!active||active.activationId!==activationId||state.payload.requests.length>=1)return false;
      const next=clone(state);next.payload.requests.push({requestId,activationId,profileId});
      await write(next);
      return active?.activationId===activationId;
    });},
    async disconnect(){epoch++;active=undefined;return lock(async()=>{
      await ensure();const next=clone(state);next.payload.sessions=[];await write(next);
    });},
  };
  return Object.freeze(api);
}
