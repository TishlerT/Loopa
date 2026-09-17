# Loopa

Loop-based music production app for iOS and Android. Open it and you are already in the workstation: pick an instrument, record a loop, layer tracks, edit MIDI, record vocals, and export the beat.

## Features

- 9 instruments: Piano, E-Piano, Organ, Guitar, Strings, Lead, Pad, Drums, Bass
- Multi-track looping with mute, solo, volume, and per-track instrument changes
- Loop lengths of 1, 2, 4, 8, or 16 bars, plus live and post-record quantization
- Full-screen piano-roll and drum-grid editor
- Vocal recording with live waveform feedback
- Session save/load, `.loopa` project import, and `.m4a` export
- Landscape-only dark studio UI

The app runs on-device and does not collect personal data. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Platforms

| Platform | Location | Status |
| --- | --- | --- |
| iOS | [`ios/`](ios/) | Shipped SwiftUI reference |
| Android | [`android-app/`](android-app/) | Kotlin / Jetpack Compose port |

`android/` is a frozen iOS source mirror for the Android migration. Do not treat it as the Android app.

## Build

**iOS** — open `ios/Loopa.xcodeproj` in Xcode.

**Android** — JDK 17 and Android SDK 34:

```bash
cd android-app
./gradlew assembleDebug
./gradlew test
```

Play Store packaging notes are in [PLAY_STORE_SUBMISSION_GUIDE.md](PLAY_STORE_SUBMISSION_GUIDE.md).
