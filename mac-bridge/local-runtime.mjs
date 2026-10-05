import {constants} from 'node:fs';
import {mkdir, open, lstat, realpath, unlink, rmdir} from 'node:fs/promises';
import {resolve, dirname, join, isAbsolute} from 'node:path';
import {homedir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';

const messages = {
  invalid_configuration: 'The local assistant is not configured.',
  busy: 'Another local assistant owns this Mac connection.',
  storage_unavailable: 'The private local assistant files are unavailable.',
  connection_failed: 'ChatGPT could not connect. Your music is unchanged.',
  connection_changed: 'The ChatGPT connection changed. Request a new change.',
  stopped: 'The local assistant has stopped.',
  cleanup_required: 'The local assistant stopped accepting work. Its process must be checked before restarting.',
};
export class LocalRuntimeError extends Error {
  constructor(code) { super(messages[code] ?? messages.storage_unavailable); this.name = 'LocalRuntimeError'; this.code = Object.hasOwn(messages, code) ? code : 'storage_unavailable'; }
}
const fail = code => new LocalRuntimeError(code);
const owned = info => info.uid === process.getuid();
const sameFile = (a,b) => a.dev === b.dev && a.ino === b.ino;

async function privateDirectory(path, create = false) {
  if (!isAbsolute(path) || resolve(path) !== path) throw fail('invalid_configuration');
  if (create) await mkdir(path, {recursive: true, mode: 0o700});
  const info = await lstat(path);
  if (!info.isDirectory() || !owned(info) || (info.mode & 0o022) || await realpath(path) !== path) throw fail('storage_unavailable');
  return info;
}
async function exclusiveFile(path, value) {
  await privateDirectory(dirname(path));
  const file = await open(path, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600);
  try { await file.writeFile(value); await file.sync(); return await file.stat(); }
  finally { await file.close(); }
}
async function removeOwnedFile(path, identity) {
  let info;
  try { info = await lstat(path); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
  if (!info.isFile() || !owned(info) || !sameFile(info, identity)) throw fail('cleanup_required');
  await unlink(path);
}
function bounded(promise, ms) {
  const supplied = Promise.resolve(promise);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(fail('cleanup_required')), ms);
    supplied.then(resolve, reject).finally(() => clearTimeout(timer));
  });
}
async function productionFactories() {
  const [repo, grant, provider, parser, server] = await Promise.all([
    import('./credential-repository.mjs'), import('./siwc-auth.mjs'), import('./music-provider.mjs'),
    import('./proposal-stream.mjs'), import('./local-server.mjs'),
  ]);
  return {repository: repo.createCredentialRepository, grant: grant.createSIWCGrant,
    provider: provider.createMusicProvider, readProposal: parser.readMusicProposal, server: server.startLocalMusicServer};
}
function openOnMac(url) {
  // The reviewed grant constructs this URL; no user-supplied command or credential argument.
  const parsed = new URL(url);
  if (parsed.origin !== 'https://auth.openai.com' || parsed.pathname !== '/api/accounts/authorize') throw fail('connection_failed');
  return new Promise((resolve, reject) => {
    const child = spawn('/usr/bin/open', [url], {stdio: 'ignore', shell: false});
    const timer = setTimeout(() => { child.kill(); reject(fail('connection_failed')); }, 5000);
    child.once('error', () => { clearTimeout(timer); reject(fail('connection_failed')); });
    child.once('close', code => { clearTimeout(timer); code === 0 ? resolve() : reject(fail('connection_failed')); });
  });
}

/**
 * Trusted Mac launcher only. The UI cannot configure helpers, directories or factories.
 * No OAuth credential is returned or written to the simulator. Persisted sessions are
 * inactive after restart; connecting requires the reviewed fresh OAuth grant.
 * An uncertain credential operation retains the process lock for explicit inspection.
 * factories/stateDirectory are seams for isolated offline tests, never HTTP inputs.
 */
export async function startLocalAssistant({helperPath, pairingFile,
  stateDirectory = join(homedir(), 'Library', 'Application Support', 'Loopa Local Assistant'),
  openBrowser = openOnMac, factories, now = Date.now} = {}) {
  if (process.platform !== 'darwin' || typeof process.getuid !== 'function' ||
      !isAbsolute(helperPath ?? '') || !isAbsolute(pairingFile ?? '') ||
      resolve(pairingFile) !== pairingFile || typeof openBrowser !== 'function' || typeof now !== 'function') throw fail('invalid_configuration');
  let helperInfo;
  try {
    helperInfo = await lstat(helperPath);
    if (!helperInfo.isFile() || !owned(helperInfo) || (helperInfo.mode & 0o022) || !(helperInfo.mode & 0o100) ||
        await realpath(helperPath) !== helperPath) throw fail('invalid_configuration');
    await privateDirectory(dirname(pairingFile));
    await privateDirectory(stateDirectory, true);
    if ((await lstat(stateDirectory)).mode & 0o077) throw fail('storage_unavailable');
  } catch (error) { throw error instanceof LocalRuntimeError ? error : fail('storage_unavailable'); }
  const lockPath = join(stateDirectory, 'bridge.lock');
  try { await mkdir(lockPath, {mode: 0o700}); }
  catch (error) { throw fail(error.code === 'EEXIST' ? 'busy' : 'storage_unavailable'); }
  const lockIdentity = await lstat(lockPath);
  const ownerPath = join(lockPath, 'owner.json');
  const ownerIdentity = await exclusiveFile(ownerPath, JSON.stringify({version: 1, pid: process.pid, id: randomUUID()}) + '\n');
  let active = true, repositoryStarted = false, uncertain = false, server, provider, repository, grant;
  let pairIdentity, grantHandle, connecting = false, usageUnavailable = false, stopPromise;
  let connectionEpoch = randomUUID();
  const lifetime = new AbortController();
  const pending = new Set();
  const check = () => { if (!active) throw fail('stopped'); };
  async function releaseLock() {
    const current = await lstat(lockPath);
    if (!sameFile(current, lockIdentity) || !current.isDirectory()) throw fail('cleanup_required');
    await removeOwnedFile(ownerPath, ownerIdentity);
    await rmdir(lockPath); // Never recursively remove unexpected contents.
  }
  function repositoryCall(method, ...args) {
    check();
    let operation;
    try { operation = Promise.resolve(repository[method](...args)); }
    catch (error) { operation = Promise.reject(error); }
    pending.add(operation);
    // Observe every underlying operation even if its OAuth caller is cancelled first.
    void operation.then(() => pending.delete(operation), error => {
      pending.delete(operation);
      if (!['busy', 'cancelled', 'invalid_record'].includes(error?.code)) uncertain = true;
    });
    return operation;
  }
  function status() {
    if (!active) return {status: 'disconnected', sharing: false};
    if (connecting) return {status: 'connecting', sharing: false};
    const session = repository?.getActiveSession();
    if (!session) return {status: 'disconnected', sharing: false};
    const sharing = ['resource.invoke','chatgpt.tokens.use.direct'].every(s => session.scopes?.includes(s));
    if (!Number.isSafeInteger(session.credentials?.expiresAt) || session.credentials.expiresAt <= now() + 45_000)
      return {status: 'reconnect_required', sharing: false};
    return {status: usageUnavailable ? 'usage_unavailable' : 'connected', sharing};
  }
  function stop() {
    if (stopPromise) return stopPromise;
    active = false;
    connectionEpoch = randomUUID();
    // Publish the terminal promise before cancellation can reenter through dependencies.
    stopPromise = Promise.resolve().then(async () => {
      try {
        lifetime.abort(); grantHandle?.cancel(); provider?.cancel();
        if (server) await bounded(server.stop(), 6000);
        if (pairIdentity) await removeOwnedFile(pairingFile, pairIdentity);
        await bounded(Promise.allSettled([...pending]), 6000);
        if (uncertain) throw fail('cleanup_required');
        await releaseLock();
      } catch { throw fail('cleanup_required'); }
    });
    void stopPromise.catch(() => {});
    return stopPromise;
  }
  try {
    const f = factories ?? await productionFactories();
    for (const name of ['repository','grant','provider','readProposal','server']) if (typeof f[name] !== 'function') throw fail('invalid_configuration');
    // Recheck the trusted executable identity immediately before repository construction.
    if (!sameFile(helperInfo, await lstat(helperPath))) throw fail('invalid_configuration');
    repository = f.repository({helperPath}); repositoryStarted = true;
    const {hostId} = await bounded(repositoryCall('initialize'), 6000); check();
    const protectedRepository = Object.fromEntries(['getRegistration','savePendingRegistration','activateVerified']
      .map(method => [method, (...args) => repositoryCall(method, ...args)]));
    grant = f.grant({repository: protectedRepository, hostId, appName: 'Loopa', openBrowser, now});
    provider = f.provider({getActiveSession: () => active ? repository.getActiveSession() : undefined,
      reserveRequest: value => repositoryCall('reserveRequest', value), readProposal: f.readProposal, now});
    const exposedProvider = {cancel: () => provider.cancel()};
    for (const method of ['listModels','proposeGain']) exposedProvider[method] = async (...args) => {
      check(); if (connecting) throw fail('connection_changed');
      const capturedEpoch = connectionEpoch;
      const current = () => { check(); if (capturedEpoch !== connectionEpoch || connecting) throw fail('connection_changed'); };
      try { const value = await provider[method](...args); current(); return value; }
      catch (error) {
        current();
        if (error?.code === 'usage_unavailable' || error?.code === 'request_not_reserved') usageUnavailable = true;
        throw error;
      }
    };
    const pendingServer = Promise.resolve(f.server({provider: exposedProvider, status, now})).then(value => {
      server = value;
      if (!active) { void Promise.resolve().then(() => value.stop()).catch(() => {}); throw fail('stopped'); }
      return value;
    });
    server = await bounded(pendingServer, 6000); check();
    const pair = server.pairing;
    const port = new URL(pair?.endpoint ?? '').port;
    if (!port || Number(port) < 1024 || pair.endpoint !== `http://127.0.0.1:${port}/` ||
        typeof pair.capability !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(pair.capability) ||
        Buffer.from(pair.capability,'base64url').length !== 32 || Buffer.from(pair.capability,'base64url').toString('base64url') !== pair.capability ||
        !Number.isSafeInteger(pair.expiresAt) || pair.expiresAt <= now() || pair.expiresAt > now() + 900_000) throw fail('invalid_configuration');
    pairIdentity = await exclusiveFile(pairingFile, JSON.stringify({version: 1, endpoint: pair.endpoint,
      capability: pair.capability, expires_at: pair.expiresAt}) + '\n');
    return Object.freeze({
      status, stop, pairingExpiresAt: pair.expiresAt,
      async connect({profileId} = {}) {
        check(); if (connecting) throw fail('busy');
        connecting = true; connectionEpoch = randomUUID(); usageUnavailable = false;
        provider.cancel(); // Stop old-account network work before starting another grant.
        // Cancellation of a completed older grant invalidates only its own activation.
        grantHandle?.cancel();
        try {
          check();
          const handle = await grant.start({profileId, signal: lifetime.signal, port: 0});
          grantHandle = handle;
          if (!active) { handle.cancel(); throw fail('stopped'); }
          await handle.completion; check();
          connecting = false;
          return status(); // No identity or credential object leaves this boundary.
        } catch { throw fail(active ? 'connection_failed' : 'stopped'); }
        finally { connecting = false; }
      },
    });
  } catch (error) {
    if (error?.code === 'cleanup_required') uncertain = true;
    active = false; lifetime.abort(); grantHandle?.cancel(); provider?.cancel();
    if (server) { try { await bounded(server.stop(),6000); } catch { uncertain = true; } }
    if (pairIdentity) { try { await removeOwnedFile(pairingFile,pairIdentity); } catch { uncertain = true; } }
    // Startup failures after a credential operation retain the lock when unsettled or uncertain.
    if (pending.size || uncertain) throw fail('cleanup_required');
    try { await releaseLock(); } catch { throw fail('cleanup_required'); }
    throw error instanceof LocalRuntimeError ? error : fail(repositoryStarted ? 'connection_failed' : 'storage_unavailable');
  }
}
