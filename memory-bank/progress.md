# Progress

Updated 2026-10-05. Entries below distinguish verified results from implementation and earlier migration claims.

## Verified in current iOS staging
- `2d849969`: strict test runner with unique result bundles, explicit test-count expectations and fail-closed result parsing; full 178-test suite and post-integration smoke passed.
- `c4d8dfd5`: retain vocal media referenced by saved projects when removing live tracks; 180 app tests and 8 focused smoke tests passed. Tests decode actual recorded-file fixtures and check byte preservation.
- `70855dfb`: explicit storage results, isolated fault injection and preservation of corrupt/unreadable session files; 193 app tests and 13 post-integration storage tests passed. Three intentional negative controls reproduced the previous destructive behavior.
- `9abbf646`: failure-aware save/recovery and recoverable Save UI, including prior-project identity protection; 217 full iPhone tests, four iPad save journeys and 20 post-integration persistence tests passed. Save-error screenshots were inspected on both layouts.
- Exact candidate review, artifact hashes, remote staging verification and post-integration smoke are required for each integration. Main remains unchanged by these improvements.

## In progress / not integrated
- AAC export writer: complete stereo conversion, owned temporary outputs, full-file decode checks, eight new tests and retained AAC/WAV artifacts. Source review alone is not runtime proof.
- Independent audits: export inclusion/solo/timing/gain, reversible edits, design direction, sound provenance.

## Required next evidence
- Actual AAC decode validation, then vocal inclusion, mute/solo, musical timing and consistent relative levels in the full exporter.
- Core journey covering record, layer, edit, audition, undo, save, relaunch and export with content assertions.
- Shared reversible edit proposals with stale-response, cancellation, scope, retry and offline tests; text before a bounded voice experiment.
- Current iPhone and iPad screenshots, coherent style guidance, useful sound palette with established provenance, and a final listening/usability comparison.
- Physical-device audio QA and current distribution tooling before release; neither is certified by simulator success.

## Known limitations and deferred work
- Retained orphan vocal files need reference-aware cleanup. Already deleted historical recordings cannot be recovered by the retention fix.
- Current exporter still omits vocals and lacks verified solo, gain and sample-accurate event parity; fixing encoding alone will not complete export correctness.
- Existing screenshot tests may pass without capturing their intended screens outside Fastlane. Use actual retained xcresult/simulator images and inspect them.
- Session JSON test injection does not isolate every audio component; use a disposable app container.
- Android migration artifacts and historical passing JVM counts are retained, but do not establish a working Android exporter, device behavior or Play publication.
- Prior Android screenshot gaps remain historical gaps, not completed QA.
