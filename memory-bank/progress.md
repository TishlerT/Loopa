# Progress

Updated 2026-10-05. Completed entries require exact source, independent review, executed tests, verified staging identity and post-integration checks.

## Verified staging milestones

- `2d849969`: strict runner and fail-closed result parsing; 178 baseline tests.
- `c4d8dfd5`: preserve saved vocal media during live track deletion/undo; 180 full tests and eight focused checks.
- `70855dfb`: explicit storage outcomes and corrupt/unreadable-file preservation; 193 full tests and 13 storage checks. Negative controls reproduced the old data-loss behavior.
- `9abbf646`: recoverable Save UI, recovery/load/import/delete errors and new-project identity protection; 217 full iPhone tests, four iPad save journeys and 20 persistence checks.
- `ca7229b9`: complete stereo AAC writing and pure reversible edits; 260 full tests, eight AAC checks and 43 post-integration checks. The original incomplete-writer candidate failed and was not integrated.
- `6b42316b`: session revision ownership, strict edit guards and correct offline mute/solo/linear MIDI faders; 292 full tests and 268 post-integration unit checks.
- `42a85cbc`: offline vocal inclusion, resampling, stereo content, period padding/trimming and mixed vocal/MIDI output; 303 full tests, 17 focused checks and 17 post-integration checks. Independent decoding verified synthetic vocal presence, near-half amplitude at half gain and silence at zero. This does not prove live/export parity or musical quality.
- `f41b792e`: scoped assistant payload decoding, stale-safe model proposal/Keep/Undo lifecycle and captured vocal lengths with production permission cancellation; 381 full tests and 29 post-integration checks. The first candidate passed 368 tests but source review rejected a delayed-permission bug; that candidate was never integrated.

## Implemented separately, not complete product features

- Original/Change preview rendering/player controls and shared export reservation are under verification. They require host transport cutover and visible UI integration.
- Initial Mac ChatGPT sign-in grant component passed 70 offline synthetic tests and independent review. A reproduced browser-launch hang was repaired. Protected credential storage, refresh, bounded proposal streaming, local pairing and real-account testing remain separate work.
- Design, musical command, export and sound provenance audits are retained. Suggestions are not proof of implementation or rights.

## Completion still required

- A real text request through the user's own ChatGPT account produces a checked, audible proposal in the local app. No real authentication or model request has happened yet.
- Original/Change comparison, Keep, discard, Undo and useful error/cancel/offline states in the user interface, without overlapping playback or unintended project changes.
- Durable applied edits and honest failure handling through save, relaunch and export; one complete recorded/layered/edited project journey with content assertions.
- Resolve MIDI timing/live gain and vocal looping differences before claiming faithful live/export parity.
- Coherent styling, inspected iPhone/iPad layouts, sound licensing/provenance and user listening/usability review.
- A separate public-release decision after local testing; no store submission or Android publication is established.

## Known limitations

Old orphan vocal files need reference-aware cleanup. Historical deleted recordings cannot be recovered by the retention fix. Proposal history is bounded and in memory. Physical audio latency, microphone routing and Bluetooth behavior are not certified by simulator tests. Newer upload tooling and the Apple agreement remain deferred. Never relabel synthetic audio as a human recording or automated checks as a listening judgment.
