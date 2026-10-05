import test from 'node:test';
import assert from 'node:assert/strict';
import { readMusicProposal, MusicProposalStreamError, MUSIC_PROPOSAL_LIMITS } from '../proposal-stream.mjs';

const TRACK = '12345678-1234-4234-8234-123456789abc';
const OTHER = '98765432-1234-4234-8234-123456789abc';
const encoder = new TextEncoder();
const args = JSON.stringify({ track_id: TRACK, gain: 0.7 });
const item = (argumentsText = args, extra = {}) => ({ type: 'function_call', id: 'fc_1', call_id: 'call_1', namespace: 'loopa_music', name: 'propose_gain', arguments: argumentsText, ...extra });
const complete = (output = [item()]) => ({ type: 'response.completed', response: { id: 'resp_1', status: 'completed', ...(output === undefined ? {} : { output }) } });
const added = (extra = {}) => ({ type: 'response.output_item.added', response_id: 'resp_1', output_index: 0, item: item(''), ...extra });
const delta = (text = args, extra = {}) => ({ type: 'response.function_call_arguments.delta', response_id: 'resp_1', item_id: 'fc_1', output_index: 0, delta: text, ...extra });
const done = (extra = {}) => ({ type: 'response.output_item.done', response_id: 'resp_1', output_index: 0, item: item(), ...extra });
const frame = (event, newline = '\n') => `data: ${typeof event === 'string' ? event : JSON.stringify(event)}${newline}${newline}`;
const wire = (events, newline) => encoder.encode(events.map(event => frame(event, newline)).join(''));
const stream = chunks => new ReadableStream({ start(controller) { for (const chunk of chunks) controller.enqueue(chunk); controller.close(); } });
const parse = (events, options = {}) => readMusicProposal(stream([wire(events)]), { expectedTrackId: TRACK, ...options });
const expected = { operations: [{ kind: 'gain', track_id: TRACK, value: 0.7 }] };
const rejects = async (promise, code) => assert.rejects(promise, error => {
  assert.ok(error instanceof MusicProposalStreamError); if (code) assert.equal(error.code, code);
  assert.doesNotMatch(error.message, /server-secret|call_1|resp_1|12345678/); return true;
});

const sequence = () => [
  { type: 'response.created', response: { id: 'resp_1', status: 'in_progress' } },
  added(), delta(args.slice(0, 12)), delta(args.slice(12)),
  { type: 'response.function_call_arguments.done', response_id: 'resp_1', item_id: 'fc_1', output_index: 0, arguments: args },
  done(), complete(), '[DONE]',
];

test('returns one safe gain operation only after complete reconciled stream', async () => {
  assert.deepEqual(await parse(sequence()), expected);
});

test('accepts terminal response output without previous item events', async () => {
  assert.deepEqual(await parse([complete()]), expected);
});

test('accepts completed item when terminal response omits output', async () => {
  const terminal = { type: 'response.completed', response: { id: 'resp_1', status: 'completed' } };
  assert.deepEqual(await parse([done(), terminal]), expected);
});

test('terminal output can finalize a call after deltas without duplicate argument append', async () => {
  assert.deepEqual(await parse([added(), delta(), complete()]), expected);
});

for (const newline of ['\n', '\r\n', '\r']) {
  test(`supports every byte boundary with ${JSON.stringify(newline)} separators and Unicode`, async () => {
    const message = { type: 'message', id: 'msg_1', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: '🎵 café — 音楽' }] };
    const bytes = wire([complete([item(), message]), '[DONE]'], newline);
    for (let split = 1; split < bytes.length; split += 1) {
      assert.deepEqual(await readMusicProposal(stream([bytes.slice(0, split), bytes.slice(split)]), { expectedTrackId: TRACK }), expected, `split=${split}`);
    }
  });
}

test('supports one-byte chunks through Unicode and CRLF boundaries', async () => {
  const text = frame({ type: 'response.output_item.done', output_index: 1, item: { type: 'message', id: 'msg_1', content: [{ type: 'output_text', text: '🎹' }] } }, '\r\n');
  const bytes = encoder.encode(text + frame(complete([item(), { type: 'message', id: 'msg_1', content: [{ type: 'output_text', text: '🎹' }] }]), '\r\n'));
  assert.deepEqual(await readMusicProposal(stream([...bytes].map(byte => Uint8Array.of(byte))), { expectedTrackId: TRACK }), expected);
});

test('ignores bounded reasoning/text but rejects no-proposal completion', async () => {
  assert.deepEqual(await parse([complete([{ type: 'reasoning', id: 'reason_1', summary: [] }, item()])]), expected);
  await rejects(parse([complete([{ type: 'message', id: 'msg_1', content: [{ type: 'output_text', text: 'No edit.' }] }])]), 'missing_proposal');
});

test('SSE comments and multiline data are valid', async () => {
  const formatted = JSON.stringify(complete(), null, 2).split('\n').map(line => `data: ${line}`).join('\n');
  const bytes = encoder.encode(`: heartbeat\n\nevent: response.completed\n${formatted}\n\n: trailing comment\n\n`);
  assert.deepEqual(await readMusicProposal(stream([bytes]), { expectedTrackId: TRACK }), expected);
});

for (const [name, events] of [
  ['wrong response ID', [added(), delta(args, { response_id: 'resp_other' }), complete()]],
  ['wrong item ID', [added(), delta(args, { item_id: 'fc_other' }), complete()]],
  ['wrong output index', [added(), delta(args, { output_index: 1 }), complete()]],
  ['changed call ID', [added(), delta(), done({ item: item(args, { call_id: 'call_other' }) }), complete()]],
  ['duplicate added call', [added(), added(), complete()]],
  ['second call', [done(), done({ output_index: 1, item: item(args, { id: 'fc_2', call_id: 'call_2' }) }), complete()]],
  ['duplicate completed item', [done(), done(), complete()]],
  ['conflicting terminal arguments', [done(), complete([item(JSON.stringify({ track_id: TRACK, gain: 0.3 }))])]],
  ['conflicting delta and final', [added(), delta(JSON.stringify({ track_id: TRACK, gain: 0.3 })), done(), complete()]],
  ['delta after final', [added(), delta(), done(), delta(' '), complete()]],
  ['terminal missing previously completed call', [done(), complete([])]],
  ['unknown function', [complete([item(args, { name: 'execute_shell' })])]],
  ['missing namespace', [complete([item(args, { namespace: undefined })])]],
  ['wrong namespace', [complete([item(args, { namespace: 'system' })])]],
  ['unsupported tool', [complete([item(), { type: 'web_search_call', id: 'search_1' }])]],
  ['function output tool loop', [complete([item(), { type: 'function_call_output', id: 'output_1', output: 'server-secret' }])]],
  ['in-progress item in completed response', [complete([item(args, { status: 'in_progress' })])]],
  ['same item ID at another index', [done(), complete([item(), { type: 'reasoning', id: 'fc_1' }])]],
  ['delta without item declaration', [delta(), complete()]],
]) {
  test(`rejects ${name}`, async () => { await rejects(parse(events)); });
}

for (const [name, argumentText] of [
  ['wrong track', JSON.stringify({ track_id: OTHER, gain: 0.7 })],
  ['out-of-range high gain', JSON.stringify({ track_id: TRACK, gain: 1.01 })],
  ['negative gain', JSON.stringify({ track_id: TRACK, gain: -0.01 })],
  ['nonfinite numeric gain', `{"track_id":"${TRACK}","gain":1e309}`],
  ['string gain', JSON.stringify({ track_id: TRACK, gain: '0.7' })],
  ['missing field', JSON.stringify({ gain: 0.7 })],
  ['unknown field', JSON.stringify({ track_id: TRACK, gain: 0.7, command: 'server-secret' })],
  ['prototype key', `{"track_id":"${TRACK}","gain":0.7,"__proto__":{}}`],
  ['duplicate field', `{"track_id":"${TRACK}","gain":0.3,"gain":0.7}`],
  ['malformed argument JSON', '{'],
  ['array arguments', '[]'],
]) {
  test(`rejects ${name} in proposal arguments`, async () => { await rejects(parse([complete([item(argumentText)])])); });
}

for (const gain of [0, 1]) {
  test(`accepts boundary gain ${gain}`, async () => {
    assert.deepEqual(await parse([complete([item(JSON.stringify({ track_id: TRACK.toUpperCase(), gain }))])]), { operations: [{ kind: 'gain', track_id: TRACK, value: gain }] });
  });
}

for (const type of ['response.failed', 'response.incomplete', 'error', 'response.refusal.delta', 'response.refusal.done']) {
  test(`${type} after partial arguments produces no proposal`, async () => {
    await rejects(parse([added(), delta(args.slice(0, 8)), { type, response: { id: 'resp_1', error: { message: 'server-secret' } } }, complete()]));
  });
}

test('refusal content in terminal message rejects otherwise valid proposal', async () => {
  await rejects(parse([complete([item(), { type: 'message', id: 'msg_1', content: [{ type: 'refusal', refusal: 'server-secret' }] }])]), 'refused');
});

test('EOF before completion rejects complete-looking arguments', async () => { await rejects(parse([added(), delta(), done()]), 'incomplete_stream'); });
test('empty stream rejects', async () => { await rejects(parse([]), 'incomplete_stream'); });
test('non-completed terminal status rejects', async () => { const e = complete(); e.response.status = 'incomplete'; await rejects(parse([e])); });
test('completion with error rejects', async () => { const e = complete(); e.response.error = { message: 'server-secret' }; await rejects(parse([e])); });
test('trailing malformed JSON after valid completion rejects', async () => { await rejects(parse([complete(), '{server-secret'])); });
test('trailing second completion rejects', async () => { await rejects(parse([complete(), complete()])); });
test('trailing failure after completion rejects', async () => { await rejects(parse([complete(), { type: 'response.failed' }])); });
test('DONE sentinel is not a substitute for completion', async () => { await rejects(parse(['[DONE]'])); });
test('duplicate DONE sentinel rejects', async () => { await rejects(parse([complete(), '[DONE]', '[DONE]'])); });

test('fatal UTF-8 validation includes trailing bytes after completion', async () => {
  await rejects(readMusicProposal(stream([wire([complete()]), Uint8Array.of(0xff)]), { expectedTrackId: TRACK }), 'invalid_utf8');
});
test('truncated multibyte UTF-8 at EOF rejects', async () => {
  await rejects(readMusicProposal(stream([wire([complete()]), Uint8Array.of(0xf0, 0x9f)]), { expectedTrackId: TRACK }), 'invalid_utf8');
});

test('single chunk beyond total wire cap rejects', async () => {
  await rejects(readMusicProposal(stream([new Uint8Array(MUSIC_PROPOSAL_LIMITS.wireBytes + 1)]), { expectedTrackId: TRACK }), 'wire_limit');
});
test('many small chunks cannot bypass total wire cap', async () => {
  const bytes = encoder.encode(': ' + 'x'.repeat(2000) + '\n\n');
  const chunks = Array.from({ length: 132 }, () => bytes);
  await rejects(readMusicProposal(stream(chunks), { expectedTrackId: TRACK }), 'wire_limit');
});
test('oversized single SSE event rejects even below total cap', async () => {
  await rejects(readMusicProposal(stream([encoder.encode(': ' + 'x'.repeat(MUSIC_PROPOSAL_LIMITS.eventBytes))]), { expectedTrackId: TRACK }), 'event_limit');
});
test('event count includes comment records', async () => {
  await rejects(readMusicProposal(stream([encoder.encode(': ping\n\n'.repeat(257))]), { expectedTrackId: TRACK }), 'event_count_limit');
});
test('argument cap rejects oversized delta', async () => {
  await rejects(parse([added(), delta(' '.repeat(4097)), complete()]), 'arguments_limit');
});

test('abort interrupts a reader whose read and cancellation both remain pending', async () => {
  const controller = new AbortController(); let reads = 0; let cancels = 0;
  let entered; const reading = new Promise(resolve => { entered = resolve; });
  const body = { getReader() { return { read() { reads += 1; entered(); return new Promise(() => {}); }, cancel() { cancels += 1; return new Promise(() => {}); }, releaseLock() {} }; } };
  const result = readMusicProposal(body, { expectedTrackId: TRACK, signal: controller.signal });
  await reading; controller.abort(new Error('server-secret'));
  await rejects(result, 'cancelled'); assert.equal(reads, 1); assert.equal(cancels, 1);
});
test('idle deadline interrupts hung reader and does not await cancellation', async () => {
  const body = { getReader() { return { read: () => new Promise(() => {}), cancel: () => new Promise(() => {}), releaseLock() {} }; } };
  await rejects(readMusicProposal(body, { expectedTrackId: TRACK, idleTimeoutMs: 5, totalTimeoutMs: 100 }), 'idle_timeout');
});
test('total deadline includes waiting for EOF after completion', async () => {
  let first = true;
  const body = { getReader() { return { read() { if (first) { first = false; return Promise.resolve({ value: wire([complete()]), done: false }); } return new Promise(() => {}); }, cancel: () => new Promise(() => {}), releaseLock() {} }; } };
  await rejects(readMusicProposal(body, { expectedTrackId: TRACK, idleTimeoutMs: 100, totalTimeoutMs: 10 }), 'total_timeout');
});
test('invalid configuration cannot disable safety limits', async () => {
  await rejects(readMusicProposal(stream([]), { expectedTrackId: 'not-a-uuid' }), 'invalid_config');
  await rejects(readMusicProposal(stream([]), { expectedTrackId: TRACK, totalTimeoutMs: 45001 }), 'invalid_config');
});

test('exact event byte cap includes every CRLF byte', async () => {
  const maximum = ':'.concat('x'.repeat(MUSIC_PROPOSAL_LIMITS.eventBytes - 5), '\r\n\r\n');
  assert.equal(encoder.encode(maximum).byteLength, MUSIC_PROPOSAL_LIMITS.eventBytes);
  assert.deepEqual(await readMusicProposal(stream([encoder.encode(maximum), wire([complete()])]), { expectedTrackId: TRACK }), expected);
  await rejects(readMusicProposal(stream([encoder.encode(':' + 'x'.repeat(MUSIC_PROPOSAL_LIMITS.eventBytes - 4) + '\r\n\r\n')]), { expectedTrackId: TRACK }), 'event_limit');
});

test('exact argument cap is accepted; one extra byte is rejected', async () => {
  const padded = args.padEnd(MUSIC_PROPOSAL_LIMITS.argumentBytes, ' ');
  assert.deepEqual(await parse([complete([item(padded)])]), expected);
  await rejects(parse([complete([item(padded + ' ')])]), 'arguments_limit');
});

test('exact total wire cap is accepted; one extra trailing byte is rejected', async () => {
  const ending = wire([complete()]); let remaining = MUSIC_PROPOSAL_LIMITS.wireBytes - ending.byteLength;
  const chunks = [];
  while (remaining >= 3) {
    const size = Math.min(remaining, MUSIC_PROPOSAL_LIMITS.eventBytes);
    chunks.push(encoder.encode(':' + 'x'.repeat(size - 3) + '\n\n')); remaining -= size;
  }
  if (remaining) chunks.push(encoder.encode('\n'.repeat(remaining)));
  chunks.push(ending);
  assert.equal(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0), MUSIC_PROPOSAL_LIMITS.wireBytes);
  assert.deepEqual(await readMusicProposal(stream(chunks), { expectedTrackId: TRACK }), expected);
  await rejects(readMusicProposal(stream([...chunks, encoder.encode('\n')]), { expectedTrackId: TRACK }), 'wire_limit');
});

test('many small argument deltas cannot bypass argument cap', async () => {
  await rejects(parse([added(), ...Array.from({ length: 64 }, () => delta(' '.repeat(65))), complete()]), 'arguments_limit');
});

test('duplicate argument-done events reject', async () => {
  const event = { type: 'response.function_call_arguments.done', item_id: 'fc_1', output_index: 0, arguments: args };
  await rejects(parse([added(), event, event, complete()]), 'conflicting_output');
});

test('delta call ID conflicts are rejected', async () => {
  await rejects(parse([added(), delta(args, { call_id: 'call_other' }), complete()]), 'identity_conflict');
});

test('message events cannot reuse a function-call item identity', async () => {
  await rejects(parse([added(), { type: 'response.output_text.delta', item_id: 'fc_1', output_index: 0, delta: 'server-secret' }, complete()]), 'identity_conflict');
});

test('progress snapshots bind call identities without duplicating later item-added', async () => {
  const progress = { type: 'response.in_progress', response: { id: 'resp_1', output: [item('')] } };
  assert.deepEqual(await parse([progress, added(), delta(), done(), complete()]), expected);
  await rejects(parse([progress, complete([item(args, { call_id: 'different_call' })])]), 'identity_conflict');
});

test('duplicate and escaped prototype JSON keys are rejected', async () => {
  await rejects(parse(['{"type":"response.completed","type":"response.failed"}']), 'invalid_stream');
  await rejects(parse([complete([item(`{"track_id":"${TRACK}","gain":0.7,"\\u005f_proto__":{}}`)])]), 'invalid_arguments');
});

test('SSE event name must agree with the data event type', async () => {
  const bytes = encoder.encode(`event: response.failed\n${frame(complete())}`);
  await rejects(readMusicProposal(stream([bytes]), { expectedTrackId: TRACK }), 'identity_conflict');
});

test('truncated final JSON cannot be treated as a completion', async () => {
  const bytes = wire([complete()]);
  await rejects(readMusicProposal(stream([bytes.slice(0, -4)]), { expectedTrackId: TRACK }));
});

test('unknown trailing non-SSE text is rejected after completion', async () => {
  await rejects(readMusicProposal(stream([wire([complete()]), encoder.encode('server-secret')]), { expectedTrackId: TRACK }), 'after_terminal');
});

test('throwing reader cleanup cannot replace a verified result', async () => {
  let delivered = false;
  const body = { getReader() { return { read() { if (delivered) return { done: true }; delivered = true; return { done: false, value: wire([complete()]) }; }, cancel() { throw new Error('server-secret'); }, releaseLock() { throw new Error('server-secret'); } }; } };
  assert.deepEqual(await readMusicProposal(body, { expectedTrackId: TRACK }), expected);
});

test('rapid endless empty chunks are bounded without waiting for a timer', async () => {
  let reads = 0;
  const body = { getReader() { return { read() { reads += 1; return { done: false, value: new Uint8Array() }; }, cancel() {}, releaseLock() {} }; } };
  await rejects(readMusicProposal(body, { expectedTrackId: TRACK }), 'invalid_stream');
  assert.equal(reads, 257);
});

test('total deadline applies despite regularly arriving bytes', async () => {
  let pending;
  const body = { getReader() { return { read() { return new Promise(resolve => { pending = setTimeout(() => resolve({ done: false, value: encoder.encode(': ping\n\n') }), 2); }); }, cancel() { clearTimeout(pending); }, releaseLock() {} }; } };
  await rejects(readMusicProposal(body, { expectedTrackId: TRACK, totalTimeoutMs: 10, idleTimeoutMs: 100 }), 'total_timeout');
});

// Public Responses shapes, independently constructed from:
// https://developers.openai.com/api/reference/resources/responses/streaming-events
// https://developers.openai.com/cookbook/articles/gpt-oss/handle-raw-cot
function contentLifecycle(kind, annotation = undefined) {
  const reasoning = kind === 'reasoning';
  const id = reasoning ? 'rs_1' : 'msg_1';
  const text = 'Bounded 🎵 content.';
  const part = { type: reasoning ? 'reasoning_text' : 'output_text', text, ...(reasoning ? {} : { annotations: annotation == null ? [] : [annotation] }) };
  const initial = { type: kind, id, status: 'in_progress', content: [], ...(reasoning ? { summary: [] } : { role: 'assistant' }) };
  const finished = { ...initial, status: 'completed', content: [part] };
  const identity = { item_id: id, output_index: 0, content_index: 0 };
  const prefix = reasoning ? 'response.reasoning_text' : 'response.output_text';
  const events = [
    { type: 'response.output_item.added', output_index: 0, item: initial },
    { type: 'response.content_part.added', ...identity, part: { ...part, text: '', ...(reasoning ? {} : { annotations: [] }) } },
    { type: `${prefix}.delta`, ...identity, delta: text },
    ...(annotation === undefined ? [] : [{ type: 'response.output_text.annotation.added', ...identity, annotation_index: 0, annotation }]),
    { type: `${prefix}.done`, ...identity, text },
    { type: 'response.content_part.done', ...identity, part },
    { type: 'response.output_item.done', output_index: 0, item: finished },
    added({ output_index: 1 }), delta(args, { output_index: 1 }), done({ output_index: 1 }),
    complete([finished, item(args, { status: 'completed' })]),
  ];
  return events.map((event, index) => ({ ...event, sequence_number: index + 1 }));
}
const snapshot = (output, extra = {}, type = 'response.in_progress') => ({ type, response: { id: 'resp_1', status: 'in_progress', output, ...extra } });
const finalItem = (text = args) => item(text, { status: 'completed' });
const otherArgs = JSON.stringify({ track_id: TRACK, gain: 0.3 });

test('SIWC-SSE-02 regression: full documented reasoning content-part lifecycle accepts gain', async () => {
  assert.deepEqual(await parse(contentLifecycle('reasoning')), expected);
});
for (const annotation of [
  { type: 'url_citation', start_index: 0, end_index: 3, title: 'Reference', url: 'https://example.invalid/reference' },
  { type: 'file_citation', file_id: 'file_1', filename: 'synthetic.txt', index: 0 },
  { type: 'container_file_citation', container_id: 'container_1', file_id: 'file_1', filename: 'synthetic.txt', start_index: 0, end_index: 3 },
  { type: 'file_path', file_id: 'file_1', index: 0 },
  null,
]) {
  test(`SIWC-SSE-02 regression: documented annotation ${annotation?.type ?? 'null'} lifecycle accepts gain`, async () => {
    assert.deepEqual(await parse(contentLifecycle('message', annotation)), expected);
  });
}
for (const newline of ['\n', '\r\n', '\r']) {
  test(`reasoning content lifecycle supports single-byte Unicode chunks and ${JSON.stringify(newline)}`, async () => {
    const bytes = wire(contentLifecycle('reasoning'), newline);
    assert.deepEqual(await readMusicProposal(stream([...bytes].map(byte => Uint8Array.of(byte))), { expectedTrackId: TRACK }), expected);
  });
}
for (const [name, change] of [
  ['wrong item', event => { event.item_id = 'other_item'; }],
  ['wrong output index', event => { event.output_index = 1; }],
  ['missing identity', event => { delete event.item_id; delete event.output_index; }],
  ['wrong part type', event => { event.part.type = 'output_text'; }],
  ['refusal part', event => { event.part = { type: 'refusal', refusal: 'server-secret' }; }],
]) {
  test(`reasoning content still rejects ${name}`, async () => {
    const events = contentLifecycle('reasoning'); change(events[1]); await rejects(parse(events));
  });
}
test('annotation event cannot reuse a function-call item or wrong message index', async () => {
  const events = contentLifecycle('message', null); events[3].item_id = 'fc_1';
  await rejects(parse(events), 'identity_conflict');
  events[3].item_id = 'msg_1'; events[3].output_index = 1;
  await rejects(parse(events), 'identity_conflict');
});

test('SIWC-SSE-02 regression: completed progress snapshot cannot change at terminal', async () => {
  await rejects(parse([snapshot([finalItem(otherArgs)]), complete()]), 'conflicting_output');
});
test('SIWC-SSE-02 regression: done item cannot disagree with a later completed snapshot', async () => {
  await rejects(parse([done(), snapshot([finalItem(otherArgs)]), complete()]), 'conflicting_output');
});
for (const [name, events] of [
  ['previous deltas', [added(), delta(otherArgs), snapshot([finalItem()]), complete()]],
  ['previous argument done', [added(), { type: 'response.function_call_arguments.done', item_id: 'fc_1', output_index: 0, arguments: otherArgs }, snapshot([finalItem()]), complete()]],
  ['later item done', [snapshot([finalItem(otherArgs)]), done(), complete()]],
  ['later argument done', [snapshot([finalItem(otherArgs)]), { type: 'response.function_call_arguments.done', item_id: 'fc_1', output_index: 0, arguments: args }, complete()]],
  ['another completed snapshot', [snapshot([finalItem(otherArgs)]), snapshot([finalItem()]), complete()]],
  ['later delta', [snapshot([finalItem()]), delta(' '), complete()]],
  ['malformed completed arguments', [snapshot([finalItem('{')]), complete()]],
  ['empty completed arguments', [snapshot([finalItem('')]), complete()]],
]) {
  test(`completed snapshot reconciles ${name}`, async () => { await rejects(parse(events)); });
}
test('completed snapshot can consistently repeat through argument done, item done and terminal', async () => {
  assert.deepEqual(await parse([
    added(), delta(), snapshot([finalItem()]), snapshot([finalItem()]),
    { type: 'response.function_call_arguments.done', item_id: 'fc_1', output_index: 0, arguments: args },
    done(), snapshot([finalItem()]), complete(),
  ]), expected);
});
test('completed snapshot can supply the item when completed response omits output', async () => {
  assert.deepEqual(await parse([snapshot([finalItem()]), { type: 'response.completed', response: { id: 'resp_1', status: 'completed' } }]), expected);
});
test('partial progress snapshots remain non-final and do not duplicate argument deltas', async () => {
  assert.deepEqual(await parse([snapshot([item('', { status: 'in_progress' })]), added(), delta(), done(), complete()]), expected);
  assert.deepEqual(await parse([snapshot([item('{"track_id":', { status: 'in_progress' })]), added(), delta(), done(), complete()]), expected);
  await rejects(parse([snapshot([item('', { status: 'in_progress' })]), { type: 'response.completed', response: { id: 'resp_1', status: 'completed' } }]), 'missing_proposal');
});
for (const type of ['response.created', 'response.in_progress', 'response.queued']) {
  for (const [name, extra] of [
    ['failed status', { status: 'failed' }],
    ['incomplete status', { status: 'incomplete' }],
    ['cancelled status', { status: 'cancelled' }],
    ['non-null error', { error: { message: 'server-secret' } }],
    ['incomplete details', { incomplete_details: { reason: 'max_output_tokens' } }],
  ]) {
    test(`SIWC-SSE-02 regression: ${type} with ${name} cannot be rehabilitated`, async () => {
      await rejects(parse([snapshot([finalItem()], extra, type), complete()]), 'failed');
    });
  }
}
for (const status of ['failed', 'incomplete', 'cancelled']) {
  test(`failure-bearing item snapshot ${status} cannot be rehabilitated`, async () => {
    await rejects(parse([snapshot([item(args, { status })]), complete()]), 'failed');
  });
}

test('documented reasoning summary lifecycle stays non-authoritative', async () => {
  const initial = { type: 'reasoning', id: 'rs_summary', summary: [], status: 'in_progress' };
  const part = { type: 'summary_text', text: 'Considering the requested gain.' };
  const finished = { ...initial, summary: [part], status: 'completed' };
  const identity = { item_id: initial.id, output_index: 0, summary_index: 0 };
  assert.deepEqual(await parse([
    { type: 'response.output_item.added', output_index: 0, item: initial },
    { type: 'response.reasoning_summary_part.added', ...identity, part: { ...part, text: '' } },
    { type: 'response.reasoning_summary_text.delta', ...identity, delta: part.text },
    { type: 'response.reasoning_summary_text.done', ...identity, text: part.text },
    { type: 'response.reasoning_summary_part.done', ...identity, part },
    { type: 'response.output_item.done', output_index: 0, item: finished },
    complete([finished, finalItem()]),
  ]), expected);
});
test('completed snapshot still requires response.completed and EOF', async () => {
  await rejects(parse([snapshot([finalItem()])]), 'incomplete_stream');
});
test('failure-bearing progress after partial arguments produces no proposal', async () => {
  await rejects(parse([added(), delta(args.slice(0, 12)), snapshot([], { error: { message: 'server-secret' } }), complete()]), 'failed');
});
test('completed snapshot cannot hide a later conflicting partial snapshot', async () => {
  await rejects(parse([snapshot([finalItem()]), snapshot([item(otherArgs, { status: 'in_progress' })]), complete()]), 'conflicting_output');
});
for (const [name, change] of [
  ['invalid annotation index', event => { event.annotation_index = -1; }],
  ['invalid content index', event => { event.content_index = 0.5; }],
  ['missing annotation value', event => { delete event.annotation; }],
]) {
  test(`annotation metadata rejects ${name}`, async () => {
    const events = contentLifecycle('message', null); change(events[3]); await rejects(parse(events));
  });
}
test('ignored annotations and reasoning remain inside the event-byte cap', async () => {
  const annotated = contentLifecycle('message', { type: 'url_citation', title: 'x'.repeat(32_768) });
  await rejects(parse(annotated), 'event_limit');
  const reasoning = contentLifecycle('reasoning'); reasoning[2].delta = 'x'.repeat(32_768);
  await rejects(parse(reasoning), 'event_limit');
});
