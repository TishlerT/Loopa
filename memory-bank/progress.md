# Progress Log

## Completed
- [x] Core looper functionality (record, play, pause, restart)
- [x] Multi-track support
- [x] Quantization system (time-based and beat-based)
- [x] Vocal recording
- [x] Metronome and count-in
- [x] BPM control with editor sheet
- [x] Instrument selection
- [x] Session save/load
- [x] XCUITest framework setup
- [x] CLI test runner scripts
- [x] Screenshot capture on failure
- [x] JSON result parsing for AI debugging
- [x] **Tracks Mixer + Track Focus MIDI Editor (Phase 1 & 2)**
  - Beat-based MidiNote model (replaces time-based events for editing)
  - Solo/mute audibility logic
  - TracksView with M/S/Q buttons, volume slider, instrument picker
  - BPMEditorView with steppers and numeric input
  - TrackFocusView with full-screen piano roll editor
  - PianoRollCanvasView with Canvas-based rendering
  - Note selection, drag-to-move, handle-to-resize, long-press-to-delete
  - Grid snapping and loop bounds clamping
- [x] **App Store Submission Preparation**
  - Fixed ScreenshotTests to work without Fastlane
  - Fixed BarCountTests assertion
  - Excluded unused ContentView/Freesound code from build
  - Verified tests pass on iPhone 16e, iPhone 16 Pro Max, iPad Pro 13-inch
  - Verified screenshot capture on all devices
- [x] **Audio-Visual Sync & Vocal Recording Fixes**
  - Fixed visual lag at loop boundaries (DisplayLink-based UI updates)
  - Fixed audio glitch during vocal recording (stale `isPlaying` state causing double-start)
  - Pre-configure audio session during count-in (prevents playback interruption)

## Test Status
- Total: 139 tests (119 unit + 20 UI)
- Passing: 119 unit tests (UI tests experiencing simulator infrastructure issues)
- Failing: 0 unit test failures

## Device Testing
| Device | Tests | Status |
|--------|-------|--------|
| iPhone 16 Pro | 20 | ✓ Pass |
| iPhone 16e | 20 | ✓ Pass |
| iPhone 16 Pro Max | 20 | ✓ Pass |
| iPad Pro 13-inch (M4) | 20 | ✓ Pass |

## Known Issues
- Restart button tests require 3+ second wait due to count-in timing
- Maestro framework cannot detect `recordButton` (works with other buttons)
- Project warnings about duplicate file group membership (cosmetic only)

## App Store Submission Status
**Ready for submission** pending external setup:
1. ~~Privacy policy URL (tishstudios.com/privacy)~~ ✓ Linked in Settings
2. Support email confirmation
3. App Store Connect metadata
4. Apple Developer account verification

## Final Fixes (Jan 2026)
- [x] Fixed audio export: MIDI notes now render correctly in offline mode (sample-accurate triggering)
- [x] Share Beat now exports playable M4A audio instead of .loopa project files
- [x] Privacy Policy now links to tishstudios.com/privacy instead of showing in-app view
- [x] Deleted PrivacyPolicyView.swift (no longer needed)
- [x] **Fixed volume slider real-time feedback** - Volume changes now heard instantly while dragging slider (was only updating on release)
- [x] **Added TrackVolumeTests** - 18 new unit tests verifying track volume independence

## Optional Future Enhancements
- [ ] Add double-tap to add note in piano roll
- [ ] Add playhead visualization in piano roll
- [ ] Consider iPad split view for Tracks/TrackFocus
