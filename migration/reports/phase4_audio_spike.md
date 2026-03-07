# Phase 4: Audio Feasibility Spike — Report

## Summary
The audio module is structured with interface-based design for testability. Pure logic (note routing, timing math, state management) is verified via JVM unit tests with mock SynthEngine. Hardware interaction (actual FluidSynth JNI, audio output, mic recording) is deferred to device testing.

## What was proven on this VM

### 1. KeyboardSampler routing logic ✅
- 10 tests verify correct channel routing (melodic vs percussion channel 9)
- All instrument program changes route correctly
- Switching between instruments and drums works

### 2. LooperAudioEngine management ✅
- 9 tests verify track preparation, channel assignment, sampler pooling
- Live instrument switching works
- Vocal tracks correctly return null sampler (handled separately)

### 3. Metronome timing math ✅
- 7 tests verify BPM-to-interval calculation across tempos (60-200 BPM)
- State management (running, stopped) verified

### 4. AudioExporter state machine ✅
- 6 tests verify export state transitions, track filtering (solo/mute/vocal)
- Error handling for empty/all-muted track lists

## What is DEFERRED_TO_LOCAL

| Requirement | Status | Reason |
|-------------|--------|--------|
| FluidSynth loads GM.sf2 | DEFERRED_TO_LOCAL | No JNI on headless VM |
| FluidSynth plays notes | DEFERRED_TO_LOCAL | No audio output on VM |
| Metronome timing accuracy | DEFERRED_TO_LOCAL | Needs real Handler looper |
| Vocal recording via mic | DEFERRED_TO_LOCAL | No audio input on VM |
| M4A export produces valid file | DEFERRED_TO_LOCAL | Needs MediaCodec/MediaMuxer |
| Audio latency measurement | DEFERRED_TO_LOCAL | Needs device |

## FluidSynth integration plan
The `SynthEngine` interface is defined. The `FluidSynthEngine` implementation has stub TODOs for JNI calls. When a FluidSynth AAR (e.g., `net.volcanomobile.fluidsynth-android:fluidsynth-android`) is available, the implementation will call:
- `fluid_settings_new()`, `fluid_synth_new()`, `fluid_audio_driver_new()`
- `fluid_synth_sfload()` for GM.sf2
- `fluid_synth_noteon()`, `fluid_synth_noteoff()`, `fluid_synth_program_change()`

Alternative: compile FluidSynth from source via CMake/NDK if no suitable AAR works.

## LGPL compliance
FluidSynth will be used as a shared library (`.so`) via dynamic linking. The app structure supports this through the JNI interface pattern.

## Test count
- KeyboardSamplerTest: 10 tests
- LooperAudioEngineTest: 9 tests
- MetronomeTest: 7 tests
- AudioExporterTest: 6 tests
- **Total Phase 4: 32 tests, all passing**
