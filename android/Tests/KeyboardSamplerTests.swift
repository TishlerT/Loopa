import XCTest
import AVFoundation
@testable import Loopa

final class KeyboardSamplerTests: XCTestCase {
	
	var sampler: KeyboardSampler!
	var engine: AVAudioEngine!
	var testSoundFontURL: URL?
	
	override func setUp() {
		super.setUp()
		sampler = KeyboardSampler()
		engine = AVAudioEngine()
		
		// Attach sampler to engine (required for it to function)
		engine.attach(sampler.sampler)
		engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
		
		// Try to find GM.sf2 in the main bundle
		testSoundFontURL = Bundle.main.url(forResource: "GM", withExtension: "sf2")
	}
	
	override func tearDown() {
		engine.stop()
		engine = nil
		sampler = nil
		super.tearDown()
	}
	
	// MARK: - Initialization Tests
	
	func testSamplerInitialization() {
		XCTAssertNotNil(sampler.sampler, "AVAudioUnitSampler should be initialized")
	}
	
	// MARK: - Program Loading Tests
	
	func testLoadMelodicProgram() throws {
		guard let url = testSoundFontURL else {
			throw XCTSkip("GM.sf2 not available in test bundle")
		}
		
		// Configure and start audio session
		let session = AVAudioSession.sharedInstance()
		try session.setCategory(.playback)
		try session.setActive(true)
		try engine.start()
		
		// Test loading each melodic program
		for program in InstrumentProgram.allCases {
			XCTAssertNoThrow(
				try sampler.load(program: program, soundFontURL: url),
				"Loading program \(program.displayName) (\(program.rawValue)) should not throw"
			)
		}
	}
	
	func testLoadDrumKit() throws {
		guard let url = testSoundFontURL else {
			throw XCTSkip("GM.sf2 not available in test bundle")
		}
		
		let session = AVAudioSession.sharedInstance()
		try session.setCategory(.playback)
		try session.setActive(true)
		try engine.start()
		
		XCTAssertNoThrow(
			try sampler.loadDrumKit(soundFontURL: url),
			"Loading drum kit should not throw"
		)
	}
	
	func testLoadInvalidSoundFont() {
		let invalidURL = URL(fileURLWithPath: "/nonexistent/file.sf2")
		
		XCTAssertThrowsError(
			try sampler.load(program: .acousticPiano, soundFontURL: invalidURL),
			"Loading from invalid URL should throw"
		)
	}
	
	// MARK: - Note Control Tests
	
	func testStopAllSendsControlMessages() {
		// This just verifies stopAll doesn't crash - actual MIDI verification would need mocking
		XCTAssertNoThrow(sampler.stopAll(), "stopAll should not throw")
	}
}

// MARK: - InstrumentProgram Tests

final class InstrumentProgramTests: XCTestCase {
	
	func testAllProgramsHaveDisplayNames() {
		for program in InstrumentProgram.allCases {
			XCTAssertFalse(program.displayName.isEmpty, "Program \(program.rawValue) should have a display name")
		}
	}
	
	func testProgramRawValuesAreValidGM() {
		// Valid GM melodic program numbers are 0-127
		for program in InstrumentProgram.allCases {
			XCTAssertLessThanOrEqual(program.rawValue, 127, "Program \(program.displayName) should have valid GM number")
		}
	}
	
	func testExpectedProgramNumbers() {
		// Verify the expected GM program numbers
		XCTAssertEqual(InstrumentProgram.acousticPiano.rawValue, 0)
		XCTAssertEqual(InstrumentProgram.electricPiano.rawValue, 4)
		XCTAssertEqual(InstrumentProgram.organ.rawValue, 16)
		XCTAssertEqual(InstrumentProgram.nylonGuitar.rawValue, 24)
		XCTAssertEqual(InstrumentProgram.strings.rawValue, 48)
		XCTAssertEqual(InstrumentProgram.synthLead.rawValue, 80)
		XCTAssertEqual(InstrumentProgram.synthPad.rawValue, 88)
	}
}


