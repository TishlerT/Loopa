# Active Context

Updated 2026-10-05. This replaces the earlier unverified claim that the Android migration was complete.

## Current focus
Improve the iOS music-making experience through a bounded development campaign: protect projects, make exports trustworthy, then test reversible musical editing and a coherent visual design. The direct playing and editing experience is the product; conversation should support it.

## Verified baseline
- Original baseline: `b33f92f`, with 178 iOS tests passing on Xcode 16.4 and iOS 18.6 simulator.
- Current verified staging at this update: `9abbf646` on `codex/loopa-staging-20261005`.
- That staging build passed 217 app tests on iPhone, all four save journeys on iPad, and 20 post-integration persistence smoke tests.
- A previous improvement preserves recorded vocal files still referenced by saved projects; deleting a live track no longer deletes that shared media immediately. Reference-aware orphan cleanup remains pending.
- Storage now returns explicit read/write/delete outcomes, distinguishes absent files from unreadable/corrupt files, and preserves existing bytes on failed mutations.

- `9abbf646` adds failure-aware save, recovery, load/import and deletion outcomes, save-sheet retry/cancellation, and new-project identity protection. The revised landscape sheet keeps the error readable and the entered name intact.
- A prior candidate failed its swipe-dismissal test and was never merged; the corrected candidate passed every required check. Do not infer integration from a worker commit or a targeted pass.

## Work awaiting final verification
- Complete stereo AAC writing with independently decoded audio fixtures is implemented and source-reviewed; actual candidate Xcode verification remains pending.
- Reversible music-editing contract, shared manual/AI mutation boundaries, sound provenance and coherent visual direction are under critique. No live AI feature or sound-quality improvement is claimed complete.

## Operating decisions
- iOS first. Android is an incomplete implementation requiring a separate verification campaign; historical test counts do not prove export, audio or publication readiness.
- Use isolated Git worktrees. Assign one writer to each file/interface and serialize simulator use and staging integration.
- Independent review and executed tests must bind to the exact proposed candidate. Keep failures and rejected ideas as evidence. Never weaken a mandatory gate to obtain a pass.
- Staging only. Main promotion, distribution, public deployment and purchases are outside this campaign.
- Use disposable simulator/app storage. Preserve personal device projects and the original checkout.
- Cloud dispatch is disabled until a reliable adapter can be demonstrated. Local workers remain available.
- Live API experiments remain disabled until credential handling and aggregate cost enforcement are verified. Never put a permanent key in app code or this repository.

## Explicit limitations
- Existing Xcode supports local development. A newer upload toolchain and physical iPhone QA installation remain deferred; simulator results cannot establish microphone, Bluetooth, speaker echo or real-device latency quality.
- No store submission or Android publication is established.
- Bundled SoundFont metadata identifies TimGM6mb; existing FluidR3/public-domain labeling requires correction after the provenance audit. Do not copy installed instrument libraries or claim redistribution rights from their local availability.
- User listening/usability judgment remains distinct from agent review and numerical audio checks.
