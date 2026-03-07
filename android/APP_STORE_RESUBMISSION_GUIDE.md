# Loopa App Store Resubmission Guide

**Purpose**: Fix Guideline 2.3.7 (price language) and 4.3(a) (spam/uniqueness) rejections.

**Time Required**: 30-45 minutes if you follow this guide step-by-step.

---

## BEFORE YOU START

You will need:
- [ ] Access to [App Store Connect](https://appstoreconnect.apple.com)
- [ ] Your Apple ID credentials
- [ ] This document open for copy/paste

---

## STEP 1: Log Into App Store Connect

1. Open Safari and go to: **https://appstoreconnect.apple.com**
2. Sign in with your Apple Developer account
3. Click **My Apps**
4. Click on **Loopa**

---

## STEP 2: Fix App Name (Guideline 2.3.7)

**Where**: Left sidebar → **App Information** → scroll to **Name**

### What to change:

If your current name contains "Free", "FREE", "$0", or any price language, change it to one of these:

| Option | App Name |
|--------|----------|
| **Option A (Recommended)** | `Loopa` |
| Option B | `Loopa - Loop Music Studio` |
| Option C | `Loopa - Beat Maker` |

### Copy this (Option A):
```
Loopa
```

**Action**: Paste into the Name field, then click **Save** (top right).

---

## STEP 3: Fix Subtitle

**Where**: Same page (App Information) → scroll to **Subtitle**

### Recommended subtitles (pick ONE, all under 30 chars):

| Option | Subtitle | Characters |
|--------|----------|------------|
| **Option 1 (Recommended)** | `Drum Sequencer + Piano Roll` | 27 |
| Option 2 | `Layer Beats & Melodies` | 23 |
| Option 3 | `Multi-Track Loop Studio` | 23 |

### Copy this (Option 1):
```
Drum Sequencer + Piano Roll
```

**Action**: Paste into the Subtitle field, then click **Save**.

---

## STEP 4: Fix Keywords

**Where**: Same page (App Information) → scroll to **Keywords**

### Remove these words if present:
- free
- FREE  
- $0
- best
- #1
- top
- GarageBand (or any competitor name)

### Copy this keyword string (98 characters):
```
looper,drum machine,piano roll,beat maker,vocal,multi-track,sequencer,quantize,mixer,loop station
```

**Note**: Keywords are comma-separated, no spaces after commas, max 100 characters total. The string above is exactly 98 characters.

**Action**: Replace your entire keywords field with the text above, then click **Save**.

---

## STEP 5: Fix Promotional Text

**Where**: Click **App Store** tab (top) → Select your version → scroll to **Promotional Text**

### Copy this:
```
Record drums, melodies, and vocals — then mix them all together. Your portable music studio with tap-to-place sequencing.
```

**Note**: Promotional text can be changed anytime without a new app version.

**Action**: Paste into Promotional Text field.

---

## STEP 6: Fix Description

**Where**: Same page → scroll to **Description**

### The first 3 sentences are CRITICAL. Replace your opening with this:

```
Loopa is a multi-track music creation app with a tap-to-place drum sequencer, piano roll editor, and vocal recording. Layer up to 8 tracks — drums, bass, synths, and vocals — with real-time BPM sync and 16th-note quantization. Every note you record can be edited, moved, or resized in the visual grid editor.

FEATURES:

• TAP-TO-PLACE DRUM SEQUENCER
Program kick, snare, and hi-hat patterns by tapping cells in the drum grid. See your rhythm visually and edit any note after recording.

• PIANO ROLL EDITOR  
Write melodies and basslines with drag-to-move, double-tap-to-resize note editing. Supports multiple instruments: leads, pads, plucks, and more.

• MULTI-TRACK MIXER
Mix all your tracks with individual volume faders. Solo or mute any track with one tap. See note counts per track.

• VOCAL RECORDING
Record vocals directly over your instrumental loops with real-time waveform visualization.

• SMART QUANTIZATION
Keep every note perfectly on beat with adjustable quantization from 1/4 to 1/16 notes.

• LOOP CONTROL
Set BPM from 60-200 and loop length from 1-8 bars. Metronome with count-in helps you start on beat.

• SESSION MANAGEMENT
Save and load your sessions. Auto-save keeps your work safe.

Built from scratch using SwiftUI and AVAudioEngine. No templates. No ads. Just music.
```

**Action**: Replace your entire description with the text above.

---

## STEP 7: Update Screenshot Captions

**Where**: Same page → scroll to **Screenshots** section

For each screenshot, add a caption that describes the SPECIFIC feature shown:

| Screenshot | Recommended Caption |
|------------|---------------------|
| Main Looper View | `Tap Record to start your loop — notes auto-quantize to the beat` |
| Drum Grid | `Tap cells to build drum patterns — kick, snare, hi-hat rows` |
| Piano Roll | `Piano roll editor: drag notes to move, double-tap to resize` |
| Tracks/Mixer | `Mix your layers with per-track volume, solo, and mute` |
| Vocal Recording | `Record vocals over your instrumental loops` |
| Export/Settings | `Save sessions and export your music` |

### Caption Rules:
- Start with an ACTION verb (Tap, Drag, Layer, Record)
- Be SPECIFIC about what the screenshot shows
- NEVER use: "Free", "Easy", "Best", "Pro-quality"

**Action**: Click each screenshot, add caption, save.

---

## STEP 8: Add App Review Notes (CRITICAL)

**Where**: Same page → scroll down to **App Review Information** → **Notes**

This is your direct message to the reviewer. It's the most important field for fixing the 4.3(a) rejection.

### Copy and paste this ENTIRE message:

```
Thank you for reviewing Loopa.

We have addressed both guidelines cited in our previous rejection:

═══════════════════════════════════════════════════════
GUIDELINE 2.3.7 - ACCURATE METADATA
═══════════════════════════════════════════════════════

We have removed all price-related language ("Free", etc.) from:
• App name
• Subtitle
• Keywords
• Promotional text
• Description
• Screenshot captions

═══════════════════════════════════════════════════════
GUIDELINE 4.3(a) - DESIGN ORIGINALITY
═══════════════════════════════════════════════════════

Loopa is an original music creation app, not a template or clone.

───────────────────────────────────────────────────────
WHO IS THIS APP FOR?
───────────────────────────────────────────────────────

Loopa targets beginner-to-intermediate musicians who want to create loop-based music on mobile without the complexity of full DAWs like GarageBand.

The ideal user is someone who:
• Wants to sketch musical ideas quickly (bedroom producers, hobbyists)
• Finds traditional DAWs overwhelming or intimidating
• Prefers visual, touch-first interfaces over menus and settings
• Wants drums, melodies, bass, and vocals in ONE simple app

───────────────────────────────────────────────────────
WHAT UNIQUE WORKFLOW DOES LOOPA HAVE?
───────────────────────────────────────────────────────

Loopa's workflow is: PLAY → RECORD → SEE → EDIT → LAYER → MIX

1. PLAY: Tap the on-screen keyboard to play any instrument
2. RECORD: Press record — notes are captured in real-time and auto-quantized
3. SEE: Every note you played appears visually in a grid editor
4. EDIT: Tap to add notes, drag to move them, double-tap to resize — no re-recording needed
5. LAYER: Add more tracks (drums, bass, pads, vocals) that loop in sync
6. MIX: Adjust volume, solo, and mute per track in the mixer view

This "record then edit" workflow lets users capture imperfect performances and fix them visually — something simple loop apps cannot do.

───────────────────────────────────────────────────────
WHAT DO COMPETITORS LACK?
───────────────────────────────────────────────────────

We analyzed existing apps and found gaps that Loopa fills:

SIMPLE LOOP APPS (loop pedal style):
✗ No visual note editing — you can only delete and re-record
✗ No piano roll — can't see or move individual notes
✗ No drum sequencer — drums must be played live
Loopa adds: Visual grid editors for both drums AND melodic instruments

DRUM MACHINE APPS:
✗ Drums only — no melodic instruments
✗ No piano roll for basslines or melodies
✗ No vocal recording
Loopa adds: Full keyboard with multiple instruments + vocal recording

COMPLEX DAWS (GarageBand, etc.):
✗ Steep learning curve — dozens of menus, modes, and options
✗ Overwhelming for quick ideas
✗ Not optimized for simple loop-based creation
Loopa adds: One-screen simplicity with loop-first design

PIANO ROLL APPS:
✗ Step entry only — no live recording option
✗ No real-time looping playback
✗ No drums or vocal recording
Loopa adds: Live recording with instant quantization + drum grid + vocals

───────────────────────────────────────────────────────
KEY DIFFERENTIATING FEATURES
───────────────────────────────────────────────────────

1. TAP-TO-PLACE DRUM SEQUENCER (Screenshot 2)
   Program kick, snare, hi-hat by tapping cells in a grid — like a hardware drum machine

2. PIANO ROLL EDITOR (Screenshot 3)
   See every note visually, drag to move, double-tap to resize duration

3. MULTI-TRACK MIXER (Screenshot 5)
   Volume faders + solo + mute per track — typically only in desktop DAWs

4. VOCAL RECORDING (Screenshot 4)
   Record vocals over loops with real-time waveform visualization

5. AUTO-QUANTIZATION
   Notes snap to the beat automatically — keeps beginners sounding tight

───────────────────────────────────────────────────────
TECHNICAL ORIGINALITY
───────────────────────────────────────────────────────

All code was written from scratch:
• Audio engine: AVAudioEngine with custom AudioUnit graph
• MIDI sequencing: Custom quantization and timing system
• UI: 100% SwiftUI — no third-party templates or UI kits

No white-label code, cloned repositories, or purchased templates were used.

───────────────────────────────────────────────────────
HOW TO TEST KEY FEATURES
───────────────────────────────────────────────────────

1. Tap the red Record button to start loop recording
2. Play notes on the keyboard — they auto-quantize to the beat
3. Tap "TRACKS" to see the mixer with all your layers
4. Tap any track row to open its editor
5. In the editor: tap cells to add notes, drag to move them

We welcome any questions and are happy to provide source code access, a video walkthrough, or any additional documentation.

Thank you for your consideration.
```

**Action**: Paste into the Notes field.

---

## STEP 9: Final Review Before Submitting

Go through this checklist:

- [ ] App Name contains NO price language (Free, $0, etc.)
- [ ] Subtitle contains NO price language
- [ ] Keywords contain NO "free" or competitor names
- [ ] Promotional Text contains NO price language
- [ ] Description first 3 sentences are specific and unique
- [ ] Screenshot captions are specific (not "Easy to use!")
- [ ] App Review Notes are filled in with the message above

---

## STEP 10: Submit for Review

1. Scroll to the top of the version page
2. Click **Add for Review** (or **Submit for Review** if already added)
3. Complete the questionnaire:
   - Export Compliance: Usually "No" unless you use custom encryption
   - Content Rights: "Yes, I own or have rights to all content"
   - Advertising Identifier: "No" (unless you have ads)
4. Click **Submit**

---

## WHAT HAPPENS NEXT

- Apple typically reviews apps within 24-48 hours
- You'll get an email when review is complete
- If approved: Your app goes live!
- If rejected again: Read the new feedback carefully and message me

---

## IF YOU NEED A NEW BUILD

**Only do this if Apple requires code changes or you want to bump the version.**

The build number needs to be incremented. Current build is "1" in Info.plist.

To create a new build:
1. I can bump the build number for you
2. Archive and upload using Xcode or Transporter
3. Then submit the new build in App Store Connect

**For metadata-only changes**: No new build needed! Just update the fields above and resubmit.

---

## QUICK REFERENCE: WORDS TO AVOID

| Never Use | Why |
|-----------|-----|
| Free, FREE, $0 | Guideline 2.3.7 violation |
| Best, #1, Top | Requires proof |
| GarageBand, FL Studio | Competitor names |
| Pro, Professional | Unless you have a Pro tier |
| Easy, Simple | Generic, every app says this |
| Just like [X] | Suggests clone |

---

## QUESTIONS?

If anything is unclear, let me know and I'll help you through it step by step.

