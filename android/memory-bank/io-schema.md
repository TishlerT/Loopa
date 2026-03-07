# I/O Schema

Public interfaces, constants, state shapes, and environment variables.

## LooperViewModel State (Published Properties)

### Core Playback State

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `isRecording` | Bool | Currently recording instrument track | true/false |
| `isRecordingVocals` | Bool | Currently recording vocal track | true/false |
| `isPlaying` | Bool | Playback is active | true/false |
| `isPaused` | Bool | Playback is paused | true/false |
| `isCountingIn` | Bool | Count-in phase before recording | true/false |
| `countInBeat` | Int | Current count-in beat number | 4, 3, 2, 1, 0 |
| `tracks` | [Track] | Recorded loop tracks | Array of Track |
| `currentPosition` | Double | Playback position in loop | 0.0 to loopDuration |
| `currentBeat` | Int | Current beat number | 0 to (bars * beatsPerBar) |
| `recordingProgress` | Double | Recording progress indicator | 0.0 to 1.0 |

### Tempo & Quantization

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `bpm` | Double | Beats per minute | 40.0 to 240.0 |
| `barCount` | BarCount | Number of bars in loop | .one, .two, .four, .eight |
| `quantizeDivision` | QuantizeDivision | Current quantization setting | .off, .quarter, .eighth, .sixteenth |

### Instrument Selection

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `currentInstrument` | Instrument | Currently selected instrument | Instrument enum value |
| `octaveOffset` | Int | Keyboard octave shift | Integer offset |

### Audio State

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `isMetronomeOn` | Bool | Metronome enabled | true/false |
| `audioError` | String? | Audio initialization error message | nil or error string |
| `isVocalMode` | Bool | Vocal recording mode active | true/false |
| `showMicPermissionAlert` | Bool | Show microphone permission alert | true/false |
| `showHeadphoneRecommendation` | Bool | Show headphone recommendation | true/false |

### Session Management

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `savedSessions` | [SavedSession] | List of saved sessions | Array of SavedSession |
| `currentSessionName` | String | Name of current session | Any string |
| `showingSaveSheet` | Bool | Save session sheet visible | true/false |
| `showingLoadSheet` | Bool | Load session sheet visible | true/false |
| `isExporting` | Bool | Audio export in progress | true/false |

### UI Sheet State

| Name | Type | Description | Valid Values |
|------|------|-------------|--------------|
| `showingSettings` | Bool | Settings sheet visible | true/false |
| `showingTracksSheet` | Bool | Tracks mixer sheet visible | true/false |
| `showingBPMEditor` | Bool | BPM editor sheet visible | true/false |
| `selectedTrackForFocus` | Track? | Track selected for piano roll | nil or Track |

## Accessibility Identifiers

### Transport Controls (LooperView)

| Identifier | Element Type | Purpose |
|------------|--------------|---------|
| `recordButton` | Button | Start/stop recording |
| `playPauseButton` | Button | Toggle play/pause |
| `restartButton` | Button | Restart from beginning |
| `quantizeButton` | Button | Cycle quantization |
| `bpmButton` | Button | Open BPM editor |
| `tracksButton` | Button | Open tracks mixer |

### Track Mixer (TrackMixerRow)

| Identifier Pattern | Element Type | Purpose |
|--------------------|--------------|---------|
| `deleteButton_{trackId}` | Button | Delete track |
| `muteButton_{trackId}` | Button | Toggle track mute |
| `soloButton_{trackId}` | Button | Toggle track solo |
| `quantizeButton_{trackId}` | Button | Open quantize options for track |
| `loopButton_{trackId}` | Button | Toggle track looping |
| `instrumentButton_{trackId}` | Button | Open instrument picker for track |

## CLI Script Interfaces

### run_tests.sh
```
Options:
  --quick    Summary only (no JSON output)
  --ui       Run UI tests only
  --unit     Run unit tests only
  --test X   Run specific test X

Exit codes:
  0  All tests passed
  1  One or more tests failed
```

### parse_results.sh
```
Options:
  --summary   Full test summary JSON
  --tests     All tests with status
  --failures  Only failed tests (simplified JSON)

Output format (--failures):
{
  "totalTests": Int,
  "passed": Int,
  "failed": Int,
  "failures": [
    {
      "test": String,
      "error": String,
      "target": String
    }
  ]
}
```

## Timing Constants

| Name | Value | Description |
|------|-------|-------------|
| Count-in beats | 4 | Beats before recording starts |
| Default BPM | 100 | Starting tempo |
| BPM range | 40-240 | Valid tempo range |
| Count-in duration | ~2.4s | At 100 BPM (60/100 * 4) |

## Enums

### QuantizeDivision
```swift
enum QuantizeDivision {
    case off       // No quantization
    case quarter   // 1/4 note grid
    case eighth    // 1/8 note grid
    case sixteenth // 1/16 note grid
}
```

### BarCount
```swift
enum BarCount {
    case one   // 1 bar
    case two   // 2 bars
    case four  // 4 bars
    case eight // 8 bars
}
```

### Instrument
```swift
enum Instrument {
    case piano, ePiano, organ, strings, lead, pad, drumKit, bass808
    // General MIDI program numbers mapped internally
}
```

## File Formats

### .loopa Session File
- Extension: `.loopa`
- Content Type: `com.loopa.session`
- Format: JSON-encoded SavedSession struct
- Contains: name, bpm, barCount, tracks (with MidiNotes)

### MIDI Export
- Format: Standard MIDI File Type 0
- Resolution: 480 ticks per quarter note
- Channels: 0 (left hand), 1 (right hand)

### Audio Export
- Format: M4A (AAC-encoded)
- Sample Rate: 44100 Hz
- Channels: Stereo (2)
- Bit Rate: 128 kbps

## Bundle Identifiers

| Target | Bundle ID |
|--------|-----------|
| Loopa | com.loopa.app |
| LoopaTests | com.loopa.app.tests |
| LoopaUITests | com.loopa.app.uitests |

## Design System Constants

### Spacing (TishSpacing)
| Name | Value |
|------|-------|
| xs | 4pt |
| sm | 8pt |
| md | 12pt |
| lg | 16pt |
| xl | 24pt |
| xxl | 32pt |

### Corner Radius (TishRadius)
| Name | Value |
|------|-------|
| sm | 4pt |
| md | 8pt |
| lg | 12pt |
| xl | 16pt |
| full | 9999pt |

### Key Colors
| Name | Hex | Usage |
|------|-----|-------|
| tishBackground | #0D0D0D | Primary background |
| tishSurface | #1A1A1A | Cards/surfaces |
| tishAccent | #00E5FF | Primary accent (cyan) |
| tishAccentSecondary | #FF0080 | Secondary accent (magenta) |
| tishRecording | #FF3B3B | Recording state |
| tishPlaying | #00FF88 | Playing state |
