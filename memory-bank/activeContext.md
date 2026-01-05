# Active Context

## Current Focus
App Store Submission Readiness - Preparing Loopa for App Store submission.

## Recent Work (This Session)
1. **Fixed Volume Slider Real-Time Feedback** - Bug fix:
   - **Root Cause:** In `TrackMixerRow.swift`, the volume slider only called `onVolumeChange()` when drag ended, not during dragging. This meant the audio engine didn't receive volume updates until finger release.
   - **Effect:** User perceived that instruments "cut out" when adjusting volume slider during playback.
   - **Fix:** Added `onVolumeChange(newVolume)` call inside `.onChanged` gesture handler for instant audio feedback.
2. **Added TrackVolumeTests** - 18 new unit tests verifying:
   - Track volume independence (changing one doesn't affect others)
   - MIDI and vocal track volume isolation
   - Volume clamping at 0.0-1.0 boundaries
   - Volume persistence with mute/solo states
   - Session loading volume preservation
3. Previous session work:
   - Fixed vocal recording audio glitch (stale `isPlaying` state)
   - Fixed audio-visual sync issue (DisplayLink-based UI updates)
   - Audited codebase for App Store submission requirements
4. Verified all 119 unit tests pass on iPhone 16 Pro

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
