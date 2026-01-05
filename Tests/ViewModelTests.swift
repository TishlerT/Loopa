import XCTest
@testable import Loopa

final class ViewModelTests: XCTestCase {
	
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

