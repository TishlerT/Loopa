import {isAbsolute, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {startLocalAssistant} from './local-runtime.mjs';

const EXIT = Object.freeze({expired:0, invalid:2, failed:3, timeout:4, cleanup:5, interrupt:130, terminate:143});
const STATUS = Object.freeze({
  invalid:'LOOPA_PILOT_INVALID_ARGUMENTS', starting:'LOOPA_PILOT_STARTING', connecting:'LOOPA_PILOT_CONNECTING',
  connected:'LOOPA_PILOT_CONNECTED', sharing:'LOOPA_PILOT_SHARING_REQUIRED', startFailed:'LOOPA_PILOT_START_FAILED',
  connectFailed:'LOOPA_PILOT_CONNECTION_FAILED', timeout:'LOOPA_PILOT_TIMEOUT', expired:'LOOPA_PILOT_EXPIRED',
  interrupt:'LOOPA_PILOT_INTERRUPTED', terminate:'LOOPA_PILOT_TERMINATED', cleanup:'LOOPA_PILOT_CLEANUP_REQUIRED',
});

function argumentsForRuntime(argv) {
  if (!Array.isArray(argv) || argv.length !== 4 || argv.some(value => typeof value !== 'string')) throw new Error();
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = {'--helper':'helperPath','--pairing-file':'pairingFile'}[argv[index]];
    const value = argv[index + 1];
    if (!key || Object.hasOwn(options,key) || !isAbsolute(value) || resolve(value) !== value || /[\u0000-\u001f\u007f]/.test(value)) throw new Error();
    options[key] = value;
  }
  if (!options.helperPath || !options.pairingFile || options.helperPath === options.pairingFile) throw new Error();
  return options;
}
const duration = (value, maximum) => Number.isInteger(value) && value > 0 && value <= maximum;

/**
 * Personal Mac pilot only: node local-pilot.mjs --helper ABS --pairing-file ABS.
 * Only those two paths reach the production runtime. Its private state-directory,
 * protected repository, browser and provider defaults are not CLI configurable.
 * Importing this module does nothing. The dependency arguments below are offline
 * test seams, never flags or environment settings.
 *
 * Exit: 0 lifetime ended, 2 invalid arguments, 3 start/connect/sharing failure,
 * 4 deadline, 5 uncertain cleanup, 130 SIGINT, 143 SIGTERM. Cleanup uncertainty
 * overrides any earlier outcome. Nothing removes/replaces a retained runtime lock.
 */
export async function runLocalPilot(argv, {
  start = startLocalAssistant, signals = process, write = value => process.stdout.write(value + '\n'), now = Date.now,
  startupTimeoutMs = 15_000, connectTimeoutMs = 180_000, cleanupTimeoutMs = 15_000, lifetimeMs = 900_000,
} = {}) {
  const emit = code => { try { write(code); } catch { /* Never let diagnostics bypass cleanup. */ } };
  let options;
  try {
    options = argumentsForRuntime(argv);
    if (typeof start !== 'function' || typeof write !== 'function' || typeof now !== 'function' ||
        typeof signals?.on !== 'function' || typeof signals?.removeListener !== 'function' ||
        !duration(startupTimeoutMs,15_000) || !duration(connectTimeoutMs,180_000) ||
        !duration(cleanupTimeoutMs,15_000) || !duration(lifetimeMs,900_000)) throw new Error();
  } catch { emit(STATUS.invalid); return EXIT.invalid; }

  let terminal, finish, runtime, starting, startupError, shutdown = false, stopping;
  let lifetimeTimer, pairingTimer;
  const ended = new Promise(resolve => { finish = resolve; });
  const end = (code, status) => {
    if (terminal) return;
    terminal = {kind:'terminal',code,status}; finish(terminal);
  };
  const interrupt = () => end(EXIT.interrupt,STATUS.interrupt);
  const terminate = () => end(EXIT.terminate,STATUS.terminate);
  const stopOnce = () => {
    if (!stopping && runtime) {
      // Publish a promise before calling a reentrant runtime.stop implementation.
      stopping = Promise.resolve().then(() => {
        if (typeof runtime.stop !== 'function') throw new Error();
        return runtime.stop();
      });
      void stopping.catch(() => {});
    }
    return stopping;
  };
  const stage = async (promise, milliseconds) => {
    const observed = Promise.resolve(promise).then(value => ({kind:'value',value}), () => ({kind:'failure'}));
    const timer = setTimeout(() => end(EXIT.timeout,STATUS.timeout),milliseconds);
    try { return await Promise.race([observed,ended]); }
    finally { clearTimeout(timer); }
  };

  signals.on('SIGINT',interrupt); signals.on('SIGTERM',terminate);
  lifetimeTimer = setTimeout(() => end(EXIT.expired,STATUS.expired),lifetimeMs);
  try {
    emit(STATUS.starting);
    // The thunk prevents starting after a synchronous signal during admission.
    starting = Promise.resolve().then(() => terminal ? undefined : start(options)).then(value => {
      runtime = value;
      if (shutdown && runtime) stopOnce();
      return value;
    }, error => { startupError = error?.code; throw error; });
    // Observe immediately, even if a dependency synchronously signals and rejects.
    void starting.catch(() => {});
    const started = await stage(starting,startupTimeoutMs);
    if (!terminal) {
      if (started.kind !== 'value' || !runtime || typeof runtime.connect !== 'function' || typeof runtime.stop !== 'function') {
        end(startupError === 'cleanup_required' ? EXIT.cleanup : EXIT.failed,
            startupError === 'cleanup_required' ? STATUS.cleanup : STATUS.startFailed);
      } else {
        const timestamp = now();
        if (!Number.isSafeInteger(timestamp) || timestamp < 0 || !Number.isSafeInteger(runtime.pairingExpiresAt) ||
            runtime.pairingExpiresAt <= timestamp || runtime.pairingExpiresAt > timestamp + 900_000) {
          end(EXIT.failed,STATUS.startFailed);
        } else {
          pairingTimer = setTimeout(() => end(EXIT.expired,STATUS.expired),runtime.pairingExpiresAt - timestamp);
          emit(STATUS.connecting);
          const connecting = Promise.resolve().then(() => terminal ? undefined : runtime.connect());
          const connected = await stage(connecting,connectTimeoutMs);
          if (!terminal) {
            if (connected.kind !== 'value' || connected.value?.status !== 'connected') end(EXIT.failed,STATUS.connectFailed);
            else if (connected.value.sharing !== true) end(EXIT.failed,STATUS.sharing);
            else emit(STATUS.connected);
          }
        }
      }
    }
    if (!terminal) await ended;
  } catch { end(EXIT.failed,STATUS.startFailed); }
  finally {
    shutdown = true;
    clearTimeout(lifetimeTimer); clearTimeout(pairingTimer);
    // Stop after a late startup handle too. If it never arrives, startup may have
    // left owned state behind: report uncertainty and let the CLI boundary exit.
    const cleanup = Promise.resolve().then(async () => {
      try { await starting; } catch {
        if (startupError === 'cleanup_required') throw new Error();
      }
      if (runtime) await stopOnce();
    });
    const observed = cleanup.then(() => true, () => false);
    let cleanupTimer;
    const deadline = new Promise(resolve => { cleanupTimer = setTimeout(() => resolve(false),cleanupTimeoutMs); });
    const clean = await Promise.race([observed,deadline]);
    clearTimeout(cleanupTimer);
    signals.removeListener('SIGINT',interrupt); signals.removeListener('SIGTERM',terminate);
    if (!clean) terminal = {code:EXIT.cleanup,status:STATUS.cleanup};
  }
  emit(terminal.status);
  return terminal.code;
}

/** Executable boundary: even a broken dependency with live handles cannot linger. */
export async function main(argv = process.argv.slice(2), dependencies) {
  process.stdout.on('error',() => {}); // A closed diagnostic pipe must not skip shutdown.
  let code;
  try { code = await runLocalPilot(argv,dependencies); }
  catch { process.stdout.write(STATUS.cleanup + '\n'); code = EXIT.cleanup; }
  process.exit(code);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await main();
}
