# Active Context

## Current Focus
App Store Submission Readiness - Preparing Loopa for App Store submission.

## Recent Work (This Session)
1. **Fixed Piano Roll Note Disappearing Bug** - Bug fix:
   - **Issue:** When zoomed out in the piano roll editor, dragging a note and dropping it on the boundary between two pitch rows (e.g., between E and F) caused the note to disappear.
   - **Root Cause:** Pitch calculation used delta-based approach with `round()` which had edge cases at row boundaries.
   - **Fix:** Changed `handleDragChanged()` in `PianoRollCanvasView.swift` to use absolute Y-position with `floor()` to determine which pitch row the touch point is in. This ensures notes always snap to a valid pitch.
2. **Fixed Multi-Bar Recording Bug** - Bug fix:
   - **Root Cause:** In `MultiTrackLooper.addLiveEvent()`, event times were wrapped using `fmod(elapsed, loopLength)` where `loopLength` was based on the MAX of existing track lengths. When recording a 4-bar track after a 1-bar track, notes at beats 5-16 wrapped to beats 1-4.
   - **Effect:** Notes got "crammed" into the first bar(s) when recording a longer track after a shorter one.
   - **Fix:** Changed `addLiveEvent()` to use `recordStartTime` and `recordingLoopLengthBeats` (based on barCount setting) instead of global `loopLength`. Also fixed `stopRecording()` to use recording loop length for quantization and note conversion.
2. **Added Multi-Bar Recording Tests** - 2 new unit tests verifying:
   - Recording 4-bar track after 1-bar track places notes correctly
   - Recording 4-bar track after 2-bar track places notes correctly
3. Verified all 121 unit tests pass on iPhone 16 Pro

## App Store Readiness Checklist
### Already Complete (In Codebase)
- [x] Privacy Policy link (opens tishstudios.com/privacy in Safari)
- [x] Contact email (support@tishstudios.com in SettingsView.swift)
- [x] App Icon (1024x1024)
- [x] Privacy manifest (PrivacyInfo.xcprivacy)
- [x] Microphone usage description (Info.plist)
- [x] No "beta"/"coming soon" text
- [x] No Android references
- [x] No user accounts (no deletion needed)
- [x] No subscriptions (no disclosure needed)
- [x] SoundFont licensing (FluidR3 Public Domain, credited in Settings)
- [x] All tests passing on multiple device sizes
- [x] Screenshot infrastructure working

### External Tasks (User Must Complete)
- [ ] Host privacy policy at tishstudios.com/privacy
- [ ] Ensure support@tishstudios.com is monitored
- [ ] Create App Store Connect listing with:
  - App name, subtitle, description
  - Keywords, category (Music), age rating (4+)
  - Screenshots from all device sizes
  - Screen recording for complex features
- [ ] Verify Apple Developer account is active

## Key Decisions
- Excluded unused ContentView/Freesound subsystem from build to eliminate external API dependencies
- Screenshot tests use XCUITest attachments (work without Fastlane)
- App targets iOS 17.0+, iPhone and iPad (landscape only)

## Next Steps
- User: Set up domain, email, App Store Connect
- Submit to App Store for review
