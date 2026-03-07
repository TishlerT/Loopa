# Cloud Agent: Android Environment Setup

You are a setup agent preparing a Linux cloud VM for Android app development. Your only job is to install and verify the complete Android development toolchain. You are not building the app yet — just preparing the environment.

## Context

This VM will be used to build and test a Kotlin + Jetpack Compose Android app that includes:
- Native C/C++ code via JNI (FluidSynth audio library compiled from source)
- Oboe audio library (C++ via CMake/NDK)
- kotlinx.serialization
- Jetpack Compose UI toolkit
- JUnit 5 unit tests (JVM-based, no emulator needed)
- Robolectric tests (JVM-based Android framework simulation, no emulator needed)
- Gradle Kotlin DSL multi-module build
- Maestro E2E testing framework (requires emulator — install if possible, skip gracefully if not)

The app targets `minSdk 29`, `targetSdk 34`, `compileSdk 34`.

## What to install

### 1. JDK 17

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk openjdk-17-jdk-headless
```

Verify: `java -version` shows 17. Set `JAVA_HOME`:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

Add to shell profile (`~/.bashrc` or `~/.profile`) so it persists.

### 2. Essential build tools

```bash
sudo apt-get install -y \
  git curl wget unzip zip \
  build-essential cmake ninja-build \
  python3 python3-pip python3-venv \
  pkg-config autoconf automake libtool \
  libglib2.0-dev libsndfile1-dev
```

The `libglib2.0-dev` and `libsndfile1-dev` packages are needed for compiling FluidSynth from source if the prebuilt AAR is unavailable.

### 3. Android command-line tools

Download the latest command-line tools from Google:

```bash
mkdir -p "$HOME/android-sdk/cmdline-tools"
cd /tmp
wget -q "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -O cmdline-tools.zip
unzip -q cmdline-tools.zip
mv cmdline-tools "$HOME/android-sdk/cmdline-tools/latest"
rm cmdline-tools.zip
```

If that URL is outdated, find the current one at https://developer.android.com/studio#command-line-tools-only and adjust accordingly.

Set environment variables (add to shell profile):

```bash
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

Source the profile: `source ~/.bashrc` (or equivalent).

### 4. SDK components

Accept licenses first, then install:

```bash
yes | sdkmanager --licenses

sdkmanager \
  "platforms;android-34" \
  "build-tools;34.0.0" \
  "platform-tools" \
  "ndk;26.1.10909125" \
  "cmake;3.22.1"
```

The NDK and CMake are required for compiling FluidSynth and Oboe native code.

### 5. Emulator (best-effort)

Check if KVM is available (hardware acceleration for x86_64 emulator):

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo  # >0 means KVM-capable CPU
ls /dev/kvm 2>/dev/null              # file exists means KVM is enabled
```

**If KVM is available** (`/dev/kvm` exists):

```bash
sudo apt-get install -y qemu-kvm
sdkmanager "system-images;android-34;google_apis;x86_64" "emulator"
avdmanager create avd -n Loopa_Test -k "system-images;android-34;google_apis;x86_64" --device "pixel_6" --force
```

Test headless emulator launch:

```bash
emulator -avd Loopa_Test -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
adb wait-for-device
adb shell getprop ro.build.version.sdk  # should return 34
```

**If KVM is NOT available**: skip emulator installation entirely. Log this:

```
EMULATOR_STATUS=unavailable
echo "KVM not available. Emulator skipped. Unit tests (./gradlew test) and Robolectric tests work without emulator. Instrumented tests (connectedAndroidTest) and Maestro E2E tests require local macOS verification or a device farm (BrowserStack/Firebase Test Lab)." > ~/EMULATOR_STATUS.txt
```

### 6. Maestro (best-effort, needs emulator)

Only install if emulator is available:

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$HOME/.maestro/bin:$PATH"
```

If no emulator, skip Maestro. It cannot run without a connected device or emulator.

### 7. Python packages for parity comparison scripts

```bash
python3 -m pip install --user numpy pillow scikit-image
```

These will be used later for screenshot comparison (SSIM), audio comparison, and state trace diffing.

### 8. Gradle wrapper

Gradle itself does NOT need manual installation. The project's `gradlew` wrapper script downloads the correct Gradle version automatically. Just ensure `JAVA_HOME` and `ANDROID_HOME` are set.

## Verification gate

Run every check below. **All must pass** (exit code 0) before reporting completion.

```bash
# JDK
java -version 2>&1 | grep -q "17\." && echo "PASS: JDK 17" || echo "FAIL: JDK 17"

# JAVA_HOME
[ -n "$JAVA_HOME" ] && echo "PASS: JAVA_HOME=$JAVA_HOME" || echo "FAIL: JAVA_HOME not set"

# Android SDK
[ -n "$ANDROID_HOME" ] && echo "PASS: ANDROID_HOME=$ANDROID_HOME" || echo "FAIL: ANDROID_HOME not set"

# sdkmanager
sdkmanager --version && echo "PASS: sdkmanager" || echo "FAIL: sdkmanager"

# adb
adb --version && echo "PASS: adb" || echo "FAIL: adb"

# NDK
[ -d "$ANDROID_HOME/ndk/26.1.10909125" ] && echo "PASS: NDK" || echo "FAIL: NDK"

# CMake
[ -d "$ANDROID_HOME/cmake/3.22.1" ] && echo "PASS: CMake" || echo "FAIL: CMake"

# Build tools
[ -d "$ANDROID_HOME/build-tools/34.0.0" ] && echo "PASS: build-tools 34" || echo "FAIL: build-tools 34"

# Platform
[ -d "$ANDROID_HOME/platforms/android-34" ] && echo "PASS: platform 34" || echo "FAIL: platform 34"

# Python
python3 -c "import numpy, PIL, skimage; print('PASS: Python packages')" || echo "FAIL: Python packages"

# Emulator (informational, not blocking)
if [ -e /dev/kvm ]; then
  emulator -list-avds 2>/dev/null | grep -q "Loopa_Test" && echo "PASS: Emulator AVD" || echo "INFO: Emulator installed but no AVD"
else
  echo "INFO: No KVM — emulator unavailable (unit tests still work)"
fi

# Maestro (informational, not blocking)
maestro --version 2>/dev/null && echo "PASS: Maestro" || echo "INFO: Maestro unavailable (needs emulator)"
```

## Completion report

When done, output a summary in exactly this format so downstream agents can parse it:

```
=== ENVIRONMENT SETUP COMPLETE ===
JDK:        17 (path: /usr/lib/jvm/java-17-openjdk-amd64)
JAVA_HOME:  <value>
ANDROID_HOME: <value>
SDK:        android-34
Build Tools: 34.0.0
NDK:        26.1.10909125
CMake:      3.22.1
Emulator:   available | unavailable
Maestro:    available | unavailable
Python:     numpy, pillow, scikit-image installed
===
Capabilities:
  ./gradlew assembleDebug          YES
  ./gradlew test                   YES
  ./gradlew connectedAndroidTest   <YES if emulator available, NO otherwise>
  maestro test                     <YES if emulator available, NO otherwise>
  ./gradlew bundleRelease          YES
  ./gradlew lint detekt ktlintCheck YES
===
```

If any critical check fails (JDK, ANDROID_HOME, sdkmanager, adb, NDK, CMake, build-tools, platform), do NOT report success. Debug and fix the failure. Emulator and Maestro are informational — their absence does not block the migration, it just means some verification must happen locally.

## Rules

- Do not install Android Studio. Command-line tools only.
- Do not modify any project source files. You are only setting up the environment.
- Do not clone or checkout any code. The repo is already present.
- Persist all environment variables in the shell profile so they survive new shell sessions.
- If a download URL is stale, search for the current URL and use that instead.
