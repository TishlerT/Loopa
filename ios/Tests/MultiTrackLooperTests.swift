import XCTest
import Combine
@testable import Loopa

final class MultiTrackLooperTests: XCTestCase {
	
	var looper: MultiTrackLooper!
	
	override func setUp() {
		super.setUp()
		looper = MultiTrackLooper()
	}
	
	override func tearDown() {
		looper.stopPlayback()
		looper = nil
		super.tearDown()
	}
	
	// MARK: - Initial State
	
	func testInitialState() {
		XCTAssertFalse(looper.isRecording)
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
		XCTAssertTrue(looper.tracks.isEmpty)
		XCTAssertEqual(looper.barCount, .four)
	}
	
	// MARK: - Bar Count
	
	func testSetBarCount() {
		looper.setBarCount(.eight)
		XCTAssertEqual(looper.barCount, .eight)
		
		looper.setBarCount(.sixteen)
		XCTAssertEqual(looper.barCount, .sixteen)
	}
	
	func testLoopLengthCalculation() {
		looper.bpm = 120
		looper.setBarCount(.four)
		
		// 4 bars * 4 beats/bar = 16 beats
		// At 120 BPM, 1 beat = 0.5 seconds
		// 16 beats * 0.5 = 8 seconds
		XCTAssertEqual(looper.loopLength, 8.0, accuracy: 0.01)
		
		looper.setBarCount(.eight)
		XCTAssertEqual(looper.loopLength, 16.0, accuracy: 0.01)
	}
	
	func testLoopLengthWithDifferentBPM() {
		looper.setBarCount(.four)
		
		looper.bpm = 60
		// 16 beats * 1.0 second/beat = 16 seconds
		XCTAssertEqual(looper.loopLength, 16.0, accuracy: 0.01)
		
		looper.bpm = 180
		// 16 beats * 0.333 second/beat ≈ 5.33 seconds
		XCTAssertEqual(looper.loopLength, 16.0 / 3.0, accuracy: 0.01)
	}
	
	// MARK: - Recording
	
	func testStartRecording() {
		looper.startRecording(instrument: .piano)
		
		XCTAssertTrue(looper.isRecording)
		XCTAssertTrue(looper.isPlaying, "Recording should auto-start playback")
	}
	
	func testStopRecordingCreatesTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		looper.stopRecording()
		
		XCTAssertFalse(looper.isRecording)
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Piano")
	}
	
	func testEmptyRecordingDoesNotCreateTrack() {
		looper.startRecording(instrument: .piano)
		looper.stopRecording()
		
		XCTAssertTrue(looper.tracks.isEmpty, "Empty recording should not create a track")
	}
	
	// MARK: - Multi-Track
	
	func testMultipleTracks() {
		// Record first track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Record second track
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 2)
		XCTAssertEqual(looper.tracks[0].instrumentName, "Piano")
		XCTAssertEqual(looper.tracks[1].instrumentName, "Drums")
	}
	
	// MARK: - Track Management
	
	func testUndoLastTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 2)
		
		looper.undoLastTrack()
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Piano")
	}
	
	func testClearAllTracks() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.clearAllTracks()
		
		XCTAssertTrue(looper.tracks.isEmpty)
		XCTAssertFalse(looper.isPlaying)
	}
	
	func testDeleteSpecificTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		let pianoTrack = looper.tracks[0]
		looper.deleteTrack(pianoTrack)
		
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Drums")
	}
	
	// MARK: - Mute
	
	func testToggleMute() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		var track = looper.tracks[0]
		XCTAssertFalse(track.isMuted)
		
		looper.toggleMute(track)
		track = looper.tracks[0]
		XCTAssertTrue(track.isMuted)
		
		looper.toggleMute(track)
		track = looper.tracks[0]
		XCTAssertFalse(track.isMuted)
	}
	
	// MARK: - Playback
	
	func testStartPlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		looper.stopPlayback()
		
		looper.startPlayback()
		XCTAssertTrue(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testStopPlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.stopPlayback()
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isRecording)
		XCTAssertFalse(looper.isPaused)
	}
	
	// MARK: - Pause/Resume
	
	func testPausePlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Should be playing after recording stops
		XCTAssertTrue(looper.isPlaying)
		
		// Pause
		looper.pausePlayback()
		XCTAssertFalse(looper.isPlaying)
		XCTAssertTrue(looper.isPaused)
	}
	
	func testResumePlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Pause
		looper.pausePlayback()
		XCTAssertTrue(looper.isPaused)
		
		// Resume
		looper.resumePlayback()
		XCTAssertTrue(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testPauseDoesNothingWhenNotPlaying() {
		// Not playing, not paused
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
		
		looper.pausePlayback()
		
		// Should still not be paused (nothing to pause)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testResumeStartsPlaybackWhenNotPaused() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		looper.stopPlayback()
		
		// Not paused, just stopped
		XCTAssertFalse(looper.isPaused)
		XCTAssertFalse(looper.isPlaying)
		
		// Resume should start playback from beginning
		looper.resumePlayback()
		XCTAssertTrue(looper.isPlaying)
	}
	
	func testStopClearsPausedState() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Pause first
		looper.pausePlayback()
		XCTAssertTrue(looper.isPaused)
		
		// Stop should clear paused state
		looper.stopPlayback()
		XCTAssertFalse(looper.isPaused)
		XCTAssertFalse(looper.isPlaying)
	}
	
	// MARK: - Multi-Bar Recording After Shorter Track
	
	func testRecordingLongerTrackAfterShorterTrack() {
		// This test verifies the fix for the bug where recording a 4-bar track
		// after a 1-bar track caused notes to get "crammed" into the first bar.
		// The issue was that addLiveEvent used global loopLength (based on max track length)
		// instead of recordingLoopLength (based on barCount setting).
		
		looper.bpm = 120  // 0.5 seconds per beat, 2 seconds per bar
		
		// Step 1: Record a 1-bar drum track
		looper.setBarCount(.one)
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 36, velocity: 0, isNoteOn: false)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks[0].recordedLengthBeats, 4.0, "1 bar = 4 beats")
		
		// Step 2: Record a 4-bar piano track with notes at various positions
		// At 120 BPM, event times: beat 1 = 0.5s, beat 5 = 2.5s, beat 9 = 4.5s, beat 13 = 6.5s
		looper.setBarCount(.four)
		looper.startRecording(instrument: .piano)
		
		// Simulate notes at beats 1, 5, 9, 13 (one per bar)
		let secondsPerBeat = 60.0 / looper.bpm
		
		// Note at beat 1 (bar 1)
		Thread.sleep(forTimeInterval: 0.1)  // Small delay
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		
		// Note at beat 5 (bar 2) - should NOT wrap to beat 1
		Thread.sleep(forTimeInterval: secondsPerBeat * 4)  // 4 beats later
		looper.addLiveEvent(note: 62, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 62, velocity: 0, isNoteOn: false)
		
		// Note at beat 9 (bar 3) - should NOT wrap to beat 1
		Thread.sleep(forTimeInterval: secondsPerBeat * 4)  // 4 beats later
		looper.addLiveEvent(note: 64, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 64, velocity: 0, isNoteOn: false)
		
		looper.stopRecording()
		
		// Verify we have 2 tracks now
		XCTAssertEqual(looper.tracks.count, 2, "Should have 2 tracks")
		
		// Verify the piano track has the correct recorded length
		let pianoTrack = looper.tracks[1]
		XCTAssertEqual(pianoTrack.recordedLengthBeats, 16.0, "4 bars = 16 beats")
		XCTAssertEqual(pianoTrack.notes.count, 3, "Should have 3 notes")
		
		// Verify notes are spread across bars (not all crammed into first bar)
		// Note at beat ~0 (bar 1)
		let note1 = pianoTrack.notes.first { $0.pitch == 60 }
		XCTAssertNotNil(note1, "Should have note at pitch 60")
		XCTAssertLessThan(note1!.startBeat, 4.0, "First note should be in bar 1 (beats 0-4)")
		
		// Note at beat ~4-8 (bar 2) - the critical test!
		let note2 = pianoTrack.notes.first { $0.pitch == 62 }
		XCTAssertNotNil(note2, "Should have note at pitch 62")
		XCTAssertGreaterThanOrEqual(note2!.startBeat, 4.0, "Second note should be in bar 2+ (beat 4+)")
		XCTAssertLessThan(note2!.startBeat, 8.0, "Second note should be in bar 2 (beats 4-8)")
		
		// Note at beat ~8-12 (bar 3) - another critical test!
		let note3 = pianoTrack.notes.first { $0.pitch == 64 }
		XCTAssertNotNil(note3, "Should have note at pitch 64")
		XCTAssertGreaterThanOrEqual(note3!.startBeat, 8.0, "Third note should be in bar 3+ (beat 8+)")
		XCTAssertLessThan(note3!.startBeat, 12.0, "Third note should be in bar 3 (beats 8-12)")
	}
	
	func testRecordingFourBarsAfterTwoBars() {
		// Variation: 4 bars after 2 bars (notes should not wrap to first 2 bars)
		looper.bpm = 120
		
		// Record a 2-bar track first
		looper.setBarCount(.two)
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks[0].recordedLengthBeats, 8.0, "2 bars = 8 beats")
		
		// Now record a 4-bar track
		looper.setBarCount(.four)
		looper.startRecording(instrument: .piano)
		
		let secondsPerBeat = 60.0 / looper.bpm
		
		// Note in bar 3 (beat 9)
		Thread.sleep(forTimeInterval: secondsPerBeat * 9)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		
		looper.stopRecording()
		
		let pianoTrack = looper.tracks[1]
		XCTAssertEqual(pianoTrack.notes.count, 1)
		
		// The note should be around beat 9, NOT wrapped to beat 1 (9 mod 8 = 1)
		let note = pianoTrack.notes[0]
		XCTAssertGreaterThanOrEqual(note.startBeat, 8.0, "Note should be in bar 3+ (beat 8+)")
	}
}

// MARK: - Instrument Tests

final class InstrumentTests: XCTestCase {
	
	func testAllInstrumentsHaveIcons() {
		for instrument in Instrument.allCases {
			XCTAssertFalse(instrument.icon.isEmpty, "\(instrument.rawValue) should have an icon")
		}
	}
	
	func testDrumKitIdentification() {
		XCTAssertTrue(Instrument.drums.isDrumKit)
		XCTAssertFalse(Instrument.piano.isDrumKit)
		XCTAssertFalse(Instrument.bass.isDrumKit)
	}
	
	func testProgramNumbers() {
		XCTAssertEqual(Instrument.piano.programNumber, 0)
		XCTAssertEqual(Instrument.electricPiano.programNumber, 4)
		XCTAssertEqual(Instrument.bass.programNumber, 32)
	}
}

// MARK: - Bar Count Tests

final class BarCountTests: XCTestCase {
	
	func testAllBarCounts() {
		let expectedCounts = [1, 2, 4, 8, 16]
		let actualCounts = BarCount.allCases.map { $0.rawValue }
		XCTAssertEqual(actualCounts, expectedCounts)
	}
	
	func testDisplayNames() {
		XCTAssertEqual(BarCount.one.displayName, "1 bar")
		XCTAssertEqual(BarCount.four.displayName, "4 bars")
		XCTAssertEqual(BarCount.sixteen.displayName, "16 bars")
	}
}



// MARK: - Authoritative musical revision and atomic edits

final class MusicalRevisionTests: XCTestCase {
    private var looper: MultiTrackLooper!

    override func setUp() {
        super.setUp()
        looper = MultiTrackLooper()
    }

    override func tearDown() {
        looper.stopPlayback()
        looper = nil
        super.tearDown()
    }

    private func fixture() -> Track {
        Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
              notes: [MidiNote(pitch: 60, startBeat: 0.3, durationBeats: 0.3)], volume: 0.5)
    }

    private func assertAdvanced(_ token: MusicalToken, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(looper.musicalToken.sessionID, token.sessionID, file: file, line: line)
        XCTAssertEqual(looper.musicalToken.revision, token.revision + 1, file: file, line: line)
    }

    func testAllExistingTrackMutationRoutesAdvanceOnce() throws {
        let t = fixture()
        looper.loadTracks([t])
        let actions: [() -> Void] = [
            { self.looper.toggleMute(t) }, { self.looper.toggleSolo(t) },
            { self.looper.toggleLoop(t) }, { self.looper.setTrackSolo(t.id, solo: false) },
            { self.looper.setTrackVolume(t.id, volume: 0.7) },
            { self.looper.setTrackInstrument(t.id, instrument: .bass) },
            { self.looper.quantizeTrack(t.id, division: .quarter) },
            { var changed = self.looper.tracks[0]; changed.notes.removeAll(); self.looper.updateTrack(changed) },
            { self.looper.addAudioTrack(Track(audioFileName: "take.caf")) },
            { self.looper.undoLastTrack() }, { self.looper.deleteTrack(t) }
        ]
        for action in actions {
            let before = looper.musicalToken
            action()
            assertAdvanced(before)
        }
    }

    func testNoOpAndMissingTrackRoutesDoNotAdvance() {
        let t = fixture()
        looper.loadTracks([t])
        let before = looper.musicalToken
        looper.setTrackSolo(t.id, solo: false)
        looper.setTrackVolume(t.id, volume: 0.5)
        looper.setTrackInstrument(t.id, instrument: .piano)
        looper.updateTrack(t)
        looper.deleteTrack(fixture())
        looper.setTrackVolume(UUID(), volume: 0.8)
        looper.setTrackSolo(UUID(), solo: true)
        looper.quantizeTrack(UUID(), division: .quarter)
        looper.bpm = looper.bpm
        looper.barCount = looper.barCount
        looper.setBarCount(looper.barCount)
        XCTAssertEqual(looper.musicalToken, before)
        looper.deleteTrack(t)
        let empty = looper.musicalToken
        looper.undoLastTrack()
        XCTAssertEqual(looper.musicalToken, empty)
    }

    func testBPMAndDirectOrMethodBarChangesAdvanceOnce() {
        var token = looper.musicalToken
        looper.bpm = 120
        assertAdvanced(token)
        token = looper.musicalToken
        looper.barCount = .two
        assertAdvanced(token)
        XCTAssertEqual(looper.loopLength, 4, accuracy: 0.001)
        token = looper.musicalToken
        looper.setBarCount(.one)
        assertAdvanced(token)
        XCTAssertEqual(looper.loopLength, 2, accuracy: 0.001)
    }

    func testInvalidBPMAndGainDoNotChangeStateOrToken() {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        for bpm in [Double.nan, .infinity, 0, -1] { looper.bpm = bpm }
        for volume in [Float.nan, .infinity, -.infinity] { looper.setTrackVolume(t.id, volume: volume) }
        XCTAssertEqual(looper.bpm, 100)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.musicalToken, token)
    }

    func testSameContentLoadAndEmptyClearReplaceSessionIdentity() {
        let t = fixture()
        looper.loadTracks([t])
        let first = looper.musicalToken
        looper.loadTracks([t])
        XCTAssertNotEqual(looper.musicalToken.sessionID, first.sessionID)
        looper.clearAllTracks()
        let cleared = looper.musicalToken
        looper.clearAllTracks()
        XCTAssertNotEqual(looper.musicalToken.sessionID, cleared.sessionID)
    }

    func testRecordingStartInvalidatesAndCompletionAdvancesOnce() {
        let initial = looper.musicalToken
        looper.startRecording(instrument: .piano)
        assertAdvanced(initial)
        let started = looper.musicalToken
        looper.startRecording(instrument: .piano)
        looper.addLiveEvent(note: 60, velocity: 90, isNoteOn: true)
        looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
        XCTAssertEqual(looper.musicalToken, started)
        looper.stopRecording()
        assertAdvanced(started)
        XCTAssertEqual(looper.tracks.count, 1)
        let done = looper.musicalToken
        looper.stopRecording()
        XCTAssertEqual(looper.musicalToken, done)
    }

    func testEmptyRecordingStillInvalidatesOldRequestButDoesNotCreateTrack() {
        let before = looper.musicalToken
        looper.startRecording(instrument: .piano)
        let started = looper.musicalToken
        XCTAssertNotEqual(started, before)
        looper.stopRecording()
        XCTAssertEqual(looper.musicalToken, started)
        XCTAssertTrue(looper.tracks.isEmpty)
    }

    func testPunchInCompletionIsOneMutationAndPreservesExistingTrack() {
        let t = fixture()
        looper.loadTracks([t])
        looper.startRecording(instrument: .piano, fromPosition: 1)
        let started = looper.musicalToken
        looper.addLiveEvent(note: 64, velocity: 90, isNoteOn: true)
        looper.addLiveEvent(note: 64, velocity: 0, isNoteOn: false)
        looper.stopRecording()
        assertAdvanced(started)
        XCTAssertEqual(looper.tracks.count, 1)
        XCTAssertEqual(looper.tracks[0].id, t.id)
        XCTAssertTrue(looper.tracks[0].notes.contains { $0.id == t.notes[0].id })
        XCTAssertTrue(looper.tracks[0].notes.contains { $0.pitch == 64 })
    }

    func testTransportAndActualTicksDoNotAdvanceToken() {
        looper.loadTracks([fixture()])
        let token = looper.musicalToken
        let tick = expectation(description: "background transport tick")
        let subscription = looper.$currentPosition.first { $0 > 0 }.sink { _ in tick.fulfill() }
        looper.startPlayback()
        wait(for: [tick], timeout: 2)
        looper.pausePlayback()
        looper.seekTo(position: 1)
        looper.resumePlayback()
        looper.stopPlayback()
        XCTAssertEqual(looper.musicalToken, token)
        withExtendedLifetime(subscription) {}
    }

    func testCommitAndInverseAdvanceInsteadOfRewinding() throws {
        let t = fixture()
        looper.loadTracks([t])
        let snapshot = try looper.musicSnapshot()
        let commit = try looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: snapshot.token)
        assertAdvanced(snapshot.token)
        XCTAssertEqual(commit.token, looper.musicalToken)
        XCTAssertEqual(looper.tracks[0].volume, 0.8)
        let undone = try looper.applyMusicInverse(commit.inverse, expectedToken: commit.token)
        assertAdvanced(commit.token)
        XCTAssertEqual(undone, looper.musicalToken)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.tracks[0].notes, t.notes)
    }

    func testLaterUserChangeAndSameContentSessionReplacementRejectStaleCommit() throws {
        let t = fixture()
        looper.loadTracks([t])
        let old = looper.musicalToken
        looper.toggleMute(t)
        let newer = looper.musicalToken
        XCTAssertThrowsError(try looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: old)) {
            XCTAssertEqual($0 as? MusicalCommitError, .stale)
        }
        XCTAssertEqual(looper.musicalToken, newer)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        looper.loadTracks(looper.tracks)
        XCTAssertThrowsError(try looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: newer))
    }

    func testInvalidCompositeLeavesTracksAndTokenUntouched() {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        let edits: [MusicEdit] = [.gain(trackID: t.id, before: 0.5, after: 0.8),
                                  .gain(trackID: t.id, before: 0.5, after: 0.9)]
        XCTAssertThrowsError(try looper.applyMusicEdits(edits, expectedToken: token)) {
            XCTAssertEqual($0 as? MusicalCommitError, .invalidEdit(.staleBefore))
        }
        XCTAssertEqual(looper.musicalToken, token)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.tracks[0].notes, t.notes)
    }

    func testPlayingAndRecordingRejectButPausedAllowsCommit() throws {
        let t = fixture()
        looper.loadTracks([t])
        let edits: [MusicEdit] = [.gain(trackID: t.id, before: 0.5, after: 0.8)]
        looper.startPlayback()
        var token = looper.musicalToken
        XCTAssertThrowsError(try looper.applyMusicEdits(edits, expectedToken: token)) {
            XCTAssertEqual($0 as? MusicalCommitError, .busy)
        }
        XCTAssertEqual(looper.musicalToken, token)
        looper.startRecording(instrument: .piano)
        looper.pausePlayback() // Recording is independently busy even when playback is paused.
        token = looper.musicalToken
        XCTAssertThrowsError(try looper.applyMusicEdits(edits, expectedToken: token)) {
            XCTAssertEqual($0 as? MusicalCommitError, .busy)
        }
        XCTAssertEqual(looper.musicalToken, token)
        looper.stopRecording()
        XCTAssertNoThrow(try looper.applyMusicEdits(edits, expectedToken: token))
    }

    func testInverseRejectsLaterMutationAndPlayback() throws {
        let t = fixture()
        looper.loadTracks([t])
        let receipt = try looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: looper.musicalToken)
        looper.startPlayback()
        XCTAssertThrowsError(try looper.applyMusicInverse(receipt.inverse, expectedToken: receipt.token))
        looper.stopPlayback()
        looper.toggleMute(t)
        let newer = looper.musicalToken
        XCTAssertThrowsError(try looper.applyMusicInverse(receipt.inverse, expectedToken: receipt.token)) {
            XCTAssertEqual($0 as? MusicalCommitError, .stale)
        }
        XCTAssertEqual(looper.musicalToken, newer)
        XCTAssertEqual(looper.tracks[0].volume, 0.8)
    }

    func testLegacyNoteWritebackPreservesNewerMetadata() {
        let stale = fixture()
        looper.loadTracks([stale])
        looper.setTrackVolume(stale.id, volume: 0.9)
        looper.toggleMute(stale)
        looper.setTrackInstrument(stale.id, instrument: .bass)
        var edited = stale
        edited.notes.removeAll()
        looper.updateTrack(edited)
        XCTAssertTrue(looper.tracks[0].notes.isEmpty)
        XCTAssertEqual(looper.tracks[0].volume, 0.9)
        XCTAssertTrue(looper.tracks[0].isMuted)
        XCTAssertEqual(looper.tracks[0].instrumentName, Instrument.bass.rawValue)
    }

    func testSynchronousPublicationCannotReenterCommitOrReadMixedSnapshot() throws {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        var calls = 0
        let subscription = looper.$tracks.dropFirst().sink { _ in
            calls += 1
            do {
                _ = try self.looper.musicSnapshot()
                XCTFail("Snapshot unexpectedly succeeded during synchronous publication")
            } catch {
                XCTAssertEqual(error as? MusicalCommitError, .busy)
            }
            do {
                _ = try self.looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.9)], expectedToken: token)
                XCTFail("Commit unexpectedly succeeded during synchronous publication")
            } catch {
                XCTAssertEqual(error as? MusicalCommitError, .busy)
            }
        }
        looper.setTrackVolume(t.id, volume: 0.7)
        XCTAssertEqual(calls, 1)
        assertAdvanced(token)
        let snapshot = try looper.musicSnapshot()
        XCTAssertEqual(snapshot.token, looper.musicalToken)
        XCTAssertEqual(snapshot.tracks[0].volume, 0.7)
        withExtendedLifetime(subscription) {}
    }

    func testConcurrentCommitsWithSameTokenHaveExactlyOneWinner() {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        let resultLock = NSLock()
        var successes = 0
        var errors: [MusicalCommitError] = []
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do {
                _ = try self.looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: token)
                resultLock.lock(); successes += 1; resultLock.unlock()
            } catch {
                resultLock.lock(); errors.append(error as! MusicalCommitError); resultLock.unlock()
            }
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(errors, Array(repeating: .stale, count: 11))
        assertAdvanced(token)
    }

    func testSnapshotIncludesConsistentTimingAndImmutableTracks() throws {
        let t = fixture()
        looper.loadTracks([t])
        looper.bpm = 120
        looper.barCount = .two
        let snapshot = try looper.musicSnapshot()
        XCTAssertEqual(snapshot.token, looper.musicalToken)
        XCTAssertEqual(snapshot.bpm, 120)
        XCTAssertEqual(snapshot.barCount, .two)
        looper.setTrackVolume(t.id, volume: 0.8)
        XCTAssertEqual(snapshot.tracks[0].volume, 0.5)
        XCTAssertNotEqual(snapshot.token, looper.musicalToken)
    }

    func testBPMPublicationRejectsReentrantCommitAndSnapshot() {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        var calls = 0
        let subscription = looper.$bpm.dropFirst().sink { _ in
            calls += 1
            do {
                _ = try self.looper.musicSnapshot()
                XCTFail("Snapshot unexpectedly succeeded during synchronous publication")
            } catch {
                XCTAssertEqual(error as? MusicalCommitError, .busy)
            }
            do {
                _ = try self.looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: token)
                XCTFail("Commit unexpectedly succeeded during synchronous publication")
            } catch {
                XCTAssertEqual(error as? MusicalCommitError, .busy)
            }
        }
        looper.bpm = 120
        assertAdvanced(token)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        withExtendedLifetime(subscription) {}
    }

    func testTransportPublicationCannotSneakInACommit() {
        let t = fixture()
        looper.loadTracks([t])
        let token = looper.musicalToken
        var calls = 0
        let subscription = looper.$isPlaying.dropFirst().filter { $0 }.sink { _ in
            calls += 1
            do {
                _ = try self.looper.applyMusicEdits([.gain(trackID: t.id, before: 0.5, after: 0.8)], expectedToken: token)
                XCTFail("Commit unexpectedly succeeded during synchronous publication")
            } catch {
                XCTAssertEqual(error as? MusicalCommitError, .busy)
            }
        }
        looper.startPlayback()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.musicalToken, token)
        withExtendedLifetime(subscription) {}
    }

    func testMultiTrackBatchPublishesAndAdvancesExactlyOnce() throws {
        let a = fixture(), b = fixture()
        looper.loadTracks([a, b])
        let token = looper.musicalToken
        var publications = 0
        let subscription = looper.$tracks.dropFirst().sink { _ in publications += 1 }
        let receipt = try looper.applyMusicEdits([.gain(trackID: a.id, before: 0.5, after: 0.7),
                                                 .gain(trackID: b.id, before: 0.5, after: 0.8)], expectedToken: token)
        assertAdvanced(token)
        XCTAssertEqual(publications, 1)
        _ = try looper.applyMusicInverse(receipt.inverse, expectedToken: receipt.token)
        assertAdvanced(receipt.token)
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(looper.tracks.map(\.volume), [0.5, 0.5])
        withExtendedLifetime(subscription) {}
    }

    func testLoadStopsPlaybackAndPublishesEvenSameContent() {
        let t = fixture()
        looper.loadTracks([t])
        var publications = 0
        let subscription = looper.$tracks.dropFirst().sink { _ in publications += 1 }
        looper.startPlayback()
        let previous = looper.musicalToken
        looper.loadTracks([t])
        XCTAssertFalse(looper.isPlaying)
        XCTAssertFalse(looper.isPaused)
        XCTAssertEqual(publications, 1)
        XCTAssertNotEqual(looper.musicalToken.sessionID, previous.sessionID)
        withExtendedLifetime(subscription) {}
    }

    func testExistingManualControlsRemainAvailableWhilePlaying() {
        let t = fixture()
        looper.loadTracks([t])
        looper.startPlayback()
        var token = looper.musicalToken
        looper.setTrackVolume(t.id, volume: 0.8)
        assertAdvanced(token)
        token = looper.musicalToken
        looper.toggleMute(t)
        assertAdvanced(token)
        XCTAssertTrue(looper.isPlaying)
        XCTAssertEqual(looper.tracks[0].volume, 0.8)
        XCTAssertTrue(looper.tracks[0].isMuted)
    }


    func testRecursiveTimingSettersCannotHideAnActualChange() {
        let token = looper.musicalToken
        var changedBPM = false
        let bpmSubscription = looper.$bpm.dropFirst().sink { _ in
            if !changedBPM { changedBPM = true; self.looper.bpm = 120 }
        }
        looper.bpm = 100 // Nested publication changes 100 -> 120 -> 100.
        XCTAssertEqual(looper.bpm, 100)
        XCTAssertEqual(looper.musicalToken.revision, token.revision + 2)
        var changedBars = false
        let barsToken = looper.musicalToken
        let barSubscription = looper.$barCount.dropFirst().sink { _ in
            if !changedBars { changedBars = true; self.looper.barCount = .one }
        }
        looper.barCount = .four
        XCTAssertEqual(looper.barCount, .four)
        XCTAssertEqual(looper.musicalToken.revision, barsToken.revision + 2)
        withExtendedLifetime((bpmSubscription, barSubscription)) {}
    }

}
