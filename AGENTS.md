# Agents

## Cursor Cloud specific instructions

### Project Overview

Loopa is a music creation app. The repo contains:
- `ios/` — the original iOS app (Swift 5.9 / SwiftUI / iOS 17+)
- `android/` — the Android port target (Kotlin / Jetpack Compose, in-progress migration)

### iOS Development (Linux limitations)

iOS build/test/run requires macOS + Xcode 15+ + iOS Simulator. On the Linux cloud VM, only lint and syntax checks are available:

- **Lint**: `cd /workspace/ios && swiftlint lint`
- **Syntax check**: `swiftc -parse <file.swift>` (syntax only, works on iOS-importing files)
- **Full build/test/run**: See `ios/TESTING.md` and `ios/memory-bank/techContext.md` for `xcodebuild`/`xcrun simctl` commands (macOS only)

### Android Development (fully available on Linux)

The Android toolchain is installed and ready:

| Component | Version / Path |
|-----------|---------------|
| JDK | 17 (`/usr/lib/jvm/java-17-openjdk-amd64`) |
| Android SDK | `~/android-sdk` |
| Build Tools | 34.0.0 |
| Platform | android-34 |
| NDK | 26.1.10909125 |
| CMake (SDK) | 3.22.1 |
| Emulator | Unavailable (no KVM on cloud VM) |
| Maestro | Unavailable (needs emulator) |

Environment variables `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT` and tool paths are set in `~/.bashrc`.

Key Android commands (once the Android project exists):
- **Build**: `./gradlew assembleDebug`
- **Unit tests**: `./gradlew test` (JVM-based, no emulator needed)
- **Lint/static analysis**: `./gradlew lint detekt ktlintCheck`
- **Instrumented tests**: Not possible without emulator; use device farm or local macOS

### Installed Tools

- **Swift 6.0.3** at `/opt/swift/usr/bin/` — for `swiftc -parse` syntax checking
- **SwiftLint 0.57.1** at `/usr/local/bin/swiftlint` — lint all `.swift` files in `ios/`
- **Python packages**: `numpy`, `pillow`, `scikit-image` — for screenshot/audio parity comparison scripts

### Key Gotchas

- The `ios/Package.swift` targets `.iOS(.v17)` and cannot be used with `swift build` on Linux.
- The `ios/project.yml` (XcodeGen config) excludes several legacy source files — see the `excludes` list.
- iOS recording tests require 3+ second wait after tapping record (4-beat count-in at ~2.4s at 100 BPM).
- KVM is not available on this cloud VM, so Android emulator and Maestro E2E tests cannot run. Unit tests and Robolectric tests work fine without an emulator.
- JDK 21 is also installed but JDK 17 is set as default (`JAVA_HOME`). The Android Gradle build requires JDK 17.
