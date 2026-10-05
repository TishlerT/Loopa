import http from 'node:http';
import {randomBytes, timingSafeEqual} from 'node:crypto';

const MAX_BODY = 16_384, MAX_REPLY = 262_144, MAX_HEADERS = 8_192;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STATES = new Set(['connected','disconnected','connecting','reconnect_required','usage_unavailable']);
const SLUG = /^[a-zA-Z0-9][a-zA-Z0-9._:-]*$/;
const errors = Object.freeze({
  unauthorized: [401, 'Pair with the local Mac assistant again.'],
  invalid_request: [400, 'The local request is invalid.'],
  not_found: [404, 'This local route is unavailable.'],
  busy: [409, 'Another assistant request is still running.'],
  duplicate_request: [409, 'This request has already been attempted.'],
  too_large: [413, 'The local request exceeds its size limit.'],
  cancelled: [409, 'The request was cancelled.'],
  timeout: [504, 'The local assistant took too long.'],
  unavailable: [503, 'The local assistant is unavailable.'],
  invalid_response: [502, 'The assistant returned an unusable response.'],
});
class LocalError extends Error { constructor(code) { super(code); this.code = code; } }
const fail = code => new LocalError(code);
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const exact = (x, keys) => object(x) && Object.keys(x).sort().join('|') === [...keys].sort().join('|');
const text = (x, bytes) => typeof x === 'string' && x.trim().length > 0 && Buffer.byteLength(x) <= bytes;
const check = signal => { if (signal.aborted) throw signal.reason; };

// Observe every promise, including dependencies that synchronously abort then reject.
// The deferred check prevents a callback from starting after stop/cancellation.
function boundedCall(callback, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, {once:true});
    Promise.resolve().then(() => { check(signal); return callback(); })
      .then(resolve, reject).finally(() => signal.removeEventListener('abort', abort));
    if (signal.aborted) abort();
  });
}
function readBody(request, signal) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    const clean = () => {
      request.off('data', data); request.off('end', end); request.off('error', error);
      signal.removeEventListener('abort', abort);
    };
    const error = () => { clean(); reject(fail('invalid_request')); };
    const abort = () => { clean(); reject(signal.reason); };
    const data = chunk => {
      size += chunk.length;
      if (size > MAX_BODY || chunks.length >= 4096) { clean(); reject(fail('too_large')); return; }
      chunks.push(chunk);
    };
    const end = () => {
      clean();
      try { resolve(JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(Buffer.concat(chunks)))); }
      catch { reject(fail('invalid_request')); }
    };
    request.on('data', data); request.once('end', end); request.once('error', error);
    signal.addEventListener('abort', abort, {once:true});
    if (signal.aborted) abort();
  });
}
function statusValue(value) {
  if (!exact(value, ['status','sharing']) || !STATES.has(value.status) || typeof value.sharing !== 'boolean') throw fail('invalid_response');
  return {version:1,status:value.status,sharing:value.sharing};
}
function modelsValue(value) {
  if (!Array.isArray(value) || !value.length || value.length > 100) throw fail('invalid_response');
  const seen = new Set();
  const models = value.map(item => {
    if (!exact(item, ['slug','displayName']) || !text(item.slug,128) || !SLUG.test(item.slug) || seen.has(item.slug) ||
        !text(item.displayName,128) || /[\p{Cc}\p{Cf}]/u.test(item.displayName)) throw fail('invalid_response');
    seen.add(item.slug); return {slug:item.slug,display_name:item.displayName};
  });
  return {version:1,models};
}
function proposalInput(value) {
  if (!exact(value,['request_id','user_text','project','model']) || typeof value.request_id !== 'string' || !UUID.test(value.request_id) ||
      !text(value.user_text,2048) || !text(value.model,128) || !SLUG.test(value.model) || !object(value.project) ||
      value.project.request_id !== value.request_id || !object(value.project.track) ||
      typeof value.project.track.id !== 'string' || !UUID.test(value.project.track.id)) throw fail('invalid_request');
  return value;
}
function proposalValue(value, input) {
  if (!exact(value,['requestId','proposal']) || value.requestId !== input.request_id || !exact(value.proposal,['operations']) ||
      !Array.isArray(value.proposal.operations) || value.proposal.operations.length !== 1) throw fail('invalid_response');
  const operation = value.proposal.operations[0];
  if (!exact(operation,['kind','track_id','value']) || operation.kind !== 'gain' || typeof operation.track_id !== 'string' ||
      operation.track_id.toLowerCase() !== input.project.track.id.toLowerCase() || !Number.isFinite(operation.value) ||
      operation.value < 0 || operation.value > 1) throw fail('invalid_response');
  return {version:1,request_id:input.request_id,proposal:{operations:[{kind:'gain',track_id:operation.track_id,value:operation.value}]}};
}

/**
 * Trusted launcher API. Pairing contains only this local capability, never OAuth credentials.
 * expiresAt is Unix milliseconds; the iOS launcher converts it to Date. Never print pairing.
 * provider is the reviewed single-owner music provider; status({signal}) returns {status,sharing}.
 * Dependency promises may finish after cancellation, but cannot publish or start later callbacks.
 */
export async function startLocalMusicServer({provider, status, now = Date.now,
  lifetimeMs = 900_000, requestTimeoutMs = 45_000} = {}) {
  if (!provider || ['listModels','proposeGain','cancel'].some(k => typeof provider[k] !== 'function') || typeof status !== 'function' ||
      typeof now !== 'function' || !Number.isInteger(lifetimeMs) || lifetimeMs < 1 || lifetimeMs > 900_000 ||
      !Number.isInteger(requestTimeoutMs) || requestTimeoutMs < 1 || requestTimeoutMs > 45_000) throw fail('invalid_request');
  const createdAt = now();
  if (!Number.isSafeInteger(createdAt) || createdAt < 0 || !Number.isSafeInteger(createdAt+lifetimeMs)) throw fail('invalid_request');
  const expiresAt = createdAt + lifetimeMs;
  const capability = randomBytes(32).toString('base64url');
  const expectedAuthorization = Buffer.from('Bearer ' + capability);
  const seenRequests = new Set(); const sockets = new Set(); const handlers = new Set();
  let active, closed = false, expired = false, stopPromise, expiryTimer, expectedHost;

  function cancelOperation(operation, code = 'cancelled') {
    if (!operation || operation.controller.signal.aborted) return;
    operation.controller.abort(fail(code));
    if (operation.providerStarted) {
      try { void Promise.resolve(provider.cancel()).catch(() => {}); } catch { /* Safe local cancellation still wins. */ }
    }
  }
  function paired() {
    if (closed || expired) return false;
    const timestamp = now();
    if (!Number.isSafeInteger(timestamp) || timestamp < createdAt || timestamp >= expiresAt) {
      expired = true; cancelOperation(active); return false;
    }
    return true;
  }
  function send(response, code, value) {
    if (closed || response.destroyed || response.writableEnded) return;
    let body;
    try { body = JSON.stringify(value); } catch { code = 502; body = JSON.stringify({version:1,error:'invalid_response',message:errors.invalid_response[1]}); }
    if (Buffer.byteLength(body) > MAX_REPLY) { code = 502; body = JSON.stringify({version:1,error:'invalid_response',message:errors.invalid_response[1]}); }
    // Bound response delivery too, including rejected/slow-reading clients.
    response.socket?.setTimeout(Math.min(5000,requestTimeoutMs),()=>response.destroy());
    response.writeHead(code, {'content-type':'application/json; charset=utf-8','content-length':Buffer.byteLength(body),
      'cache-control':'no-store','connection':'close','x-content-type-options':'nosniff','cross-origin-resource-policy':'same-origin'});
    response.end(body);
  }
  function sendError(response, error) {
    const code = error instanceof LocalError && Object.hasOwn(errors,error.code) ? error.code :
      error?.code === 'busy' ? 'busy' : error?.code === 'cancelled' ? 'cancelled' : error?.code === 'timeout' ? 'timeout' : 'unavailable';
    send(response, errors[code][0], {version:1,error:code,message:errors[code][1]});
  }
  function authenticate(request) {
    const names = new Set();
    for (let i=0;i<request.rawHeaders.length;i+=2) {
      const name = request.rawHeaders[i].toLowerCase();
      if (names.has(name)) throw fail('invalid_request');
      names.add(name);
    }
    if (request.socket.remoteAddress !== '127.0.0.1' || request.headers.host !== expectedHost ||
        names.has('origin') || names.has('cookie') || names.has('content-encoding') ||
        [...names].some(name => name.startsWith('sec-fetch-')) || request.url.includes('?') || request.url.includes('#')) throw fail('invalid_request');
    const supplied = Buffer.from(request.headers.authorization ?? '');
    if (!paired() || supplied.length !== expectedAuthorization.length || !timingSafeEqual(supplied,expectedAuthorization)) throw fail('unauthorized');
  }
  async function handle(request, response) {
    let operation, timer, disconnected;
    // A client can abort after the body reader has detached its listeners.
    request.on('error', () => {});
    response.on('error', () => { if (operation && active === operation) cancelOperation(operation); });
    try {
      authenticate(request);
      const cancelMatch = /^\/v1\/proposals\/([0-9a-f-]{36})$/i.exec(request.url);
      const route = request.method === 'GET' && request.url === '/v1/status' ? 'status' :
        request.method === 'GET' && request.url === '/v1/models' ? 'models' :
        request.method === 'POST' && request.url === '/v1/proposals' ? 'proposal' :
        request.method === 'DELETE' && cancelMatch && UUID.test(cancelMatch[1]) ? 'cancel' : null;
      if (!route) throw fail('not_found');
      const length = request.headers['content-length'];
      if (length !== undefined && (!/^\d+$/.test(length) || Number(length) > MAX_BODY)) throw fail('too_large');
      if (route !== 'proposal' && (Number(length ?? 0) !== 0 || request.headers['transfer-encoding'])) throw fail('invalid_request');
      if (route === 'proposal' && (request.headers['content-type'] !== 'application/json' ||
          (request.headers['transfer-encoding'] && request.headers['transfer-encoding'] !== 'chunked'))) throw fail('invalid_request');
      if (route === 'cancel') {
        const matches = active?.kind === 'proposal' && active.requestId === cancelMatch[1].toLowerCase() && !active.controller.signal.aborted;
        if (matches) cancelOperation(active);
        send(response,200,{version:1,cancelled:!!matches}); return;
      }
      if (active) throw fail('busy');
      operation = {kind:route, requestId:null, controller:new AbortController(), providerStarted:false};
      active = operation;
      request.socket.setTimeout(0); // The absolute operation timer now owns this connection.
      const signal = operation.controller.signal;
      disconnected = () => { if (!response.writableFinished) cancelOperation(operation); };
      response.once('close',disconnected);
      request.once('aborted',disconnected);
      timer = setTimeout(() => cancelOperation(operation,'timeout'),requestTimeoutMs);
      let output;
      if (route === 'status') output = statusValue(await boundedCall(() => status({signal}),signal));
      else if (route === 'models') output = modelsValue(await boundedCall(() => {
        operation.providerStarted = true; return provider.listModels({signal});
      },signal));
      else {
        const input = proposalInput(await readBody(request,signal));
        check(signal);
        operation.requestId = input.request_id.toLowerCase();
        if (seenRequests.has(operation.requestId) || seenRequests.size >= 256) throw fail('duplicate_request');
        seenRequests.add(operation.requestId);
        output = proposalValue(await boundedCall(() => {
          operation.providerStarted = true;
          return provider.proposeGain({requestId:input.request_id,userText:input.user_text,project:input.project,model:input.model,signal});
        },signal), input);
      }
      check(signal);
      if (!paired() || active !== operation) throw fail('cancelled');
      send(response,200,output);
    } catch (error) { sendError(response,error); }
    finally {
      clearTimeout(timer);
      if (disconnected) { response.off('close',disconnected); request.off('aborted',disconnected); }
      if (active === operation) active = undefined;
    }
  }
  const server = http.createServer({maxHeaderSize:MAX_HEADERS,headersTimeout:Math.min(5000,requestTimeoutMs),
    requestTimeout:requestTimeoutMs,connectionsCheckingInterval:100},(request,response) => {
      const pending = handle(request,response).catch(() => response.destroy()).finally(() => handlers.delete(pending));
      handlers.add(pending);
    });
  server.maxConnections = 16;
  server.maxRequestsPerSocket = 1;
  server.setTimeout(Math.min(5000,requestTimeoutMs),socket => socket.destroy());
  server.on('connection',socket => {
    sockets.add(socket); socket.on('error',()=>{});
    socket.once('close',()=>sockets.delete(socket)); if(closed)socket.destroy();
  });
  server.on('clientError',(_error,socket) => {
    if (socket.destroyed) return;
    if (!socket.writable || socket.writableEnded) { socket.destroy(); return; }
    socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n',()=>socket.destroy());
  });
  server.on('checkContinue',(_request,response)=>sendError(response,fail('invalid_request')));
  server.on('checkExpectation',(_request,response)=>sendError(response,fail('invalid_request')));
  server.on('upgrade',(_request,socket)=>socket.destroy());
  server.on('connect',(_request,socket)=>socket.destroy());
  await new Promise((resolve,reject) => { server.once('error',reject);server.listen(0,'127.0.0.1',()=>{server.off('error',reject);resolve();}); });
  const address = server.address();
  if (!address || address.address !== '127.0.0.1' || address.port < 1024) { server.close();throw fail('unavailable'); }
  expectedHost = `127.0.0.1:${address.port}`;
  function stop() {
    if (stopPromise) return stopPromise;
    let finished;
    stopPromise = new Promise(resolve => { finished = resolve; });
    closed = true; clearTimeout(expiryTimer); cancelOperation(active);
    const socketsClosed = new Promise(resolve => {
      server.close(()=>resolve());
      for (const socket of sockets) socket.destroy();
      server.closeAllConnections();
    });
    // These are the signal-raced handlers, never uncooperative dependency promises.
    void Promise.all([socketsClosed,...handlers]).then(() => finished());
    return stopPromise;
  }
  server.on('error',()=>{void stop();});
  expiryTimer = setTimeout(() => { expired = true; void stop(); },Math.max(0,expiresAt-now()));
  expiryTimer.unref();
  return Object.freeze({pairing:Object.freeze({endpoint:`http://${expectedHost}/`,capability,expiresAt}),stop});
}
