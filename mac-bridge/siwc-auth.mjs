/**
 * Independently authored SIWC public-client grant adapter.
 * Protocol: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
 * No credential persistence, refresh, inference, or automatic browser launch lives here.
 */
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { createLocalJWKSet, jwtVerify } from 'jose';

const ISSUER = 'https://auth.openai.com';
const AUTHORIZE = `${ISSUER}/api/accounts/authorize`;
const TOKEN = `${ISSUER}/api/accounts/oauth/token`;
const DISCOVERY = `${ISSUER}/.well-known/openid-configuration`;
const RESOURCE = 'https://api.openai.com/v1';
const CALLBACK = '/auth/callback';
const SCOPES = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
const MESSAGES = Object.freeze({
  invalid_config: 'The sign-in configuration is invalid.',
  authorization_busy: 'A sign-in attempt is already running.',
  authorization_timeout: 'The sign-in attempt expired. Start again when ready.',
  cancelled: 'Sign-in was cancelled.',
  callback_unavailable: 'The local sign-in callback could not be started.',
  invalid_callback: 'The sign-in callback could not be verified.',
  access_denied: 'ChatGPT sign-in was not authorized.',
  authorization_failed: 'ChatGPT sign-in could not be completed.',
  invalid_grant: 'The authorization code was rejected. Sign in again using the saved registration.',
  storage_unavailable: 'Protected credential storage is unavailable. Existing account data was preserved.',
  registration_not_found: 'The selected registration could not be found.',
  invalid_registration: 'The selected registration could not be verified.',
  invalid_token_response: 'ChatGPT returned an incomplete credential response.',
  invalid_identity: 'The ChatGPT identity could not be verified.',
  account_mismatch: 'This sign-in belongs to a different account than the selected registration.',
  invalid_discovery: 'The ChatGPT signing-key configuration could not be verified.',
  request_timeout: 'The sign-in service request timed out.',
  response_too_large: 'The sign-in service response exceeded its size limit.',
  invalid_remote_response: 'The sign-in service returned an invalid response.',
  remote_rejected: 'The sign-in service rejected the request.',
  remote_unavailable: 'The sign-in service could not be reached.',
  browser_unavailable: 'The system browser could not be opened.',
});

/** Errors deliberately contain no upstream response, URL, token, or original cause. */
export class SIWCGrantError extends Error {
  constructor(code) {
    super(MESSAGES[code] ?? MESSAGES.authorization_failed);
    this.name = 'SIWCGrantError';
    this.code = Object.hasOwn(MESSAGES, code) ? code : 'authorization_failed';
  }
}
const fail = code => new SIWCGrantError(code);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const boundedString = (value, max) => typeof value === 'string' && value.length > 0 && Buffer.byteLength(value) <= max;
const validClient = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,200}$/.test(value) && value !== 'dynamic_agent_client';
const validProfile = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,100}$/.test(value);
const validSecret = value => boundedString(value, 16_384) && !/[\u0000-\u0020\u007f]/.test(value);
const randomSecret = () => randomBytes(32).toString('base64url');
const abortError = signal => signal.reason instanceof SIWCGrantError ? signal.reason : fail('cancelled');

function checkAbort(signal) { if (signal.aborted) throw abortError(signal); }
function abortable(promise, signal) {
  const supplied = Promise.resolve(promise);
  if (signal.aborted) {
    void supplied.catch(() => {});
    return Promise.reject(abortError(signal));
  }
  return new Promise((resolve, reject) => {
    const abort = () => reject(abortError(signal));
    signal.addEventListener('abort', abort, { once: true });
    supplied.then(resolve, reject).finally(() => signal.removeEventListener('abort', abort));
  });
}
function authURL(value) {
  try {
    const url = new URL(value);
    if (url.origin !== ISSUER || url.username || url.password || url.hash) throw new Error();
    return url.href;
  } catch { throw fail('invalid_discovery'); }
}

/**
 * repository is trusted Mac-only code, never a simulator RPC implementation:
 *   getRegistration(profileId) -> {profileId,clientId,hostId,issuer,subject?} | undefined
 *   savePendingRegistration(metadata, {signal}) -> void
 *   activateVerified(record, {signal}) -> void
 * Writes must be atomic; activateVerified must check signal immediately at its commit
 * boundary. A pending write must not replace the active account. The token-bearing
 * record is delivered only to activateVerified, never returned to UI callers.
 * resolveKey is a trusted JOSE key resolver test/integration seam, not a URL option.
 */
export function createSIWCGrant({
  repository, hostId, appName = 'Loopa', fetchImpl = globalThis.fetch,
  openBrowser, now = Date.now, resolveKey,
  requestTimeoutMs = 10_000, grantTimeoutMs = 180_000,
} = {}) {
  if (!repository || ['getRegistration', 'savePendingRegistration', 'activateVerified'].some(name => typeof repository[name] !== 'function') ||
      typeof hostId !== 'string' || !/^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(hostId) ||
      !boundedString(appName, 120) || appName.trim() !== appName || /[\u0000-\u001f\u007f]/.test(appName) ||
      typeof fetchImpl !== 'function' || typeof now !== 'function' ||
      (openBrowser !== undefined && typeof openBrowser !== 'function') || (resolveKey !== undefined && typeof resolveKey !== 'function') ||
      !Number.isInteger(requestTimeoutMs) || requestTimeoutMs < 1 || requestTimeoutMs > 10_000 ||
      !Number.isInteger(grantTimeoutMs) || grantTimeoutMs < 1 || grantTimeoutMs > 180_000) throw fail('invalid_config');
  let active;

  async function remoteJSON(url, init, signal, maxBytes = 65_536) {
    const timeout = new AbortController();
    const timer = setTimeout(() => timeout.abort(fail('request_timeout')), requestTimeoutMs);
    const combined = AbortSignal.any([signal, timeout.signal]);
    let reader; let response;
    try {
      checkAbort(combined);
      response = await abortable(fetchImpl(url, { ...init, redirect: 'error', signal: combined }), combined);
      if (!response || typeof response.status !== 'number' || !response.body || (response.url && response.url !== url)) throw fail('invalid_remote_response');
      if (response.status >= 300 && response.status < 400) throw fail('remote_rejected');
      const declared = response.headers.get('content-length');
      if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) throw fail('response_too_large');
      reader = response.body.getReader();
      const chunks = []; let size = 0;
      for (;;) {
        const { done, value } = await abortable(reader.read(), combined);
        if (done) break;
        size += value.byteLength;
        if (size > maxBytes) throw fail('response_too_large');
        chunks.push(value);
      }
      let data;
      try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
      catch { throw fail('invalid_remote_response'); }
      if (!response.ok) {
        if (url === TOKEN && data?.error === 'invalid_grant') throw fail('invalid_grant');
        throw fail('remote_rejected');
      }
      if (!object(data)) throw fail('invalid_remote_response');
      return data;
    } catch (error) {
      if (combined.aborted) throw abortError(combined);
      if (error instanceof SIWCGrantError) throw error;
      throw fail('remote_unavailable');
    } finally {
      clearTimeout(timer);
      if (reader) {
        // Do not let an uncooperative transport stall cancellation cleanup.
        void reader.cancel().catch(() => {});
        reader.releaseLock();
      } else if (response?.body) {
        void response.body.cancel().catch(() => {});
      }
    }
  }

  async function verifiedIdentity(idToken, clientId, nonce, signal) {
    let resolver = resolveKey;
    if (!resolver) {
      const discovery = await remoteJSON(DISCOVERY, { headers: { accept: 'application/json' } }, signal);
      if (discovery.issuer !== ISSUER || typeof discovery.jwks_uri !== 'string') throw fail('invalid_discovery');
      const url = authURL(discovery.jwks_uri);
      const jwks = await remoteJSON(url, { headers: { accept: 'application/json' } }, signal, 131_072);
      if (!Array.isArray(jwks.keys) || jwks.keys.length < 1 || jwks.keys.length > 32) throw fail('invalid_discovery');
      try { resolver = createLocalJWKSet(jwks); } catch { throw fail('invalid_discovery'); }
    }
    checkAbort(signal);
    try {
      const timestamp = now();
      if (!Number.isSafeInteger(timestamp) || timestamp < 0) throw new Error();
      const { payload } = await abortable(jwtVerify(idToken, resolver, {
        algorithms: ['RS256'], issuer: ISSUER, audience: clientId,
        requiredClaims: ['iss', 'sub', 'aud', 'exp', 'iat', 'nonce'],
        clockTolerance: 5, currentDate: new Date(timestamp),
      }), signal);
      if (!boundedString(payload.sub, 1024) || payload.nonce !== nonce ||
          !Number.isFinite(payload.iat) || payload.iat < 0 || payload.iat > timestamp / 1000 + 5 || payload.iat > payload.exp ||
          (payload.azp !== undefined && payload.azp !== clientId) ||
          (Array.isArray(payload.aud) && payload.aud.length > 1 && payload.azp !== clientId)) throw new Error();
      const identity = {};
      if (boundedString(payload.name, 200) && !/[\u0000-\u001f\u007f]/.test(payload.name)) identity.name = payload.name;
      if (boundedString(payload.email, 320) && !/[\u0000-\u001f\u007f]/.test(payload.email)) identity.email = payload.email;
      return { issuer: ISSUER, subject: payload.sub, identity };
    } catch {
      checkAbort(signal);
      throw fail('invalid_identity');
    }
  }

  async function store(method, value, signal) {
    try { checkAbort(signal); return await abortable(repository[method](value, { signal }), signal); }
    catch { checkAbort(signal); throw fail('storage_unavailable'); }
  }

  return Object.freeze({
    async start({ profileId, signal: callerSignal, port = 0 } = {}) {
      if (active) throw fail('authorization_busy');
      if (!Number.isInteger(port) || port < 0 || port > 65535 || (profileId !== undefined && !validProfile(profileId)) ||
          (callerSignal !== undefined && !(callerSignal instanceof AbortSignal))) throw fail('invalid_config');
      const controller = new AbortController();
      const signal = callerSignal ? AbortSignal.any([callerSignal, controller.signal]) : controller.signal;
      active = controller;
      const timer = setTimeout(() => controller.abort(fail('authorization_timeout')), grantTimeoutMs);
      let server;
      const cleanup = () => {
        clearTimeout(timer);
        server?.close(); server?.closeAllConnections();
        if (active === controller) active = undefined;
      };
      try {
        checkAbort(signal);
        let registration;
        if (profileId !== undefined) {
          registration = await store('getRegistration', profileId, signal);
          if (!registration) throw fail('registration_not_found');
          if (!object(registration) || registration.profileId !== profileId || !validClient(registration.clientId) ||
              registration.hostId !== hostId || registration.issuer !== ISSUER ||
              (registration.subject !== undefined && !boundedString(registration.subject, 1024))) throw fail('invalid_registration');
          registration = structuredClone(registration);
        }
        const id = profileId ?? randomUUID();
        const state = randomSecret(); const nonce = randomSecret(); const verifier = randomSecret();
        let deliver; let rejectCallback; let consumed = false; let origin;
        const callback = new Promise((resolve, reject) => { deliver = resolve; rejectCallback = reject; });
        void callback.catch(() => {});
        server = createServer({ maxHeaderSize: 8192 }, (request, response) => {
          response.setHeader('Cache-Control', 'no-store');
          response.setHeader('Referrer-Policy', 'no-referrer');
          response.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
          const notFound = () => response.writeHead(404).end('Not found');
          const raw = request.url ?? '';
          if (!origin || consumed || request.method !== 'GET' || request.headers.host !== new URL(origin).host ||
              request.headersDistinct.host.length !== 1 ||
              request.socket.remoteAddress !== '127.0.0.1' || raw.split('?', 1)[0] !== CALLBACK || raw.length > 8192) { notFound(); return; }
          let url;
          try { url = new URL(raw, origin); } catch { response.writeHead(400).end('Invalid callback'); return; }
          if (url.origin !== origin || url.hash) { notFound(); return; }
          const provided = Buffer.from(url.searchParams.get('state') ?? ''); const expected = Buffer.from(state);
          if (url.searchParams.getAll('state').length !== 1 || provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
            response.writeHead(400).end('Invalid sign-in state'); return;
          }
          consumed = true;
          const reject = code => { response.writeHead(400).end('Sign-in was not completed'); rejectCallback(fail(code)); };
          if ([...url.searchParams.keys()].some(key => url.searchParams.getAll(key).length !== 1)) { reject('invalid_callback'); return; }
          if (url.searchParams.has('error')) {
            if (url.searchParams.has('code')) { reject('invalid_callback'); return; }
            reject(url.searchParams.get('error') === 'access_denied' ? 'access_denied' : 'authorization_failed'); return;
          }
          const code = url.searchParams.get('code');
          const returnedClient = url.searchParams.get('client_id');
          const clientId = returnedClient ?? registration?.clientId;
          if (!boundedString(code, 4096) || !validClient(clientId) ||
              (registration && returnedClient !== null && returnedClient !== registration.clientId)) { reject('invalid_callback'); return; }
          response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Return to Loopa. Your connection is being verified.');
          deliver({ code, clientId });
        });
        server.requestTimeout = 10_000; server.headersTimeout = 5_000;
        server.keepAliveTimeout = 1_000; server.maxConnections = 4; server.maxRequestsPerSocket = 1;
        server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
        await abortable(new Promise((resolve, reject) => {
          server.once('error', reject);
          server.listen({ host: '127.0.0.1', port }, () => { server.removeListener('error', reject); resolve(); });
        }), signal).catch(() => { checkAbort(signal); throw fail('callback_unavailable'); });
        server.on('error', () => controller.abort(fail('callback_unavailable')));
        origin = `http://127.0.0.1:${server.address().port}`;
        const redirectUri = `${origin}${CALLBACK}`;
        const url = new URL(AUTHORIZE);
        url.search = new URLSearchParams({
          client_id: registration?.clientId ?? 'dynamic_agent_client',
          response_type: 'code', redirect_uri: redirectUri, scope: SCOPES, resource: RESOURCE,
          state, nonce, code_challenge_method: 'S256',
          code_challenge: createHash('sha256').update(verifier).digest('base64url'),
          ext_agent_host_id: hostId,
          ...(registration ? {} : { agent_name_hint: appName }),
        }).toString();

        const completion = (async () => {
          const received = await abortable(callback, signal);
          const pending = { version: 1, profileId: id, clientId: received.clientId, hostId, issuer: ISSUER,
            ...(registration?.subject ? { subject: registration.subject } : {}) };
          await store('savePendingRegistration', pending, signal);
          const data = await remoteJSON(TOKEN, {
            method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
            body: new URLSearchParams({ grant_type: 'authorization_code', client_id: received.clientId,
              code: received.code, code_verifier: verifier, redirect_uri: redirectUri, resource: RESOURCE }),
          }, signal);
          const receivedAt = now();
          if (!boundedString(data.scope, 4096) || !boundedString(data.id_token, 16_384) ||
              !validSecret(data.access_token) || typeof data.token_type !== 'string' || data.token_type.toLowerCase() !== 'bearer' ||
              !Number.isSafeInteger(receivedAt) || typeof data.expires_in !== 'number' || !Number.isFinite(data.expires_in) || data.expires_in <= 0 ||
              !Number.isSafeInteger(receivedAt + data.expires_in * 1000)) throw fail('invalid_token_response');
          const scopes = [...new Set(data.scope.trim().split(/\s+/))];
          if (scopes.some(scope => !/^[\x21\x23-\x5b\x5d-\x7e]+$/.test(scope)) ||
              (scopes.includes('offline_access') && !validSecret(data.refresh_token)) ||
              (data.refresh_token !== undefined && !validSecret(data.refresh_token))) throw fail('invalid_token_response');
          const identity = await verifiedIdentity(data.id_token, received.clientId, nonce, signal);
          if (registration?.subject && identity.subject !== registration.subject) throw fail('account_mismatch');
          const record = { ...pending, ...identity, receivedAt, scopes,
            credentials: { accessToken: data.access_token, idToken: data.id_token, tokenType: 'Bearer',
              expiresAt: receivedAt + data.expires_in * 1000,
              ...(data.refresh_token ? { refreshToken: data.refresh_token } : {}) } };
          await store('activateVerified', record, signal);
          return { status: 'connected', sharing: scopes.includes('chatgpt.tokens.use.direct') && scopes.includes('resource.invoke'),
            profileId: id, identity: structuredClone(identity.identity) };
        })().catch(error => {
          if (error instanceof SIWCGrantError) throw error;
          checkAbort(signal); throw fail('authorization_failed');
        }).finally(cleanup);
        void completion.catch(() => {});
        if (openBrowser) {
          // Launch completion is not the OAuth completion boundary. Some browser
          // adapters remain pending after a valid callback; return the cancellable
          // handle immediately and let only an active launch failure abort its grant.
          void Promise.resolve().then(() => openBrowser(url.href)).catch(() => {
            if (active === controller && !signal.aborted) controller.abort(fail('browser_unavailable'));
          });
        }
        return Object.freeze({ authorizationUrl: url.href, redirectUri, completion,
          cancel: () => controller.abort(fail('cancelled')) });
      } catch (error) {
        cleanup();
        if (error instanceof SIWCGrantError) throw error;
        checkAbort(signal); throw fail('authorization_failed');
      }
    },
  });
}
