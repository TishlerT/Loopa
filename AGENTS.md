# Agents

## Cursor Cloud specific instructions

### Project Overview

Loopa is a native iOS music creation app (Swift 5.9 / SwiftUI / iOS 17+). The repo has two directories at the root—`ios/` and `android/`—but both contain the same iOS codebase. There is no Android code, no backend, and no server-side component.

### Critical Constraint: macOS Required for Build/Test/Run

This is a pure iOS project. **Building, running the app, and executing tests all require macOS with Xcode 15+ and an iOS Simulator.** On the Linux cloud VM, only the following are possible:

| Task | Available on Linux? | Command |
|------|-------------------|---------|
| **Lint (SwiftLint)** | Yes | `cd ios && swiftlint lint` |
| **Swift syntax check** | Yes | `swiftc -parse <file.swift>` |
| **Build app** | No (requires Xcode) | — |
| **Run unit tests** | No (requires iOS Simulator) | — |
| **Run UI tests** | No (requires iOS Simulator) | — |
| **Run the app** | No (requires iOS Simulator) | — |

### Installed Tools

- **Swift 6.0.3** at `/opt/swift/usr/bin/` (added to `PATH` via `~/.bashrc`). Used for `swiftc -parse` syntax checking. Backwards-compatible with Swift 5.9 source.
- **SwiftLint 0.57.1** at `/usr/local/bin/swiftlint`. Runs on all 63 `.swift` files in `ios/`.

### Lint

```bash
cd /workspace/ios && swiftlint lint
```

Exits with code 2 when there are errors (currently 65 identifier-name errors, 2712 trailing-whitespace warnings). No `.swiftlint.yml` config exists; all default rules apply.

### Syntax Validation

```bash
cd /workspace/ios && find . -name "*.swift" -not -path "./Package.swift" | xargs -I{} swiftc -parse {}
```

`swiftc -parse` checks syntax only (no type checking or linking), so it works even on files importing iOS frameworks like SwiftUI and AVFoundation.

### Build, Test, and Run (macOS only)

Refer to `ios/TESTING.md` and `ios/memory-bank/techContext.md` for the full set of `xcodebuild` and `xcrun simctl` commands. Key commands:

- **Generate Xcode project**: `xcodegen generate` (requires XcodeGen)
- **Build**: `xcodebuild -project Loopa.xcodeproj -scheme Loopa -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- **Run unit tests**: `./run_tests.sh --unit`
- **Run UI tests**: `./run_tests.sh --ui`
- **Parse test results**: `./parse_results.sh --summary`

### Key Gotchas

- The `Package.swift` at `ios/Package.swift` targets `.iOS(.v17)` and cannot be used with `swift build` on Linux.
- The `project.yml` (XcodeGen config) excludes several legacy source files from the Loopa build target—see the `excludes` list in `ios/project.yml`.
- Recording tests require a 3+ second wait after tapping record due to a 4-beat count-in at 100 BPM (~2.4s).
- The `android/` directory is a duplicate of `ios/`; changes should be made in `ios/` only.
