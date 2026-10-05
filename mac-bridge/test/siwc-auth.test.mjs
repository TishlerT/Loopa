import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import http from 'node:http';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createSIWCGrant, SIWCGrantError } from '../siwc-auth.mjs';

test('synchronous repository cancellation observes rejection without raw stderr or Node crash',()=>{
  const program=`
    import assert from 'node:assert/strict';
    import {createSIWCGrant} from ${JSON.stringify(new URL('../siwc-auth.mjs',import.meta.url).href)};
    const c=new AbortController();
    const grant=createSIWCGrant({hostId:'urn:uuid:11111111-1111-4111-8111-111111111111',repository:{
      getRegistration(){c.abort();return Promise.reject(new Error('SYNTHETIC-RAW-REPOSITORY-ERROR'));},
      savePendingRegistration(){throw new Error('must not write');},activateVerified(){throw new Error('must not activate');}},
      fetchImpl(){throw new Error('must not access network');}});
    await assert.rejects(grant.start({profileId:'synthetic-profile',signal:c.signal}),{code:'cancelled'});
    await new Promise(r=>setTimeout(r,10));
  `;
  const child=spawnSync(process.execPath,['--input-type=module','--eval',program],{encoding:'utf8',timeout:5000,env:{PATH:process.env.PATH}});
  assert.equal(child.status,0,child.stderr);assert.equal(child.signal,null);assert.equal(child.stderr,'');assert.equal(child.stdout,'');
});

const { privateKey, publicKey } = await generateKeyPair('RS256');
const wrongKeys = await generateKeyPair('RS256');
const jwk = { ...await exportJWK(publicKey), kid: 'fixture-key', use: 'sig', alg: 'RS256' };
const NOW = 1_800_000_000_000;
const HOST = 'urn:uuid:12345678-1234-4234-8234-123456789abc';
const CLIENT = 'oaiapp_loopa_fixture';
const ISSUER = 'https://auth.openai.com';
const SHARING = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

async function fixture(options = {}) {
  const calls = [];
  const pending = [];
  const activated = [];
  const saved = options.saved;
  let attempt; let browserAuthorizationUrl;
  const repository = {
    async getRegistration(id) { assert.equal(id, saved?.profileId); return saved; },
    async savePendingRegistration(record) { pending.push(structuredClone(record)); options.onPending?.(record); },
    async activateVerified(record, { signal }) { signal.throwIfAborted(); activated.push(structuredClone(record)); },
    ...options.repository,
  };
  const tokenBody = async () => {
    const a = new URL(attempt?.authorizationUrl ?? browserAuthorizationUrl);
    const claims = {
      iss: ISSUER, sub: 'fixture-subject', aud: CLIENT,
      iat: NOW / 1000, exp: NOW / 1000 + 600,
      nonce: a.searchParams.get('nonce'), email: 'synthetic@example.invalid',
      ...options.claims,
    };
    for (const key of options.omitClaims ?? []) delete claims[key];
    const idToken = await new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'fixture-key' }).sign(options.wrongSignature ? wrongKeys.privateKey : privateKey);
    return { access_token: 'synthetic-access-never-real', refresh_token: 'synthetic-refresh-never-real', id_token: idToken,
      token_type: 'Bearer', expires_in: 3600, scope: SHARING, ...options.tokens };
  };
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    assert.equal(init.redirect, 'error');
    assert.equal(new URL(url).origin, ISSUER, 'unmocked network must fail');
    if (options.fetchOverride) return options.fetchOverride(url, init, tokenBody);
    if (url === `${ISSUER}/api/accounts/oauth/token`) {
      assert.equal(pending.length, 1, 'issued registration must persist before exchange');
      return Response.json(await tokenBody());
    }
    if (url === `${ISSUER}/.well-known/openid-configuration`) {
      return Response.json({ issuer: ISSUER, jwks_uri: `${ISSUER}/.well-known/jwks.json`, ...options.discovery });
    }
    if (url === `${ISSUER}/.well-known/jwks.json`) return Response.json({ keys: [jwk] });
    throw new Error('UNMOCKED NETWORK');
  };
  const grant = createSIWCGrant({ repository, hostId: HOST, appName: 'Loopa', fetchImpl, now: () => NOW,
    ...(options.useDiscovery ? {} : { resolveKey: async () => publicKey }),
    ...options.config,
    ...(options.config?.openBrowser ? { openBrowser(url) { browserAuthorizationUrl = url; return options.config.openBrowser(url); } } : {}),
  });
  attempt = await grant.start({ profileId: saved?.profileId, ...options.start });
  const callback = async (overrides = {}, request = {}) => {
    const a = new URL(attempt.authorizationUrl);
    const u = new URL(attempt.redirectUri);
    u.search = new URLSearchParams({ state: a.searchParams.get('state'), code: 'synthetic-code', client_id: CLIENT, ...overrides }).toString();
    if (request.query) u.search = request.query;
    return sendCallback(u, request);
  };
  return { grant, attempt, calls, pending, activated, callback, tokenBody };
}

function sendCallback(url, { method = 'GET', host, path } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port: url.port, method,
      path: path ?? url.pathname + url.search, headers: { Host: host ?? url.host } }, res => {
      res.resume(); res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject); req.end();
  });
}
const rejectsCode = (promise, code) => assert.rejects(promise, e => {
  assert.ok(e instanceof SIWCGrantError); assert.equal(e.code, code);
  assert.doesNotMatch(e.message, /synthetic-|server-secret|UNMOCKED/); return true;
});

// No test starts a browser, authenticates an account, or contacts a public service.
test('fresh authorization uses independent PKCE/state/nonce and loopback binding', async () => {
  const f = await fixture();
  try {
    const url = new URL(f.attempt.authorizationUrl);
    assert.equal(url.origin, ISSUER); assert.equal(url.pathname, '/api/accounts/authorize');
    assert.equal(url.searchParams.get('client_id'), 'dynamic_agent_client');
    assert.equal(url.searchParams.get('ext_agent_host_id'), HOST);
    assert.equal(url.searchParams.get('agent_name_hint'), 'Loopa');
    assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
    assert.equal(url.searchParams.get('scope'), SHARING);
    assert.equal(url.searchParams.get('resource'), 'https://api.openai.com/v1');
    assert.equal(new URL(f.attempt.redirectUri).hostname, '127.0.0.1');
    assert.equal(new URL(f.attempt.redirectUri).pathname, '/auth/callback');
    assert.equal(url.searchParams.get('state').length, 43);
    assert.notEqual(url.searchParams.get('state'), url.searchParams.get('nonce'));
    assert.equal(f.calls.length, 0);
  } finally { f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled'); }
});

test('verified grant activates exactly once and exposes only a safe session', async () => {
  const f = await fixture(); await f.callback(); const result = await f.attempt.completion;
  assert.equal(result.status, 'connected'); assert.equal(result.sharing, true);
  assert.equal(f.activated.length, 1); assert.equal(f.pending.length, 1);
  const record = f.activated[0];
  assert.equal(record.subject, 'fixture-subject'); assert.equal(record.clientId, CLIENT);
  assert.equal(record.credentials.accessToken, 'synthetic-access-never-real');
  assert.equal(record.credentials.refreshToken, 'synthetic-refresh-never-real');
  assert.equal(record.credentials.expiresAt, NOW + 3600_000);
  assert.doesNotMatch(JSON.stringify(result), /synthetic-access|synthetic-refresh|idToken|credentials/);
  const exchange = f.calls[0]; const body = new URLSearchParams(exchange.init.body);
  assert.equal(body.get('client_id'), CLIENT); assert.equal(body.get('redirect_uri'), f.attempt.redirectUri);
  assert.equal(body.get('resource'), 'https://api.openai.com/v1');
  assert.equal(createHash('sha256').update(body.get('code_verifier')).digest('base64url'), new URL(f.attempt.authorizationUrl).searchParams.get('code_challenge'));
});

test('default JWT resolver verifies bounded discovery and JWKS without network escape', async () => {
  const f = await fixture({ useDiscovery: true }); await f.callback(); await f.attempt.completion;
  assert.equal(f.calls.length, 3); assert.equal(f.activated.length, 1);
});

for (const [name, claims, omitClaims, wrongSignature] of [
  ['wrong issuer', { iss: 'https://attacker.invalid' }],
  ['wrong audience', { aud: 'another-client' }],
  ['wrong nonce', { nonce: 'wrong' }],
  ['expired token', { exp: NOW / 1000 - 30 }],
  ['future issued-at', { iat: NOW / 1000 + 100 }],
  ['wrong azp', { azp: 'another-client' }],
  ['multiple audiences without azp', { aud: [CLIENT, 'another-client'] }],
  ['empty subject', { sub: '' }],
  ['missing expiry', {}, ['exp']],
  ['missing issued-at', {}, ['iat']],
  ['missing nonce', {}, ['nonce']],
  ['invalid signature', {}, [], true],
]) {
  test(`rejects ${name} before activation`, async () => {
    const f = await fixture({ claims, omitClaims, wrongSignature }); await f.callback();
    await rejectsCode(f.attempt.completion, 'invalid_identity'); assert.equal(f.activated.length, 0);
    assert.equal(f.pending.length, 1);
  });
}

test('identity-only grant never enables ChatGPT plan usage', async () => {
  const f = await fixture({ tokens: { scope: 'openid profile email', refresh_token: undefined } });
  await f.callback(); assert.equal((await f.attempt.completion).sharing, false);
});

test('direct-use scope without resource.invoke is not treated as plan permission', async () => {
  const f = await fixture({ tokens: { scope: 'openid chatgpt.tokens.use.direct' } });
  await f.callback(); assert.equal((await f.attempt.completion).sharing, false);
});

for (const [name, tokens] of [
  ['missing scope', { scope: undefined }], ['wrong token type', { token_type: 'MAC' }],
  ['missing access token', { access_token: undefined }], ['missing offline refresh token', { refresh_token: undefined }],
  ['negative expiry', { expires_in: -1 }], ['nonfinite expiry', { expires_in: 'Infinity' }],
  ['missing identity token', { id_token: undefined }], ['oversized token', { access_token: 'x'.repeat(17000) }],
  ['header-unsafe access token', { access_token: 'synthetic-token\r\nInjected: bad' }],
  ['control character in refresh token', { refresh_token: 'synthetic-token\u0000' }],
]) {
  test(`rejects token response with ${name}`, async () => {
    const f = await fixture({ tokens }); await f.callback();
    await rejectsCode(f.attempt.completion, 'invalid_token_response'); assert.equal(f.activated.length, 0);
  });
}

for (const [name, request] of [
  ['wrong Host', { host: 'localhost' }], ['wrong path', { path: '/callback' }], ['wrong method', { method: 'POST' }],
]) {
  test(`unrelated callback ${name} does not consume grant`, async () => {
    const f = await fixture(); assert.equal(await f.callback({}, request), 404);
    assert.equal(f.calls.length, 0); await f.callback(); await f.attempt.completion;
  });
}

test('wrong state and duplicate state do not consume pending authorization', async () => {
  const f = await fixture(); assert.equal(await f.callback({ state: 'wrong' }), 400);
  const state = new URL(f.attempt.authorizationUrl).searchParams.get('state');
  assert.equal(await f.callback({}, { query: `state=${state}&state=${state}&code=x&client_id=${CLIENT}` }), 400);
  assert.equal(f.calls.length, 0); await f.callback(); await f.attempt.completion;
});

test('matching callback with duplicate code is rejected before exchange', async () => {
  const f = await fixture(); const state = new URL(f.attempt.authorizationUrl).searchParams.get('state');
  await f.callback({}, { query: `state=${state}&code=x&code=y&client_id=${CLIENT}` });
  await rejectsCode(f.attempt.completion, 'invalid_callback'); assert.equal(f.calls.length, 0);
});

test('denied consent with matching state never exchanges a code', async () => {
  const f = await fixture(); const state = new URL(f.attempt.authorizationUrl).searchParams.get('state');
  await f.callback({}, { query: `state=${state}&error=access_denied&error_description=server-secret` });
  await rejectsCode(f.attempt.completion, 'access_denied'); assert.equal(f.pending.length, 0); assert.equal(f.calls.length, 0);
});

test('token rejection preserves pending issued registration and sanitized error', async () => {
  const f = await fixture({ fetchOverride: async () => Response.json({ error: 'invalid_grant', error_description: 'server-secret' }, { status: 400 }) });
  await f.callback(); await rejectsCode(f.attempt.completion, 'invalid_grant');
  assert.equal(f.pending[0].clientId, CLIENT); assert.equal(f.activated.length, 0);
});

test('pending storage failure prevents exchange and exposes no repository error', async () => {
  const f = await fixture({ repository: { async savePendingRegistration() { throw new Error('server-secret'); } } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'storage_unavailable'); assert.equal(f.calls.length, 0);
});

test('returning registration reuses client ID and validates original account identity', async () => {
  const saved = { profileId: 'saved-profile', clientId: CLIENT, hostId: HOST, issuer: ISSUER, subject: 'fixture-subject' };
  const f = await fixture({ saved });
  const a = new URL(f.attempt.authorizationUrl);
  assert.equal(a.searchParams.get('client_id'), CLIENT); assert.equal(a.searchParams.has('agent_name_hint'), false);
  const state = a.searchParams.get('state');
  await f.callback({}, { query: `state=${state}&code=synthetic-code` });
  assert.equal((await f.attempt.completion).profileId, 'saved-profile');
});

test('returning account mismatch never replaces active credentials', async () => {
  const f = await fixture({ saved: { profileId: 'saved-profile', clientId: CLIENT, hostId: HOST, issuer: ISSUER, subject: 'original-account' } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'account_mismatch'); assert.equal(f.activated.length, 0);
});

test('returning callback cannot replace its registered client ID', async () => {
  const f = await fixture({ saved: { profileId: 'saved-profile', clientId: CLIENT, hostId: HOST, issuer: ISSUER, subject: 'fixture-subject' } });
  await f.callback({ client_id: 'oaiapp_another' });
  await rejectsCode(f.attempt.completion, 'invalid_callback'); assert.equal(f.calls.length, 0);
});

for (const [name, fetchOverride, code] of [
  ['redirect response', async () => new Response('', { status: 302, headers: { location: 'https://attacker.invalid' } }), 'remote_rejected'],
  ['oversized response', async () => new Response('x'.repeat(70000)), 'response_too_large'],
  ['malformed response', async () => new Response('{'), 'invalid_remote_response'],
  ['stalled response', async () => new Promise(() => {}), 'request_timeout'],
]) {
  test(`bounded token transport rejects ${name}`, async () => {
    const f = await fixture({ fetchOverride, config: { requestTimeoutMs: 25 } }); await f.callback();
    await rejectsCode(f.attempt.completion, code); assert.equal(f.activated.length, 0);
  });
}

test('external JWKS URI in discovery cannot exfiltrate token or make outbound request', async () => {
  const f = await fixture({ useDiscovery: true, discovery: { jwks_uri: 'https://attacker.invalid/jwks' } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'invalid_discovery');
  assert.equal(f.calls.length, 2); assert.equal(f.activated.length, 0);
});

test('cancellation interrupts stalled exchange and prevents activation', async () => {
  let entered; const waiting = new Promise(resolve => { entered = resolve; });
  const f = await fixture({ fetchOverride: async () => { entered(); return new Promise(() => {}); } });
  await f.callback(); await waiting; f.attempt.cancel();
  await rejectsCode(f.attempt.completion, 'cancelled'); assert.equal(f.activated.length, 0);
});

test('grant timeout closes an abandoned callback listener', async () => {
  const f = await fixture({ config: { grantTimeoutMs: 30 } });
  await rejectsCode(f.attempt.completion, 'authorization_timeout'); assert.equal(f.calls.length, 0);
});

test('one grant component rejects simultaneous starts', async () => {
  const f = await fixture();
  await rejectsCode(f.grant.start(), 'authorization_busy'); f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled');
});

test('optional browser receives only authorization URL and failures are sanitized', async () => {
  let seen;
  const f = await fixture({ config: { openBrowser: url => { seen = url; } } });
  assert.equal(seen, f.attempt.authorizationUrl); f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled');
});

test('configuration rejects arbitrary host IDs and overlong timeouts', () => {
  const repository = { getRegistration() {}, savePendingRegistration() {}, activateVerified() {} };
  assert.throws(() => createSIWCGrant({ repository, hostId: 'https://attacker.invalid' }), { code: 'invalid_config' });
  assert.throws(() => createSIWCGrant({ repository, hostId: HOST, requestTimeoutMs: 1e9 }), { code: 'invalid_config' });
});

test('new attempt uses fresh secrets after previous cancellation', async () => {
  const f = await fixture(); const previous = new URL(f.attempt.authorizationUrl);
  f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled');
  const next = await f.grant.start();
  for (const field of ['state', 'nonce', 'code_challenge']) assert.notEqual(new URL(next.authorizationUrl).searchParams.get(field), previous.searchParams.get(field));
  next.cancel(); await rejectsCode(next.completion, 'cancelled');
});

test('pre-aborted caller starts no listener or remote request', async () => {
  const controller = new AbortController(); controller.abort();
  await rejectsCode(fixture({ start: { signal: controller.signal } }), 'cancelled');
});

test('browser failure closes pending attempt and never invokes token endpoint', async () => {
  const f = await fixture({ config: { openBrowser() { throw new Error('server-secret'); } } });
  await rejectsCode(f.attempt.completion, 'browser_unavailable');
  assert.equal(f.calls.length, 0);
});

test('absolute callback URLs and dot-normalized paths are not accepted', async () => {
  const f = await fixture();
  assert.equal(await f.callback({}, { path: `http://127.0.0.1:${new URL(f.attempt.redirectUri).port}/auth/callback` }), 404);
  assert.equal(await f.callback({}, { path: '/other/../auth/callback' }), 404);
  await f.callback(); await f.attempt.completion;
});

test('duplicate client ID parameters reject registration', async () => {
  const f = await fixture(); const state = new URL(f.attempt.authorizationUrl).searchParams.get('state');
  await f.callback({}, { query: `state=${state}&code=x&client_id=${CLIENT}&client_id=${CLIENT}` });
  await rejectsCode(f.attempt.completion, 'invalid_callback'); assert.equal(f.calls.length, 0);
});

test('dynamic registration identifier cannot become issued client identifier', async () => {
  const f = await fixture(); await f.callback({ client_id: 'dynamic_agent_client' });
  await rejectsCode(f.attempt.completion, 'invalid_callback'); assert.equal(f.pending.length, 0);
});

test('oversized declared content length is rejected before reading response body', async () => {
  let cancelled = false;
  const f = await fixture({ fetchOverride: async () => new Response(new ReadableStream({ cancel() { cancelled = true; } }), { headers: { 'content-length': '9999999' } }) });
  await f.callback(); await rejectsCode(f.attempt.completion, 'response_too_large');
  assert.equal(f.activated.length, 0);
  assert.equal(cancelled, true, 'rejected body must release its transport');
});

test('stalled response body respects request deadline', async () => {
  const f = await fixture({ fetchOverride: async () => new Response(new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('{')); } })), config: { requestTimeoutMs: 25 } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'request_timeout'); assert.equal(f.activated.length, 0);
});

test('JWKS count cap rejects excessive keys without identity activation', async () => {
  const f = await fixture({ useDiscovery: true, fetchOverride: async (url, _init, tokens) => {
    if (url.endsWith('/oauth/token')) return Response.json(await tokens());
    if (url.endsWith('/openid-configuration')) return Response.json({ issuer: ISSUER, jwks_uri: `${ISSUER}/.well-known/jwks.json` });
    if (url.endsWith('/jwks.json')) return Response.json({ keys: Array(33).fill(jwk) });
    throw new Error('UNMOCKED NETWORK');
  } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'invalid_discovery'); assert.equal(f.activated.length, 0);
});

test('JWKS byte cap rejects oversized keys before JOSE parsing', async () => {
  const f = await fixture({ useDiscovery: true, fetchOverride: async (url, _init, tokens) => {
    if (url.endsWith('/oauth/token')) return Response.json(await tokens());
    if (url.endsWith('/openid-configuration')) return Response.json({ issuer: ISSUER, jwks_uri: `${ISSUER}/.well-known/jwks.json` });
    if (url.endsWith('/jwks.json')) return Response.json({ keys: [{ ...jwk, n: 'x'.repeat(140000) }] });
    throw new Error('UNMOCKED NETWORK');
  } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'response_too_large'); assert.equal(f.activated.length, 0);
});

test('invalid discovery issuer is rejected', async () => {
  const f = await fixture({ useDiscovery: true, discovery: { issuer: 'https://attacker.invalid' } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'invalid_discovery'); assert.equal(f.calls.length, 2);
});

test('registration storage error does not expose repository exception', async () => {
  await rejectsCode(fixture({ saved: { profileId: 'fixture-profile' }, repository: { getRegistration() { throw new Error('server-secret'); } } }), 'storage_unavailable');
});

test('activation failure exposes no credential record or raw storage exception', async () => {
  const f = await fixture({ repository: { activateVerified() { throw new Error('synthetic-access-never-real server-secret'); } } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'storage_unavailable'); assert.equal(f.pending.length, 1);
});

test('cancellation signal reaches repository atomic activation boundary', async () => {
  let reached; const ready = new Promise(resolve => { reached = resolve; });
  let release; const hold = new Promise(resolve => { release = resolve; });
  let writes = 0;
  const f = await fixture({ repository: { async activateVerified(_record, { signal }) {
    reached(); await hold; signal.throwIfAborted(); writes += 1;
  } } });
  await f.callback(); await ready; f.attempt.cancel(); release();
  await rejectsCode(f.attempt.completion, 'cancelled'); assert.equal(writes, 0);
});

test('resolved signing key still requires supported signature algorithm', async () => {
  const f = await fixture({ tokens: { id_token: `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from('{}').toString('base64url')}.` } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'invalid_identity'); assert.equal(f.activated.length, 0);
});

test('callback replay while exchange is pending cannot start another exchange', async () => {
  let entered; const ready = new Promise(resolve => { entered = resolve; });
  const f = await fixture({ fetchOverride: async () => { entered(); return new Promise(() => {}); } });
  await f.callback(); await ready; assert.equal(await f.callback(), 404);
  assert.equal(f.calls.length, 1); f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled');
});

test('network signing-key failure cannot activate received credentials', async () => {
  const f = await fixture({ useDiscovery: true, fetchOverride: async (url, _init, tokens) => {
    if (url.endsWith('/oauth/token')) return Response.json(await tokens());
    throw new Error('server-secret');
  } });
  await f.callback(); await rejectsCode(f.attempt.completion, 'remote_unavailable');
  assert.equal(f.pending.length, 1); assert.equal(f.activated.length, 0);
});

test('multiple audiences with correct azp are accepted', async () => {
  const f = await fixture({ claims: { aud: [CLIENT, 'additional-audience'], azp: CLIENT } });
  await f.callback(); assert.equal((await f.attempt.completion).sharing, true);
});


async function withDeadline(promise, milliseconds = 200) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Operation remained pending beyond test deadline')), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

function callbackFromAuthorization(authorizationUrl) {
  const authorization = new URL(authorizationUrl);
  const callback = new URL(authorization.searchParams.get('redirect_uri'));
  callback.search = new URLSearchParams({ state: authorization.searchParams.get('state'), code: 'synthetic-code', client_id: CLIENT }).toString();
  return sendCallback(callback);
}

test('successful callback completes even when browser launcher promise never settles', async () => {
  let release;
  const launcher = new Promise(resolve => { release = resolve; });
  try {
    const f = await withDeadline(fixture({ config: { grantTimeoutMs: 40,
      openBrowser: async url => { await callbackFromAuthorization(url); await launcher; },
    } }));
    assert.equal((await withDeadline(f.attempt.completion)).sharing, true);
    assert.equal(f.activated.length, 1);
  } finally { release(); }
});


test('pending browser launcher does not prevent cancellation', async () => {
  let rejectLaunch;
  const launcher = new Promise((_, reject) => { rejectLaunch = reject; });
  const f = await withDeadline(fixture({ config: { openBrowser: () => launcher } }));
  f.attempt.cancel(); await rejectsCode(f.attempt.completion, 'cancelled');
  rejectLaunch(new Error('server-secret'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.calls.length, 0); assert.equal(f.activated.length, 0);
});

test('pending browser launcher remains subject to grant timeout before callback', async () => {
  const f = await withDeadline(fixture({ config: { grantTimeoutMs: 30, openBrowser: () => new Promise(() => {}) } }));
  await rejectsCode(f.attempt.completion, 'authorization_timeout');
  assert.equal(f.calls.length, 0); assert.equal(f.activated.length, 0);
});

test('late browser rejection cannot override success or abort a subsequent grant', async () => {
  let rejectLaunch;
  const launcher = new Promise((_, reject) => { rejectLaunch = reject; });
  let launches = 0;
  const f = await withDeadline(fixture({ config: { openBrowser: async url => {
    launches += 1;
    if (launches === 1) { await callbackFromAuthorization(url); await launcher; }
    else { await new Promise(() => {}); }
  } } }));
  const result = await withDeadline(f.attempt.completion);
  assert.equal(result.sharing, true); assert.equal(f.activated.length, 1);
  const second = await withDeadline(f.grant.start());
  let secondSettled = false;
  void second.completion.then(() => { secondSettled = true; }, () => { secondSettled = true; });
  rejectLaunch(new Error('server-secret'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(secondSettled, false);
  await rejectsCode(f.grant.start(), 'authorization_busy');
  assert.equal(await f.attempt.completion, result);
  assert.equal(f.activated.length, 1);
  second.cancel(); await rejectsCode(second.completion, 'cancelled');
});
