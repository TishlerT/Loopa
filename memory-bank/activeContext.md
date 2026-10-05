# Active context

Updated 2026-10-05 after verification of staging `f41b792e98cc9f3c1e24c423f577756f6064b28e`.

## Product direction

Build a useful local music-making app with text assistance: select a track, request a change, hear the original and proposed version, keep or discard it, undo, save, reopen and export. Audio input for the assistant is deferred. The user will test the local experience before deciding how to release it publicly. Do not call Loopa the first AI music app or treat a test count as evidence of musical quality.

## Verified work

The current staging candidate passed 381 full iPhone simulator tests with no failures or skips, independent source review, remote/local Git identity checks, and 29 post-integration recording lifecycle checks. Main remains at the original campaign baseline `b33f92fb2e7b48ee438ae8a3015e64353928c94a`.

Project storage now reports failures without silently replacing or deleting existing work. Saved vocal files survive removal from the current session. Actual AAC writing preserves complete stereo output. Offline exports include selected vocal and MIDI tracks and honor mute, solo and linear track gain; decoded synthetic audio verifies these behaviors.

Typed gain and bounded MIDI edits are guarded by session identity/revision and explicit selection. Assistant response parsing derives authority locally. Proposal state holds candidates separately from the project, rejects stale/cancelled/conflicting replies and supports explicit Keep and revision-checked Undo. These model components are not yet connected to a production assistant screen.

New vocal takes capture their beat period at recording start. Pending microphone permission is invalidated by transport actions and project replacement; a delayed grant cannot start recording after the user has moved on.

## Active work and limitations

Original/Change audio comparison and its shared renderer reservation are isolated implementations awaiting combined verification. The Mac sign-in grant component passed 70 synthetic tests and independent review after a browser-launch timing repair. No real ChatGPT login or inference has occurred. Protected storage, local pairing, provider transport and the assistant screen still need integration.

The planned personal test uses the user's ChatGPT allowance through the documented local sign-in path. Keep identity consent separate from usage permission. OAuth credentials stay on the Mac; no paid API fallback. Commercial/public eligibility and costs require a separate later decision. No production entitlement is established by offline tests.

The exporter still has block-based MIDI scheduling, and live MIDI gain/vocal looping can differ from offline output. Audition needs an explicit pause/drain boundary. No seamless live editing, physical microphone/latency quality or user listening approval is established. Proposal receipts are memory-only; durable Keep/Undo and a full save/relaunch/export journey remain required.

## Campaign boundaries

Use isolated worktrees, one writer per file/interface, independent review and executed tests for exact candidates. Only the coordinator dispatches through the reviewed controller. Serialize simulator and integration access; retain failed candidates and results. The campaign deadline is immutable and must not renew automatically.

Staging only: no main promotion, app submission, public deployment, agreements, paid assets or personal device data changes. Use the disposable simulator bundle `com.loopa.campaign`. Cloud workers remain disabled until their dispatch adapter is verified. Paid API calls remain blocked pending reviewed credential/cost enforcement; never exceed the $20 aggregate cap or redeem a reset without its individual authorization.

Bundled SoundFont provenance remains unresolved: metadata identifies TimGM6mb, contrary to the old FluidR3/public-domain label. Do not copy installed commercial libraries. Android functionality/publication and distribution readiness remain unverified. The iPhone can remain unplugged during simulator development; physical audio QA is a separate release requirement.
