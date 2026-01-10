# Active Context

## Current Focus
UX improvements and polish for app release.

## Recent Work (This Session)
1. **Fixed iPad MIDI Editor Playhead Selection Bug** - Bug fix:
   - **Issue:** On iPad, tapping notes in the piano roll editor would accidentally select the playhead instead.
   - **Root Cause:** Two issues: (1) `playheadHitWidth` was fixed at 30pt and didn't scale for iPad's larger screen, (2) tap gesture checked playhead BEFORE notes, so any tap near the playhead would select it instead of the intended note.
   - **Fix:** Made `playheadHitWidth` adaptive (20pt on iPad, 30pt on iPhone) and reordered tap gesture to check notes FIRST, then playhead only if no note was found.
   - All 158 unit tests + 20 UI tests pass on both iPad and iPhone

## Previous Sessions
1. **Fixed First Vocal Recording Bug** - Bug fix:
   - **Issue:** First vocal recording after app restart failed silently. Waveform visual incorrectly responded to metronome during count-in instead of actual voice input.
   - **Root Cause:** `stopMonitoring()` reset audio session to `.playback` mode even when `sessionPreparedForRecording` was true (set during count-in). Then `startRecording()` skipped session config because it thought session was already prepared.
   - **Fix:** Added `&& !sessionPreparedForRecording` check in `stopMonitoring()` to preserve the pre-configured session.
   - All 20 tests pass

## Previous Sessions
1. **Auto-Save/Auto-Restore Working Session** - New feature:
   - App now automatically saves the current session when going to background
   - On next launch, the session is automatically restored
   - Works even if user swipes app away without saving
   - Clears auto-save when user explicitly saves or clears all tracks
   - Added 6 unit tests for working session persistence
   - All 158 unit tests pass

## Previous Sessions
1. **Fixed Timeline Sync Bug** - Bug fix:
   - **Issue:** When recording tracks with different bar counts, the beat indicator (highlighted box) and progress bar would desync visually.
   - **Root Cause:** `synchronizedBeat` used `looper.synchronizedPlaybackPosition` (based on longest existing track's loop length), while `synchronizedProgressFraction` used `recordingProgress` (based on barCount setting) during recording. When these differed, the visuals desynced.
   - **Fix:** Updated `synchronizedBeat` in `LooperViewModel.swift` to derive beat from `recordingProgress` during recording, ensuring both beat indicator and progress bar use the same timing source.
   - All 20 tests pass

2. **Editor Hint for TracksView** - UX improvement:
   - Added dismissible hint above the tracks list: "👆 Tap a track to open the editor"
   - Hint only appears when there are tracks and user hasn't opened an editor yet
   - Uses `@AppStorage("hasOpenedEditor")` to persist preference across sessions
   - Once user taps a track to open the editor, hint is hidden permanently

## Previous Sessions
1. **Multi-Note Drag Feature** - New feature:
   - In multi-select mode, dragging one selected note now moves ALL selected notes together
   - Relative positions between notes are preserved during drag
   - Tapping empty background no longer deselects notes (allows panning with selection)
   - Visual preview shows all notes moving during drag
   - Background scroll now works while notes are selected (only locks during active drag)
   - Added 5 unit tests for multi-drag behavior
   - All 152 unit tests pass

2. **Note Preview on Add** - New feature:
   - When adding notes in the piano roll or drum grid, the sound now plays immediately as audible feedback
   - Added `previewNote()` method to `LooperViewModel` that plays a short (~150ms) preview using the track's instrument
   - Integrated preview call in `TrackFocusViewModel.addNote()` - works for both melodic instruments and drums
   - Added 5 new unit tests for preview functionality
   - All 147 unit tests pass

2. **Verified Copy/Paste Note Offset Preservation** - Investigation:
   - User reported pasted notes all landing at playhead position
   - Added 5 unit tests to verify copy/paste behavior
   - Tests confirmed the implementation is **already correct**: notes preserve relative offsets when copied and pasted
   - The leftmost note becomes the reference point, and all other notes maintain their offset from it
   - All 142 unit tests pass

2. **Fixed Pre-existing Test Build Issues**:
   - ScreenshotTests: Added stub functions for Fastlane snapshot helpers when not running via Fastlane
   - TrackVolumeTests: Fixed Float vs Double type mismatch in XCTAssertEqual calls

3. **Fixed Piano Roll Note Disappearing Bug** - Bug fix:
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
3. Verified all 147 unit tests pass on iPhone 16 Pro

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
