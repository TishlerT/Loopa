/** Pure, independently authored Responses SSE decoder. It never executes tools. */
export const MUSIC_PROPOSAL_LIMITS = Object.freeze({
  wireBytes: 262_144, eventBytes: 32_768, argumentBytes: 4096,
  eventCount: 256, calls: 1, idleTimeoutMs: 15_000, totalTimeoutMs: 45_000,
});
const MESSAGES = Object.freeze({
  invalid_config: 'The proposal stream configuration is invalid.',
  invalid_stream: 'The proposal stream could not be verified.',
  invalid_utf8: 'The proposal stream contained invalid text encoding.',
  wire_limit: 'The proposal response exceeded its size limit.',
  event_limit: 'A proposal event exceeded its size limit.',
  event_count_limit: 'The proposal response contained too many events.',
  arguments_limit: 'The proposed edit exceeded its size limit.',
  tool_limit: 'Only one proposed edit is allowed.',
  unsupported_tool: 'The response requested an unsupported operation.',
  invalid_arguments: 'The proposed edit did not match the allowed format.',
  identity_conflict: 'The proposal stream contained conflicting identifiers.',
  conflicting_output: 'The proposal stream contained conflicting output.',
  missing_proposal: 'The completed response did not contain a proposed edit.',
  incomplete_stream: 'The proposal response ended before verified completion.',
  failed: 'The model could not complete this proposal.',
  refused: 'The model declined to provide this proposal.',
  cancelled: 'The proposal request was cancelled.',
  idle_timeout: 'The proposal stream stopped responding.',
  total_timeout: 'The proposal request exceeded its time limit.',
  after_terminal: 'The response contained unexpected data after completion.',
});
export class MusicProposalStreamError extends Error {
  constructor(code) {
    super(MESSAGES[code] ?? MESSAGES.invalid_stream);
    this.name = 'MusicProposalStreamError';
    this.code = Object.hasOwn(MESSAGES, code) ? code : 'invalid_stream';
  }
}
const fail = code => new MusicProposalStreamError(code);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const identifier = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
const forbiddenKeys = new Set(['__proto__', 'prototype', 'constructor']);

// JSON.parse alone silently accepts duplicate keys. This bounded lexical pass
// rejects ambiguity before parsing, including escaped spellings of object keys.
function strictJSON(text) {
  const stack = [];
  try {
    for (let i = 0; i < text.length; i += 1) {
      const c = text[i];
      if (c === '"') {
        const begin = i;
        for (i += 1; i < text.length && text[i] !== '"'; i += 1) if (text[i] === '\\') i += 1;
        if (i >= text.length) throw new Error();
        let next = i + 1;
        while (next < text.length && /\s/.test(text[next])) next += 1;
        if (text[next] === ':') {
          const key = JSON.parse(text.slice(begin, i + 1));
          const keys = stack.at(-1);
          if (!(keys instanceof Set) || forbiddenKeys.has(key) || keys.has(key)) throw new Error();
          keys.add(key);
        }
      } else if (c === '{' || c === '[') {
        stack.push(c === '{' ? new Set() : null);
        if (stack.length > 32) throw new Error();
      } else if (c === '}' || c === ']') stack.pop();
    }
    return JSON.parse(text);
  } catch { throw fail('invalid_stream'); }
}

function gainArguments(text, expectedTrackId) {
  if (typeof text !== 'string') throw fail('invalid_arguments');
  if (Buffer.byteLength(text) > MUSIC_PROPOSAL_LIMITS.argumentBytes) throw fail('arguments_limit');
  let args;
  try { args = strictJSON(text); } catch { throw fail('invalid_arguments'); }
  if (!object(args) || Object.keys(args).length !== 2 || !Object.hasOwn(args, 'track_id') || !Object.hasOwn(args, 'gain') ||
      !uuid(args.track_id) || args.track_id.toLowerCase() !== expectedTrackId.toLowerCase() ||
      typeof args.gain !== 'number' || !Number.isFinite(args.gain) || args.gain < 0 || args.gain > 1) throw fail('invalid_arguments');
  return args.gain;
}

const ignoredTypes = new Set([
  'response.output_text.delta', 'response.output_text.done',
  'response.output_text.annotation.added',
  'response.content_part.added', 'response.content_part.done',
  'response.reasoning_summary_part.added', 'response.reasoning_summary_part.done',
  'response.reasoning_summary_text.delta', 'response.reasoning_summary_text.done',
  'response.reasoning_text.delta', 'response.reasoning_text.done',
]);

/**
 * Read fetch's WHATWG response.body and return only a validated Swift wire command.
 * Calls are proposals, not executable tools. No output is returned before terminal
 * success AND EOF; callers must still recheck their captured session/revision.
 * Timeout overrides can only tighten the fixed production caps for offline tests.
 */
export async function readMusicProposal(body, {
  expectedTrackId, signal, idleTimeoutMs = MUSIC_PROPOSAL_LIMITS.idleTimeoutMs,
  totalTimeoutMs = MUSIC_PROPOSAL_LIMITS.totalTimeoutMs,
} = {}) {
  if (!body || typeof body.getReader !== 'function' || !uuid(expectedTrackId) ||
      (signal !== undefined && !(signal instanceof AbortSignal)) ||
      !Number.isInteger(idleTimeoutMs) || idleTimeoutMs < 1 || idleTimeoutMs > MUSIC_PROPOSAL_LIMITS.idleTimeoutMs ||
      !Number.isInteger(totalTimeoutMs) || totalTimeoutMs < 1 || totalTimeoutMs > MUSIC_PROPOSAL_LIMITS.totalTimeoutMs) throw fail('invalid_config');
  if (signal?.aborted) throw fail('cancelled');
  const controller = new AbortController();
  const stop = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;
  const timeout = setTimeout(() => controller.abort(), totalTimeoutMs);
  const startedAt = performance.now();
  const stopped = () => {
    if (signal?.aborted) throw fail('cancelled');
    if (controller.signal.aborted || performance.now() - startedAt >= totalTimeoutMs) throw fail('total_timeout');
  };
  let reader;
  const records = new Map(); const itemIndexes = new Map(); const callIds = new Set();
  let responseId; let terminal = false; let sentinel = false; let calls = 0;
  let wireBytes = 0; let eventCount = 0; let eventBytes = 0;
  let line = ''; let lineBytes = 0; let pendingCR = false; let emptyChunks = 0;
  let dataLines = []; let eventName; let hasRecord = false;
  const decoder = new TextDecoder('utf-8', { fatal: true });

  function responseIdentity(id) {
    if (id === undefined) return;
    if (!identifier(id)) throw fail('identity_conflict');
    if (responseId !== undefined && responseId !== id) throw fail('identity_conflict');
    responseId = id;
  }
  function indexValue(index) {
    if (!Number.isInteger(index) || index < 0 || index >= 256) throw fail('identity_conflict');
    return index;
  }
  function inspectItem(item) {
    if (!object(item) || !identifier(item.id)) throw fail('invalid_stream');
    if (!['function_call', 'message', 'reasoning'].includes(item.type)) throw fail('unsupported_tool');
    if (item.error != null || item.incomplete_details != null ||
        (item.status !== undefined && !['in_progress', 'completed'].includes(item.status))) throw fail('failed');
    if (item.type === 'function_call') {
      if (item.name !== 'propose_gain' || item.namespace !== 'loopa_music') throw fail('unsupported_tool');
      if (!identifier(item.call_id)) throw fail('identity_conflict');
      if (typeof item.arguments !== 'string') throw fail('invalid_arguments');
      if (Buffer.byteLength(item.arguments) > MUSIC_PROPOSAL_LIMITS.argumentBytes) throw fail('arguments_limit');
    } else if (item.type === 'message') {
      if (!Array.isArray(item.content)) throw fail('invalid_stream');
      for (const part of item.content) {
        if (part?.type === 'refusal') throw fail('refused');
        if (!object(part) || part.type !== 'output_text' || typeof part.text !== 'string') throw fail('invalid_stream');
      }
    }
  }
  function finalizeArguments(record, text) {
    const gain = gainArguments(text, expectedTrackId);
    if (record.hasDelta && record.delta !== text) throw fail('conflicting_output');
    if (record.finalText !== undefined && record.finalText !== text) throw fail('conflicting_output');
    record.finalText = text; record.gain = gain;
  }
  function acceptItem(item, index, phase) {
    indexValue(index); inspectItem(item);
    const priorIndex = itemIndexes.get(item.id);
    if (priorIndex !== undefined && priorIndex !== index) throw fail('identity_conflict');
    let record = records.get(index);
    if (record && (record.id !== item.id || record.type !== item.type)) throw fail('identity_conflict');
    if (!record) {
      record = { id: item.id, type: item.type, added: false, done: false, itemDone: false, delta: '', hasDelta: false, argumentsDone: false };
      if (item.type === 'function_call') {
        if (callIds.has(item.call_id)) throw fail('identity_conflict');
        callIds.add(item.call_id); calls += 1;
        if (calls > MUSIC_PROPOSAL_LIMITS.calls) throw fail('tool_limit');
        record.callId = item.call_id;
      }
      records.set(index, record); itemIndexes.set(item.id, index);
    }
    if (item.type === 'function_call' && record.callId !== item.call_id) throw fail('identity_conflict');
    if (phase === 'snapshot') {
      // Partial snapshots bind identity only. Explicitly completed snapshots are
      // final representations, so reconcile them just like item-done/terminal.
      // Once finalized, even a later partial snapshot cannot contradict the call.
      if (item.type === 'function_call' && (item.status === 'completed' || record.done)) {
        finalizeArguments(record, item.arguments);
      }
      if (item.status === 'completed') record.done = true;
      return record;
    }
    if (phase === 'added') {
      if (record.added || record.done) throw fail('conflicting_output');
      record.added = true;
      if (item.type === 'function_call' && item.arguments) { record.delta = item.arguments; record.hasDelta = true; }
    } else {
      if (phase === 'done' && record.itemDone) throw fail('conflicting_output');
      if (item.status !== undefined && item.status !== 'completed') throw fail('conflicting_output');
      if (item.type === 'function_call') finalizeArguments(record, item.arguments);
      if (phase === 'done') record.itemDone = true;
      record.done = true;
    }
    return record;
  }
  function eventRecord(event, requiredType) {
    const record = records.get(indexValue(event.output_index));
    if (!record || event.item_id !== record.id || (requiredType && record.type !== requiredType) ||
        (event.call_id !== undefined && event.call_id !== record.callId)) throw fail('identity_conflict');
    return record;
  }
  function ignoreContent(event) {
    if (event.part?.type === 'refusal') throw fail('refused');
    if (event.error != null || event.status === 'incomplete') throw fail('failed');
    let expectedType = event.type.startsWith('response.reasoning') ? 'reasoning' : 'message';
    if (event.type.startsWith('response.content_part.')) {
      if (!object(event.part) || !['output_text', 'reasoning_text'].includes(event.part.type) ||
          typeof event.part.text !== 'string') throw fail('invalid_stream');
      expectedType = event.part.type === 'reasoning_text' ? 'reasoning' : 'message';
    }
    eventRecord(event, expectedType);
    // Content is never exposed or executed. Validate its documented routing
    // fields without storing text, annotations, URLs, or raw reasoning.
    const partIndex = event.type.startsWith('response.reasoning_summary') ? event.summary_index : event.content_index;
    if (!Number.isSafeInteger(partIndex) || partIndex < 0) throw fail('identity_conflict');
    if (event.type === 'response.output_text.annotation.added') {
      if (!Number.isSafeInteger(event.annotation_index) || event.annotation_index < 0 ||
          !(event.annotation === null || object(event.annotation))) throw fail('invalid_stream');
    } else if (event.type.startsWith('response.reasoning_summary_part.')) {
      if (!object(event.part) || event.part.type !== 'summary_text' || typeof event.part.text !== 'string') throw fail('invalid_stream');
    } else if (event.type.endsWith('.delta') && typeof event.delta !== 'string') throw fail('invalid_stream');
    else if (event.type.endsWith('_text.done') && typeof event.text !== 'string') throw fail('invalid_stream');
  }
  function processEvent(event) {
    if (!object(event) || typeof event.type !== 'string') throw fail('invalid_stream');
    if (terminal) throw fail('after_terminal');
    responseIdentity(event.response_id);
    if (['response.failed', 'response.incomplete', 'error'].includes(event.type)) throw fail('failed');
    if (event.type.startsWith('response.refusal.')) throw fail('refused');
    if (['response.created', 'response.in_progress', 'response.queued'].includes(event.type)) {
      if (!object(event.response) || !identifier(event.response.id)) throw fail('identity_conflict');
      responseIdentity(event.response.id);
      if (event.response.error != null || event.response.incomplete_details != null ||
          (event.response.status !== undefined && !['in_progress', 'queued'].includes(event.response.status))) throw fail('failed');
      if (event.response.output !== undefined) {
        if (!Array.isArray(event.response.output)) throw fail('invalid_stream');
        event.response.output.forEach((output, index) => acceptItem(output, index, 'snapshot'));
      }
    } else if (event.type === 'response.output_item.added' || event.type === 'response.output_item.done') {
      acceptItem(event.item, event.output_index, event.type.endsWith('.added') ? 'added' : 'done');
    } else if (event.type === 'response.function_call_arguments.delta') {
      const record = eventRecord(event, 'function_call');
      if (record.done || record.argumentsDone || typeof event.delta !== 'string') throw fail('conflicting_output');
      record.delta += event.delta; record.hasDelta = true;
      if (Buffer.byteLength(record.delta) > MUSIC_PROPOSAL_LIMITS.argumentBytes) throw fail('arguments_limit');
    } else if (event.type === 'response.function_call_arguments.done') {
      const record = eventRecord(event, 'function_call');
      if (record.itemDone || record.argumentsDone) throw fail('conflicting_output');
      finalizeArguments(record, event.arguments); record.argumentsDone = true;
    } else if (event.type === 'response.completed') {
      const result = event.response;
      if (!object(result) || !identifier(result.id) || result.status !== 'completed' || result.error != null || result.incomplete_details != null) throw fail('failed');
      responseIdentity(result.id);
      if (result.output !== undefined) {
        if (!Array.isArray(result.output) || result.output.length > 256) throw fail('invalid_stream');
        for (const index of records.keys()) if (index >= result.output.length) throw fail('conflicting_output');
        result.output.forEach((output, index) => acceptItem(output, index, 'terminal'));
      }
      const proposals = [...records.values()].filter(record => record.type === 'function_call');
      if (proposals.length !== 1 || !proposals[0].done || proposals[0].finalText === undefined) throw fail('missing_proposal');
      terminal = true;
    } else if (ignoredTypes.has(event.type)) {
      ignoreContent(event);
    } else throw fail('unsupported_tool');
  }
  function dispatch() {
    if (!hasRecord) { eventBytes = 0; return; }
    eventCount += 1;
    if (eventCount > MUSIC_PROPOSAL_LIMITS.eventCount) throw fail('event_count_limit');
    const data = dataLines.join('\n'); const named = eventName;
    const hasData = dataLines.length > 0;
    dataLines = []; eventName = undefined; hasRecord = false; eventBytes = 0;
    if (!hasData) return;
    if (data === '[DONE]') {
      if (!terminal || sentinel || named !== undefined) throw fail('after_terminal');
      sentinel = true; return;
    }
    const event = strictJSON(data);
    if (named !== undefined && named !== event?.type) throw fail('identity_conflict');
    processEvent(event);
  }
  function finishLine() {
    const value = line; line = ''; lineBytes = 0;
    if (value === '') { dispatch(); return; }
    hasRecord = true;
    if (value.startsWith(':')) return;
    const separator = value.indexOf(':');
    const field = separator < 0 ? value : value.slice(0, separator);
    const raw = separator < 0 ? '' : value.slice(separator + 1);
    const content = raw.startsWith(' ') ? raw.slice(1) : raw;
    if (terminal && field !== 'data' && value.trim()) throw fail('after_terminal');
    if (field === 'data') dataLines.push(content);
    if (field === 'event') {
      if (eventName !== undefined) throw fail('invalid_stream');
      eventName = content;
    }
  }
  function newline(size) {
    eventBytes += size;
    if (eventBytes > MUSIC_PROPOSAL_LIMITS.eventBytes) throw fail('event_limit');
    finishLine();
  }
  function consume(text) {
    for (const character of text) {
      if (pendingCR) {
        pendingCR = false;
        if (character === '\n') { newline(2); continue; }
        newline(1);
      }
      if (character === '\r') pendingCR = true;
      else if (character === '\n') newline(1);
      else {
        const size = Buffer.byteLength(character); eventBytes += size; lineBytes += size;
        if (eventBytes > MUSIC_PROPOSAL_LIMITS.eventBytes || lineBytes > MUSIC_PROPOSAL_LIMITS.eventBytes) throw fail('event_limit');
        line += character;
      }
    }
  }
  function nextChunk() {
    stopped();
    return new Promise((resolve, reject) => {
      let settled = false;
      const cleanup = () => { clearTimeout(idle); stop.removeEventListener('abort', abort); };
      const finish = (error, value) => {
        if (settled) return;
        settled = true; cleanup();
        if (error) reject(error); else resolve(value);
      };
      const abort = () => { try { stopped(); } catch (error) { finish(error); } };
      const idle = setTimeout(() => finish(fail('idle_timeout')), idleTimeoutMs);
      stop.addEventListener('abort', abort, { once: true });
      Promise.resolve().then(() => { stopped(); return reader.read(); }).then(value => finish(null, value), error => finish(error));
    });
  }

  try {
    reader = body.getReader();
    for (;;) {
      const chunk = await nextChunk(); stopped();
      if (!object(chunk) || typeof chunk.done !== 'boolean') throw fail('invalid_stream');
      if (chunk.done) {
        if (chunk.value !== undefined) throw fail('invalid_stream');
        let tail;
        try { tail = decoder.decode(); } catch { throw fail('invalid_utf8'); }
        consume(tail);
        if (pendingCR) { pendingCR = false; newline(1); }
        if (line) finishLine(); dispatch();
        break;
      }
      if (!(chunk.value instanceof Uint8Array)) throw fail('invalid_stream');
      if (chunk.value.byteLength === 0) {
        emptyChunks += 1;
        if (emptyChunks > MUSIC_PROPOSAL_LIMITS.eventCount) throw fail('invalid_stream');
        continue;
      }
      wireBytes += chunk.value.byteLength;
      if (wireBytes > MUSIC_PROPOSAL_LIMITS.wireBytes) throw fail('wire_limit');
      let text;
      try { text = decoder.decode(chunk.value, { stream: true }); } catch { throw fail('invalid_utf8'); }
      consume(text);
    }
    stopped();
    if (!terminal) throw fail('incomplete_stream');
    const proposal = [...records.values()].find(record => record.type === 'function_call');
    return { operations: [{ kind: 'gain', track_id: expectedTrackId, value: proposal.gain }] };
  } catch (error) {
    if (signal?.aborted) throw fail('cancelled');
    if (error instanceof MusicProposalStreamError) throw error;
    throw fail('invalid_stream');
  } finally {
    clearTimeout(timeout);
    if (reader) {
      try { void Promise.resolve(reader.cancel()).catch(() => {}); } catch {}
      try { reader.releaseLock(); } catch {}
    }
  }
}
