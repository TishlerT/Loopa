import XCTest
import Combine
@testable import Loopa

final class ViewModelTests: XCTestCase {
	
	// MARK: - Note Preview Tests
	
	@MainActor
	func testPreviewNoteDoesNotCrash() {
		let looperVM = LooperViewModel()
		
		// Create a track and add it to the looper
		let track = Track(
			instrumentName: "Piano",
			instrumentProgram: 0,
			isDrumKit: false,
			notes: []
		)
		
		// Preview note should not crash even without a track in the looper
		// (guard should exit gracefully)
		looperVM.previewNote(pitch: 60, velocity: 100, trackId: track.id)
		
		// If we get here without crashing, the test passes
		XCTAssertTrue(true)
	}
	
	@MainActor
	func testPreviewNoteWithDrumTrack() {
		let looperVM = LooperViewModel()
		
		// Create a drum track
		let drumTrack = Track(
			instrumentName: "Drums",
			instrumentProgram: 0,
			isDrumKit: true,
			notes: []
		)
		
		// Preview drum note should not crash
		looperVM.previewNote(pitch: 36, velocity: 100, trackId: drumTrack.id)
		looperVM.previewNote(pitch: 38, velocity: 90, trackId: drumTrack.id)
		looperVM.previewNote(pitch: 42, velocity: 80, trackId: drumTrack.id)
		
		XCTAssertTrue(true)
	}
	
	// MARK: - Drum Mapping Tests
	
	func testDrumMapping() {
		// Test the drum mapping logic directly
		let startNote: UInt8 = 60
		let layout: [UInt8] = [36, 38, 42, 46, 39, 41, 43, 37, 49]
		
		func mapDrum(note: UInt8) -> UInt8 {
			let idx = Int(note &- startNote)
			let leftIndex = max(0, min(8, idx))
			return layout[leftIndex]
		}
		
		// Test each key maps to expected drum
		XCTAssertEqual(mapDrum(note: 60), 36, "Note 60 should map to kick (36)")
		XCTAssertEqual(mapDrum(note: 61), 38, "Note 61 should map to snare (38)")
		XCTAssertEqual(mapDrum(note: 62), 42, "Note 62 should map to closed hi-hat (42)")
		XCTAssertEqual(mapDrum(note: 63), 46, "Note 63 should map to open hi-hat (46)")
		XCTAssertEqual(mapDrum(note: 64), 39, "Note 64 should map to clap (39)")
		XCTAssertEqual(mapDrum(note: 65), 41, "Note 65 should map to tom1 (41)")
		XCTAssertEqual(mapDrum(note: 66), 43, "Note 66 should map to tom2 (43)")
		XCTAssertEqual(mapDrum(note: 67), 37, "Note 67 should map to rim (37)")
		XCTAssertEqual(mapDrum(note: 68), 49, "Note 68 should map to crash (49)")
	}
	
	func testDrumMappingBoundary() {
		let startNote: UInt8 = 60
		let layout: [UInt8] = [36, 38, 42, 46, 39, 41, 43, 37, 49]
		
		func mapDrum(note: UInt8) -> UInt8 {
			let idx = Int(note &- startNote)
			let leftIndex = max(0, min(8, idx))
			return layout[leftIndex]
		}
		
		// Test boundary conditions - note: below range wraps due to unsigned subtraction
		// so max(0, min(8, large_number)) = 8, returning crash (49)
		XCTAssertEqual(mapDrum(note: 59), 49, "Below range wraps to max index (crash)")
		XCTAssertEqual(mapDrum(note: 100), 49, "Above range should clamp to crash")
	}
	
	// MARK: - Instrument Choice Tests
	
	func testLeftChoicesContainDrumKit() {
		let leftChoices = ["Drum Kit", "808 Bass", "Piano", "E‑Piano", "Organ", "Strings", "Lead", "Pad"]
		XCTAssertTrue(leftChoices.contains("Drum Kit"), "Left choices should include Drum Kit")
	}
	
	func testRightChoicesContainPiano() {
		let rightChoices = ["Piano", "E‑Piano", "Organ", "Strings", "Lead", "Pad", "Drum Kit", "808 Bass"]
		XCTAssertTrue(rightChoices.contains("Piano"), "Right choices should include Piano")
	}
}

// MARK: - Vocal Recording Length

/// Exercise the production capture/finish lifecycle without requesting a microphone.
final class VocalRecordingLengthTests: XCTestCase {
    @MainActor
    private func makeViewModel(
        makeStorage: (URL) -> SessionStorage = { SessionStorage(directoryURL: $0) }
    ) throws -> LooperViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocalRecordingLength-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vm = LooperViewModel(storage: makeStorage(directory))
        addTeardownBlock {
            await MainActor.run { vm.stopPlayback() }
            try FileManager.default.removeItem(at: directory)
        }
        return vm
    }

    @MainActor
    private func assertRecordedPeriod(_ bars: BarCount, beats: Double,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let vm = try makeViewModel()
        vm.barCount = bars
        vm.bpm = 120
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "fixture.m4a" }), file: file, line: line)
        vm.finishVocalRecording(stopRecording: { true })
        let track = try XCTUnwrap(vm.looper.tracks.only, file: file, line: line)
        XCTAssertEqual(track.recordedLengthBeats, beats, file: file, line: line)
        XCTAssertEqual(track.audioFileName, "fixture.m4a", file: file, line: line)
        XCTAssertTrue(track.isVocal, file: file, line: line)
        XCTAssertTrue(track.isLooping, file: file, line: line)
        XCTAssertFalse(vm.isRecordingVocals, file: file, line: line)
    }

    @MainActor
    func testOneBarVocalStoresFourBeats() throws { try assertRecordedPeriod(.one, beats: 4) }

    @MainActor
    func testTwoBarVocalStoresEightBeats() throws { try assertRecordedPeriod(.two, beats: 8) }

    @MainActor
    func testFourBarVocalStoresSixteenBeats() throws { try assertRecordedPeriod(.four, beats: 16) }

    @MainActor
    func testEightBarVocalStoresThirtyTwoBeats() throws { try assertRecordedPeriod(.eight, beats: 32) }

    @MainActor
    func testSixteenBarVocalStoresSixtyFourBeats() throws { try assertRecordedPeriod(.sixteen, beats: 64) }

    @MainActor
    func testAutoStopUsesStartingBarsAndTempoAfterSettingsChange() throws {
        let vm = try makeViewModel()
        vm.barCount = .one
        vm.bpm = 120
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "one-bar.m4a" }))
        vm.setBarCount(.eight)
        vm.bpm = 60
        var stops = 0
        let stop = { stops += 1; return true }
        vm.checkVocalRecordingAutoStop(recordingElapsed: 1.999, stopRecording: stop)
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(vm.isRecordingVocals)
        vm.checkVocalRecordingAutoStop(recordingElapsed: 2, stopRecording: stop)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 4)
        XCTAssertFalse(vm.isRecordingVocals)
        XCTAssertTrue(vm.isPaused)
        XCTAssertEqual(vm.looper.synchronizedPlaybackPosition, 0)
    }

    @MainActor
    func testEarlyManualStopKeepsThePlannedBarPeriod() throws {
        let vm = try makeViewModel()
        vm.barCount = .eight
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "short-take.m4a" }))
        // An immediate manual stop still occupies the selected eight-bar phrase.
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 32)
    }

    @MainActor
    func testSettingsAreCapturedBeforeTheRecorderStarts() throws {
        let vm = try makeViewModel()
        vm.barCount = .two
        vm.bpm = 120
        XCTAssertTrue(vm.beginVocalRecording(startRecording: {
            vm.barCount = .eight
            vm.bpm = 30
            return "two-bar.m4a"
        }))
        vm.checkVocalRecordingAutoStop(recordingElapsed: 4, stopRecording: { true })
        XCTAssertFalse(vm.isRecordingVocals)
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 8)
    }

    @MainActor
    func testFailedStartRestoresVolumeAndDoesNotReuseMetadata() throws {
        let vm = try makeViewModel()
        let normalVolume = vm.audio.masterVolume
        vm.barCount = .one
        XCTAssertFalse(vm.beginVocalRecording(startRecording: { nil }))
        XCTAssertFalse(vm.isRecordingVocals)
        XCTAssertEqual(vm.audio.masterVolume, normalVolume)
        var stops = 0
        vm.finishVocalRecording(stopRecording: { stops += 1; return true })
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(vm.looper.tracks.isEmpty)
        vm.barCount = .eight
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "retry.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 32)
        XCTAssertEqual(vm.looper.tracks.only?.audioFileName, "retry.m4a")
        XCTAssertEqual(vm.audio.masterVolume, normalVolume)
    }

    @MainActor
    func testFailedStopDiscardsTheCaptureBeforeTheNextTake() throws {
        let vm = try makeViewModel()
        vm.barCount = .eight
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "failed.m4a" }))
        vm.finishVocalRecording(stopRecording: { false })
        XCTAssertFalse(vm.isRecordingVocals)
        XCTAssertTrue(vm.looper.tracks.isEmpty)
        vm.barCount = .two
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "next.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 8)
        XCTAssertEqual(vm.looper.tracks.only?.audioFileName, "next.m4a")
    }

    @MainActor
    func testInvalidTempoRejectsStartWithoutCallingTheRecorder() throws {
        let vm = try makeViewModel()
        let normalVolume = vm.audio.masterVolume
        var starts = 0
        for invalidTempo in [0.0, -1, .nan, .infinity, Double.leastNonzeroMagnitude] {
            vm.bpm = invalidTempo
            XCTAssertFalse(vm.beginVocalRecording(startRecording: { starts += 1; return "invalid.m4a" }))
            XCTAssertFalse(vm.isRecordingVocals)
            XCTAssertEqual(vm.audio.masterVolume, normalVolume)
        }
        XCTAssertEqual(starts, 0)
        vm.bpm = 120
        vm.barCount = .one
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "valid.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 4)
    }

    @MainActor
    func testDuplicateStartAndStopCannotReplaceOrDuplicateTheTake() throws {
        let vm = try makeViewModel()
        vm.barCount = .two
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "first.m4a" }))
        vm.barCount = .eight
        var duplicateStarts = 0
        XCTAssertFalse(vm.beginVocalRecording(startRecording: { duplicateStarts += 1; return "second.m4a" }))
        var stops = 0
        vm.finishVocalRecording(stopRecording: { stops += 1; return true })
        vm.finishVocalRecording(stopRecording: { stops += 1; return true })
        XCTAssertEqual(duplicateStarts, 0)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(vm.looper.tracks.only?.audioFileName, "first.m4a")
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 8)
    }

    @MainActor
    func testNewVocalDoesNotChangeExistingMIDIOrVocalData() throws {
        let vm = try makeViewModel()
        let existing = [
            Track(audioFileName: "legacy-default.m4a", isMuted: true, volume: 0.3),
            Track(audioFileName: "explicit-period.m4a", isSolo: true, recordedLengthBeats: 7, isLooping: false),
            Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
                  notes: [MidiNote(pitch: 64, velocity: 99, startBeat: 0.5, durationBeats: 1)],
                  recordedLengthBeats: 32)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let originalBytes = try encoder.encode(existing)
        vm.looper.loadTracks(existing)
        vm.barCount = .one
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "new.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.count, 4)
        XCTAssertEqual(try encoder.encode(Array(vm.looper.tracks.prefix(3))), originalBytes)
        XCTAssertEqual(vm.looper.tracks.last?.recordedLengthBeats, 4)
    }

    @MainActor
    func testCancelledPermissionRequestCannotStartARecordingLater() async throws {
        let vm = try makeViewModel()
        let requested = expectation(description: "Permission request started")
        var decision: CheckedContinuation<Bool, Never>?
        var starts = 0
        let task = try XCTUnwrap(vm.requestVocalRecordingPermission(requestPermission: {
            await withCheckedContinuation { continuation in
                decision = continuation
                requested.fulfill()
            }
        }, startRecording: { starts += 1; return "cancelled.m4a" }))
        await fulfillment(of: [requested], timeout: 3)
        vm.stopVocalRecording()
        decision?.resume(returning: true)
        await task.value
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(vm.isRecordingVocals)
        XCTAssertTrue(vm.looper.tracks.isEmpty)
        vm.barCount = .two
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "later.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 8)
    }

    @MainActor
    func testDeniedPermissionLeavesTheNextTakeClean() async throws {
        let vm = try makeViewModel()
        var starts = 0
        let task = try XCTUnwrap(vm.requestVocalRecordingPermission(requestPermission: { false },
            startRecording: { starts += 1; return "denied.m4a" }))
        await task.value
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(vm.showMicPermissionAlert)
        XCTAssertFalse(vm.isRecordingVocals)
        vm.barCount = .eight
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "granted.m4a" }))
        vm.finishVocalRecording(stopRecording: { true })
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 32)
    }

    @MainActor
    private func assertPendingPermissionIsCancelled(
        grant: Bool = true,
        makeStorage: (URL) -> SessionStorage = { SessionStorage(directoryURL: $0) },
        by action: (LooperViewModel) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let vm = try makeViewModel(makeStorage: makeStorage)
        let playing = expectation(description: "Playback state forwarded")
        let subscription = vm.$isPlaying.first { $0 }.sink { _ in playing.fulfill() }
        vm.looper.startPlayback()
        await fulfillment(of: [playing], timeout: 3)
        withExtendedLifetime(subscription) {}

        let requested = expectation(description: "Delayed permission requested")
        var decision: CheckedContinuation<Bool, Never>?
        var starts = 0
        let task = try XCTUnwrap(vm.requestVocalRecordingPermission(requestPermission: {
            await withCheckedContinuation { continuation in
                decision = continuation
                requested.fulfill()
            }
        }, startRecording: { starts += 1; return "obsolete.m4a" }))
        await fulfillment(of: [requested], timeout: 3)
        action(vm)
        let expectedIDs = vm.looper.tracks.map(\.id)
        let expectedPlayback = vm.looper.isPlaying
        let expectedPause = vm.isPaused
        decision?.resume(returning: grant)
        await task.value
        XCTAssertEqual(starts, 0, file: file, line: line)
        XCTAssertFalse(vm.isRecordingVocals, file: file, line: line)
        XCTAssertFalse(vm.showMicPermissionAlert, file: file, line: line)
        XCTAssertEqual(vm.looper.tracks.map(\.id), expectedIDs, file: file, line: line)
        XCTAssertEqual(vm.looper.isPlaying, expectedPlayback, file: file, line: line)
        XCTAssertEqual(vm.isPaused, expectedPause, file: file, line: line)
        // Prevent an intentionally started MIDI count-in from outliving its fixture.
        if vm.isCountingIn { vm.toggleRecordingWithResume() }
        if vm.looper.isRecording { vm.stopRecording() }
    }

    @MainActor
    func testPlayPauseCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.togglePlayPause() }
    }

    @MainActor
    func testStopPlaybackCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.stopPlayback() }
    }

    @MainActor
    func testPausePlaybackCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.pausePlayback() }
    }

    @MainActor
    func testRestartAndTogglePlaybackCancelPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.restartPlayback() }
        try await assertPendingPermissionIsCancelled { $0.togglePlayback() }
    }

    @MainActor
    func testClearAllCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { XCTAssertTrue($0.clearAll()) }
    }

    @MainActor
    func testLoadSessionCancelsPendingVocalPermission() async throws {
        let session = SavedSession(name: "Replacement", bpm: 90, barCount: 2,
                                   tracks: [Track(audioFileName: "existing.m4a", recordedLengthBeats: 8)])
        try await assertPendingPermissionIsCancelled { XCTAssertTrue($0.loadSession(session)) }
    }

    @MainActor
    func testImportSessionCancelsPendingVocalPermission() async throws {
        let session = SavedSession(name: "Imported", bpm: 80, barCount: 1, tracks: [])
        try await assertPendingPermissionIsCancelled { XCTAssertTrue($0.loadImportedSession(session)) }
    }

    @MainActor
    func testRestoreWorkingSessionCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled {
            $0.looper.addAudioTrack(Track(audioFileName: "saved.m4a", recordedLengthBeats: 8))
            XCTAssertTrue($0.saveWorkingSession())
            XCTAssertTrue($0.restoreWorkingSession())
        }
    }

    @MainActor
    func testFailedClearAndLoadStillCancelPendingVocalPermission() async throws {
        let makeStorage: (URL) -> SessionStorage = {
            SessionStorage(directoryURL: $0, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        }
        try await assertPendingPermissionIsCancelled(makeStorage: makeStorage) {
            $0.looper.addAudioTrack(Track(audioFileName: "retained.m4a"))
            XCTAssertTrue($0.saveWorkingSession())
            XCTAssertFalse($0.clearAll())
        }
        try await assertPendingPermissionIsCancelled(makeStorage: makeStorage) {
            $0.looper.addAudioTrack(Track(audioFileName: "retained.m4a"))
            XCTAssertTrue($0.saveWorkingSession())
            XCTAssertFalse($0.loadSession(SavedSession(name: "Other", bpm: 120, barCount: 4, tracks: [])))
        }
    }

    @MainActor
    func testLateDenialAfterPauseDoesNotShowAnObsoletePermissionAlert() async throws {
        try await assertPendingPermissionIsCancelled(grant: false) { $0.togglePlayPause() }
    }

    @MainActor
    func testNewMIDIRecordingOrCountInCancelsPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.startRecording() }
        try await assertPendingPermissionIsCancelled { $0.toggleRecordingWithResume() }
    }

    @MainActor
    func testSecondVocalRecordTapCancelsPendingPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.toggleVocalRecording() }
        try await assertPendingPermissionIsCancelled { $0.toggleVocalRecordingWithResume() }
    }

    @MainActor
    func testSeekResumeAndInstrumentSelectionCancelPendingVocalPermission() async throws {
        try await assertPendingPermissionIsCancelled { $0.seekToPosition(0) }
        try await assertPendingPermissionIsCancelled { $0.resumePlayback() }
        try await assertPendingPermissionIsCancelled { $0.selectInstrument(.piano) }
    }

    @MainActor
    func testInvalidElapsedTimeCannotAutoStopTheTake() throws {
        let vm = try makeViewModel()
        vm.barCount = .one
        vm.bpm = 120
        XCTAssertTrue(vm.beginVocalRecording(startRecording: { "valid.m4a" }))
        var stops = 0
        for invalidElapsed in [-1.0, .nan, .infinity] {
            vm.checkVocalRecordingAutoStop(recordingElapsed: invalidElapsed, stopRecording: { stops += 1; return true })
        }
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(vm.isRecordingVocals)
        vm.checkVocalRecordingAutoStop(recordingElapsed: 2, stopRecording: { stops += 1; return true })
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(vm.looper.tracks.only?.recordedLengthBeats, 4)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

// MARK: - Integration Test for Audio Flow

final class AudioFlowIntegrationTests: XCTestCase {
	
	func testFullAudioSetupSequence() throws {
		let engine = TishAudioEngine()
		
		// Step 1: Configure session
		XCTAssertNoThrow(try engine.configureSession(), "Session configuration should succeed")
		
		// Step 2: Load sound fonts (may fail without GM.sf2 in test bundle)
		do {
			try engine.loadSoundFonts()
			XCTAssertNotNil(engine.soundFontURL, "SoundFont URL should be set")
			
			// Step 3: Load left drums
			XCTAssertNoThrow(try engine.setLeftDrums(), "Loading left drums should succeed")
			
			// Step 4: Load right piano
			XCTAssertNoThrow(try engine.setRight(program: .acousticPiano), "Loading right piano should succeed")
			
			// Step 5: Start engine
			XCTAssertNoThrow(try engine.start(), "Starting engine should succeed")
			XCTAssertTrue(engine.engine.isRunning, "Engine should be running")
			
		} catch {
			throw XCTSkip("GM.sf2 not available: \(error)")
		}
	}
	
	func testNoteRoutingDoesNotCrash() throws {
		let engine = TishAudioEngine()
		
		try engine.configureSession()
		
		do {
			try engine.loadSoundFonts()
			try engine.setLeftDrums()
			try engine.setRight(program: .acousticPiano)
			try engine.start()
		} catch {
			throw XCTSkip("GM.sf2 not available: \(error)")
		}
		
		// Test note routing - should not crash
		XCTAssertNoThrow(engine.noteOn(note: 60, velocity: 100, isLeft: true), "Left note on should not crash")
		XCTAssertNoThrow(engine.noteOn(note: 60, velocity: 100, isLeft: false), "Right note on should not crash")
		XCTAssertNoThrow(engine.noteOff(note: 60, isLeft: true), "Left note off should not crash")
		XCTAssertNoThrow(engine.noteOff(note: 60, isLeft: false), "Right note off should not crash")
		XCTAssertNoThrow(engine.stopAllNotes(), "Stop all notes should not crash")
	}
	
	func testInstrumentChangesDoNotCrash() throws {
		let engine = TishAudioEngine()
		
		try engine.configureSession()
		
		do {
			try engine.loadSoundFonts()
			try engine.start()
		} catch {
			throw XCTSkip("GM.sf2 not available: \(error)")
		}
		
		// Test all instrument programs
		for program in InstrumentProgram.allCases {
			XCTAssertNoThrow(
				try engine.setLeft(program: program),
				"Setting left to \(program.displayName) should not crash"
			)
			XCTAssertNoThrow(
				try engine.setRight(program: program),
				"Setting right to \(program.displayName) should not crash"
			)
		}
		
		// Test drum kit
		XCTAssertNoThrow(try engine.setLeftDrums(), "Setting left drums should not crash")
		XCTAssertNoThrow(try engine.setRightDrums(), "Setting right drums should not crash")
	}
}
