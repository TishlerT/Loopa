# Active context

Updated 2026-10-05 after verification of staging `6fe4ad51b08cd93ff36d5d746c734c8950da13c6`.

## Product direction

Build a useful local music-making app with text assistance: select a track, request a change, hear the original and proposed version, keep or discard it, undo, save, reopen and export. Audio input for the assistant is deferred. The user will test the local experience before deciding how to release it publicly. Do not call Loopa the first AI music app or treat a test count as evidence of musical quality.

## Verified work

The current staging candidate passed 474 full iPhone simulator tests with no failures or skips, independent source review, remote/local Git identity checks, and 450 post-integration unit checks. Main remains at the original campaign baseline `b33f92fb2e7b48ee438ae8a3015e64353928c94a`.

Project storage now reports failures without silently replacing or deleting existing work. Saved vocal files survive removal from the current session. Actual AAC writing preserves complete stereo output. Offline exports include selected vocal and MIDI tracks and honor mute, solo and linear track gain; decoded synthetic audio verifies these behaviors.

Typed gain and bounded MIDI edits are guarded by session identity/revision and explicit selection. Assistant response parsing derives authority locally. Proposal state holds candidates separately from the project, rejects stale/cancelled/conflicting replies and supports explicit Keep and revision-checked Undo. These verified model components now also have a local HTTP client and exclusive preview audio ownership. The new assistant screen and controller remain a separate combined candidate awaiting full verification.

New vocal takes capture their beat period at recording start. Pending microphone permission is invalidated by transport actions and project replacement; a delayed grant cannot start recording after the user has moved on.

## Active work and limitations

Original/Change rendering and exclusive transport/audio ownership are integrated and verified. The assembled Mac bridge passed 410 Node tests, 61 native tests and a synthetic end-to-end default-runtime request, including signed identity, native IPC, bounded parsing, durable request reservation and restart. A CLI adds 45 tests. These are offline proofs, not actual account access. No real ChatGPT login or inference has occurred.

The visible local pilot supports one selected track's gain only: type a request, compare Original and Change, Keep/discard/Undo and save a recovery copy. No EQ, compression, voice input or automatic song generation is implemented in this slice. Review rejected the first screen candidate for an actual compile failure, hidden Undo after reopen/Refresh and ignored renewed pairing. Repairs preserve the same controller across re-pairing, keep Undo visible and block replacement while music is unsaved. The repaired full iOS suite and independent combined approval remain required before integration.

Keep and Undo save the current music; the Undo receipt itself survives panel dismissal but not app relaunch. The bridge uses a short-lived simulator pairing capability, keeps OAuth credentials on the Mac and durably permits one real inference request for this bounded personal pilot. Reconnection cannot reset that reservation. A future broader local trial needs an explicitly reviewed allowance change.

The planned personal test uses the user's ChatGPT allowance through the documented local sign-in path. Keep identity consent separate from usage permission. OAuth credentials stay on the Mac; no paid API fallback. Commercial/public eligibility and costs require a separate later decision. No production entitlement is established by offline tests.

The exporter still has block-based MIDI scheduling, and live MIDI gain/vocal looping can differ from offline output. Audition needs an explicit pause/drain boundary. No seamless live editing, physical microphone/latency quality or user listening approval is established. Proposal receipts are memory-only. The complete real-request, audible comparison, Keep/Undo, save/relaunch/export journey remains required.

## Campaign boundaries

Use isolated worktrees, one writer per file/interface, independent review and executed tests for exact candidates. Only the coordinator dispatches through the reviewed controller. Serialize simulator and integration access; retain failed candidates and results. The campaign deadline is immutable and must not renew automatically.

Staging only: no main promotion, app submission, public deployment, agreements, paid assets or personal device data changes. Use the disposable simulator bundle `com.loopa.campaign`. Cloud workers remain disabled until their dispatch adapter is verified. Paid API calls remain blocked pending reviewed credential/cost enforcement; never exceed the $20 aggregate cap or redeem a reset without its individual authorization.

Bundled SoundFont provenance remains unresolved: metadata identifies TimGM6mb, contrary to the old FluidR3/public-domain label. Do not copy installed commercial libraries. Android functionality/publication and distribution readiness remain unverified. The iPhone can remain unplugged during simulator development; physical audio QA is a separate release requirement.
