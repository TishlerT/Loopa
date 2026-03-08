# Parity Verification Report

## State Parity — Proven on Cloud VM

### Enum Values ✅
- TrackType: 2 values (midi, audio) — matches iOS
- Instrument: 9 entries with correct displayNames, programNumbers, isDrumKit flags — matches iOS
- BarCount: 5 entries (1, 2, 4, 8, 16) — matches iOS
- QuantizeDivision: 5 entries with correct beatFractions — matches iOS

### Model Shapes ✅
- MidiNote: MIN_DURATION = 0.0625 (1/64 note) — matches iOS
- Track: default volume = 0.8, default isLooping = true, default recordedLengthBeats = 16.0 — matches iOS
- Track.isVocal correctly identifies audio tracks — matches iOS
- Vocal track defaults (name = "Vocals", program = 0, isDrumKit = false) — matches iOS
- Audibility: mute takes precedence over solo — matches iOS

### Quantization Logic ✅
- Time-based quantization at various BPMs (60, 120, 180) — matches iOS
- Beat-based quantization with loop wrapping — matches iOS
- Duration minimum constraints — matches iOS
- Drum auto-quantize to 16th notes — matches iOS
- Static helpers (snap, clamp, clampDuration) — matches iOS

### Serialization ✅
- SavedSession round-trip encode/decode — preserves all fields
- MidiNote noteName convention (C4 = pitch 60) — matches iOS

### ViewModel State ✅
- LooperViewModel default state matches iOS (bpm=100, barCount=4, instrument=Piano, quantize=Off)
- TrackFocusViewModel zoom limits match iOS (0.5-4.0 horizontal, 0.6-2.5 vertical)
- TrackFocusViewModel minNoteDuration = 0.125 — matches iOS
- Copy/paste preserves relative offsets — matches iOS
- Multi-drag preserves relative positions — matches iOS

## DEFERRED_TO_LOCAL

| Item | Reason |
|------|--------|
| Visual parity screenshots | No emulator for capture; only 6 of 10 iOS baselines exist |
| Audio parity (M4A export) | No audio stack on headless VM; no iOS audio export baselines |
| MIDI export comparison | No iOS MIDI export baselines |
| Maestro E2E flows | No emulator, no Maestro |
| Multi-touch keyboard behavior | Requires device |
| Piano roll gesture interaction | Requires device |
| Audio latency measurement | Requires device |
