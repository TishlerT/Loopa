# Loopa — College Application Activity Entries

## Verified Facts

- **App name**: Loopa
- **Studio**: Tish Studios (tishstudios.com)
- **Platform**: iOS 17.0+ (iPhone & iPad), SwiftUI, Swift 5.9
- **Purpose**: Loop-based music creation app — record, layer, and loop instruments and vocals in real-time
- **Core features verified in codebase**:
  - Multi-instrument keyboard (piano, synths, drums, 808s, organ, strings, lead, pad, bass)
  - Multi-track loop recording with layering (1-16 bars)
  - Vocal recording with microphone access
  - Piano roll MIDI editor with note selection, move, resize, delete
  - Drum step sequencer (16th-note grid)
  - Quantization options (1/4, 1/8, 1/16 note grids)
  - Solo, mute, volume per track
  - Session save/load with custom .loopa file format
  - M4A audio export (AAC, 128kbps)
  - Standard MIDI file export (Type 0)
  - Metronome with 4-beat count-in
  - BPM control (40-240 BPM)
- **Technical stack & engineering signals**:
  - AVAudioEngine with offline rendering for audio export
  - AVAssetWriter for M4A encoding
  - SoundFont (.sf2) instrument loading via AVAudioUnitSampler
  - General MIDI program mapping
  - Standard MIDI file format implementation (header/track chunks, variable-length quantities)
  - Security-scoped URL access for file imports
  - JSON-based session serialization
  - Privacy manifest (PrivacyInfo.xcprivacy) — no tracking, no data collection
  - XcodeGen for declarative project configuration
  - Fastlane for App Store screenshot automation
  - **127 test functions** across 12 test files (unit + UI)
  - XCUITest framework with accessibility identifiers
  - Custom CLI test runner with JSON result parsing
  - MVVM architecture (ViewModels, Models, UI layers)
  - Design system with named colors, typography, spacing constants
- **Pricing model (per website)**: Free, no ads, no subscriptions
- **Website tagline**: "Create music anywhere"

---

## Missing Info

1. **Is Loopa currently published on the App Store, or is it pending App Review?**
2. **If published, what is the App Store URL?**

---

## Entry Format

Each entry includes:
- **Tight**: ≤150 characters
- **Extended**: ≤300 characters
- Character count in parentheses at end

---

# Set 1: Core Entries (Impact / Wholesome / Technical)

## A1 Impact / Published / No-AI

**Tight:**
Built and shipped Loopa, a free iOS music app with multi-track recording, MIDI editing, and audio export — 127 automated tests. (127)

**Extended:**
Designed and developed Loopa, an iOS music production app on the App Store. Features multi-instrument keyboard, loop recorder, piano roll, and audio/MIDI export. Built with SwiftUI and AVAudioEngine. Wrote 127 automated tests. Free with no ads — making music creation accessible. (282)

---

## A2 Wholesome / Published / No-AI

**Tight:**
Created Loopa, a free iOS app that helps anyone make music — no experience required. Multi-track loops, MIDI editor, export. (124)

**Extended:**
Built Loopa to make music creation accessible. Multi-instrument keyboard, loop recording, vocal layers, and a piano roll editor — all free, no ads, no subscriptions. Shipped to the App Store for iPhone and iPad. My goal: give everyone the tools to create, not just consume. 127 tests ensure reliability. (297)

---

## A3 Technical / Published / No-AI

**Tight:**
Shipped Loopa for iOS: SwiftUI + AVAudioEngine, offline audio rendering, MIDI export, 127 tests. Free on the App Store. (120)

**Extended:**
Developed Loopa, an iOS music app using SwiftUI, AVAudioEngine, and AVAssetWriter for offline M4A rendering. Implemented MIDI file export, SoundFont instruments, and quantization. XCUITest suite with 127 tests, Fastlane for automation. Published on App Store. (259)

---

## B1 Impact / Pending / No-AI

**Tight:**
Built Loopa, an iOS music creation app with loop recording, MIDI editing, and audio export — 127 tests, pending App Review. (124)

**Extended:**
Designed and developed Loopa, a full-featured iOS music production app currently in App Review. Features multi-instrument keyboard, multi-track loop recording, piano roll editor, and M4A/MIDI export. Built with SwiftUI and AVAudioEngine. 127 automated tests. Free with no ads — making music creation accessible. (303)

---

## B2 Wholesome / Pending / No-AI

**Tight:**
Created Loopa, a free iOS app to help anyone make music. Multi-track loops, MIDI editor, export. Pending App Store release. (124)

**Extended:**
Built Loopa so anyone can create music — no experience needed. Record loops, layer instruments, edit in a piano roll, and export audio. Free with no ads or subscriptions. Currently pending App Store review. My goal: make creation tools accessible, not gatekept. 127 tests ensure it works. (289)

---

## B3 Technical / Pending / No-AI

**Tight:**
Developed Loopa for iOS: SwiftUI, AVAudioEngine, MIDI/M4A export, 127 automated tests. Pending App Store review. (112)

**Extended:**
Developed Loopa, an iOS music app with SwiftUI, AVAudioEngine, and AVAssetWriter. Features offline M4A rendering, Standard MIDI file export, SoundFont instruments, and beat-based quantization. 127 tests (XCUITest + unit), Fastlane for screenshots, XcodeGen for config. Pending App Store release. (291)

---

## C1 Impact / Published / AI-Assisted

**Tight:**
Built Loopa with AI-assisted development — shipped free iOS music app with 127 tests. Led all product and QA decisions. (119)

**Extended:**
Used Cursor with AI to build Loopa, a free iOS music app on the App Store. Led architecture, reviewed all code, wrote test strategy (127 tests), and owned product decisions. AI accelerated implementation; I drove vision and quality. Multi-track recording, MIDI editor, audio export. (282)

---

## C2 Wholesome / Published / AI-Assisted

**Tight:**
Directed AI tools to build Loopa, a free iOS music app for anyone. Owned product vision, QA, and 127 tests. Now on App Store. (126)

**Extended:**
Partnered with AI tools in Cursor to create Loopa — a free music app for iPhone and iPad. I led product vision, tested every feature, and ensured quality with 127 automated tests. AI handled code generation; I made the decisions that shaped the product. Goal: make music creation accessible, not gatekept. (303)

---

## C3 Technical / Published / AI-Assisted

**Tight:**
Built Loopa using Cursor + AI: SwiftUI, AVAudioEngine, MIDI export. Directed architecture, QA'd with 127 tests. On App Store. (125)

**Extended:**
Developed Loopa using AI-assisted coding in Cursor. Led SwiftUI architecture, AVAudioEngine integration, and MIDI/M4A export implementation. Wrote test strategy and 127 automated tests (XCUITest + unit). Reviewed all AI-generated code, fixed issues, and iterated until shipping. Now on App Store. (289)

---

## D1 Impact / Pending / AI-Assisted

**Tight:**
Built Loopa with AI-assisted development — iOS music app with 127 tests. Led product, architecture, and QA. Pending review. (123)

**Extended:**
Used Cursor with AI assistance to build Loopa, a free iOS music app. Led architecture decisions, reviewed every code change, wrote 127 automated tests, and drove product iteration. AI accelerated implementation; I owned vision and quality. Multi-track recording, MIDI editor, audio export. Pending App Store review. (305)

---

## D2 Wholesome / Pending / AI-Assisted

**Tight:**
Directed AI tools to build Loopa, a free music app for anyone. Led product vision and 127 tests. Pending App Store release. (125)

**Extended:**
Partnered with AI in Cursor to create Loopa, a free music app for iPhone and iPad. I led product decisions, tested every feature, and wrote 127 automated tests. AI handled code; I made the calls. Goal: make music creation accessible. Pending App Store review. (261)

---

## D3 Technical / Pending / AI-Assisted

**Tight:**
Built Loopa using Cursor + AI: SwiftUI, AVAudioEngine, MIDI export, 127 tests. Directed architecture and QA. Pending review. (124)

**Extended:**
Developed Loopa using AI-assisted coding in Cursor. Led SwiftUI architecture, AVAudioEngine integration, MIDI/M4A export, and 127 automated tests (XCUITest + unit). Reviewed all generated code, fixed issues, iterated until ready. Pending App Store review. (252)

---

# Set 2: Holistic Entries (Founder / Self-Discovery / Entrepreneurial)

## E1 Founder / Published / No-AI

**Tight:**
Saw a gap: music apps are too complex or too limited. Built Loopa in a focused sprint — now free on the App Store. (109)

**Extended:**
Noticed most music apps are either overwhelming or toy-like. Built Loopa to fill that gap: a cohesive set of features — loop recording, multi-track mixing, MIDI editing — that just work together. Shipped to the App Store in a focused sprint. Proved I can turn an idea into a real product. (281)

---

## E2 Founder / Published / AI-Assisted

**Tight:**
Identified a market gap, used AI tools to build fast. Shipped Loopa — a cohesive iOS music app — in one focused sprint. (119)

**Extended:**
Spotted a gap: music creation apps are either bloated or too basic. Used Cursor and AI to accelerate development while I led product and architecture. Built a cohesive feature set — loops, tracks, MIDI editor — in one intense sprint. Shipped Loopa free on the App Store. Learned I can turn ideas into products. (299)

---

## E3 Founder / Pending / No-AI

**Tight:**
Saw a gap in music apps — too complex or too limited. Built Loopa in a focused sprint. Pending App Store review. (113)

**Extended:**
Noticed music creation apps are either overwhelming or gimmicky. Built Loopa to fill that gap: a cohesive set of features that work together naturally — loop recording, multi-track mixing, MIDI editing. Shipped in a focused sprint. Proved I can take an idea from zero to product. Pending App Store release. (296)

---

## E4 Founder / Pending / AI-Assisted

**Tight:**
Identified a market gap, used AI tools to move fast. Built Loopa — a cohesive iOS music app — in one focused sprint. (118)

**Extended:**
Spotted a gap: music apps are either bloated pro tools or toy apps. Used AI in Cursor to accelerate while I drove product vision. Built a cohesive feature set — loops, layers, MIDI editor — in one intense sprint. Pending App Store review. Proved I can turn ideas into real products under pressure. (293)

---

## F1 Self-Discovery / Published / No-AI

**Tight:**
Built Loopa to prove I could ship. One focused sprint: idea to App Store. Cohesive music app, free, no ads. (105)

**Extended:**
Wanted to prove I could take an idea from zero to product. Identified a gap in music apps — too complex or too toy-like — and built Loopa in one intense sprint. Loop recording, multi-track mixing, MIDI editor, audio export. Shipped to the App Store. Learned I can persist through ambiguity and ship. (294)

---

## F2 Self-Discovery / Published / AI-Assisted

**Tight:**
Built Loopa to prove I could ship. Used AI to move fast, led product. Idea to App Store in one sprint. (101)

**Extended:**
Wanted to prove I could turn an idea into a real product. Used AI tools in Cursor to accelerate coding while I drove architecture and product decisions. Built Loopa — a cohesive music app — in one intense sprint. Shipped to the App Store. Proved to myself I can persist through complexity and deliver. (297)

---

## F3 Self-Discovery / Pending / No-AI

**Tight:**
Built Loopa to prove I could ship. One focused sprint: gap identified, product built. Pending App Store review. (110)

**Extended:**
Wanted to prove I could take an idea from zero to product. Saw a gap in music apps and built Loopa in one intense sprint — loop recording, multi-track mixing, MIDI editor, audio export. Pending App Store review. Learned I can persist through ambiguity and turn ideas into reality. (282)

---

## F4 Self-Discovery / Pending / AI-Assisted

**Tight:**
Built Loopa to prove I could ship. Used AI to move fast, led all product decisions. One sprint, pending review. (111)

**Extended:**
Wanted to prove I could turn an idea into a real product. Used AI tools to accelerate coding; I led product, architecture, and QA. Built Loopa — a cohesive music app — in one focused sprint. Pending App Store review. Showed myself I can persist through complexity and ship. (273)

---

## G1 Entrepreneurial / Published / No-AI

**Tight:**
Identified a gap, built the solution, shipped it. Loopa: free iOS music app, cohesive features, now on the App Store. (117)

**Extended:**
Saw that music apps either overwhelm beginners or limit creators. Built Loopa to bridge that gap — multi-track loops, MIDI editing, audio export — all working together naturally. Shipped to the App Store in a focused sprint. Free, no ads. Proved I can identify an opportunity and execute on it. (294)

---

## G2 Entrepreneurial / Published / AI-Assisted

**Tight:**
Identified a gap, used AI to build fast, shipped it. Loopa: cohesive iOS music app, free on the App Store. (107)

**Extended:**
Saw that music apps either overwhelm or underwhelm. Used AI tools to accelerate development while leading product decisions. Built Loopa — loop recording, MIDI editing, audio export — with features that work together naturally. Shipped to the App Store. Proved I can spot an opportunity and execute. (292)

---

## G3 Entrepreneurial / Pending / No-AI

**Tight:**
Identified a gap, built the solution. Loopa: free iOS music app with cohesive features. Pending App Store review. (112)

**Extended:**
Saw that music apps either overwhelm beginners or limit creators. Built Loopa to bridge that gap — multi-track loops, MIDI editing, audio export — all working together naturally. Pending App Store review. Proved I can identify an opportunity, build the product, and persist through shipping. (290)

---

## G4 Entrepreneurial / Pending / AI-Assisted

**Tight:**
Identified a gap, used AI to build fast. Loopa: cohesive iOS music app with natural features. Pending review. (109)

**Extended:**
Saw that music apps either overwhelm or underwhelm. Used AI tools to accelerate while leading product and architecture. Built Loopa with features that work together naturally — loops, tracks, MIDI editor. Pending App Store review. Showed I can spot an opportunity and ship under pressure. (286)

---

# Character Count Summary

## Set 1: Core Entries

| Entry | Tight | Extended |
|-------|-------|----------|
| A1 Impact/Published/No-AI | 127 | 282 |
| A2 Wholesome/Published/No-AI | 124 | 297 |
| A3 Technical/Published/No-AI | 120 | 259 |
| B1 Impact/Pending/No-AI | 124 | 303 |
| B2 Wholesome/Pending/No-AI | 124 | 289 |
| B3 Technical/Pending/No-AI | 112 | 291 |
| C1 Impact/Published/AI | 119 | 282 |
| C2 Wholesome/Published/AI | 126 | 303 |
| C3 Technical/Published/AI | 125 | 289 |
| D1 Impact/Pending/AI | 123 | 305 |
| D2 Wholesome/Pending/AI | 125 | 261 |
| D3 Technical/Pending/AI | 124 | 252 |

## Set 2: Holistic Entries

| Entry | Tight | Extended |
|-------|-------|----------|
| E1 Founder/Published/No-AI | 109 | 281 |
| E2 Founder/Published/AI | 119 | 299 |
| E3 Founder/Pending/No-AI | 113 | 296 |
| E4 Founder/Pending/AI | 118 | 293 |
| F1 Self-Discovery/Published/No-AI | 105 | 294 |
| F2 Self-Discovery/Published/AI | 101 | 297 |
| F3 Self-Discovery/Pending/No-AI | 110 | 282 |
| F4 Self-Discovery/Pending/AI | 111 | 273 |
| G1 Entrepreneurial/Published/No-AI | 117 | 294 |
| G2 Entrepreneurial/Published/AI | 107 | 292 |
| G3 Entrepreneurial/Pending/No-AI | 112 | 290 |
| G4 Entrepreneurial/Pending/AI | 109 | 286 |

