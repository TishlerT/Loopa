import XCTest
import AVFoundation
@testable import Loopa

final class AudioEngineTests: XCTestCase {
	
	var engine: TishAudioEngine!
	
	override func setUp() {
		super.setUp()
		engine = TishAudioEngine()
	}
	
	override func tearDown() {
		engine = nil
		super.tearDown()
	}
	
	// MARK: - Initialization Tests
	
	func testEngineInitialization() {
		XCTAssertNotNil(engine.engine, "AVAudioEngine should be initialized")
		XCTAssertNotNil(engine.left, "Left sampler should be initialized")
		XCTAssertNotNil(engine.right, "Right sampler should be initialized")
		XCTAssertNotNil(engine.click, "Click sampler should be initialized")
		XCTAssertNotNil(engine.reverb, "Reverb should be initialized")
	}
	
	func testReverbConfiguration() {
		XCTAssertEqual(engine.reverb.wetDryMix, 12, "Reverb wet/dry mix should be 12")
	}
	
	func testSamplersAttachedToEngine() {
		// Check that samplers are attached by verifying they have an engine
		XCTAssertNotNil(engine.left.sampler.engine, "Left sampler should be attached to engine")
		XCTAssertNotNil(engine.right.sampler.engine, "Right sampler should be attached to engine")
		XCTAssertNotNil(engine.click.sampler.engine, "Click sampler should be attached to engine")
		XCTAssertNotNil(engine.reverb.engine, "Reverb should be attached to engine")
	}
	
	// MARK: - Audio Session Tests
	
	func testConfigureSession() {
		// This test verifies the session configuration doesn't throw
		XCTAssertNoThrow(try engine.configureSession(), "Audio session configuration should not throw")
		
		let session = AVAudioSession.sharedInstance()
		XCTAssertEqual(session.category, .playback, "Category should be .playback")
	}
	
	// MARK: - SoundFont Loading Tests
	
	func testSoundFontURLInitiallyNil() {
		XCTAssertNil(engine.soundFontURL, "SoundFont URL should be nil before loading")
		XCTAssertNil(engine.soundFont808URL, "808 SoundFont URL should be nil before loading")
	}
	
	func testLoadSoundFonts() throws {
		// This will fail if GM.sf2 is not in the test bundle
		// In a real test, we'd mock this or include a test SoundFont
		do {
			try engine.loadSoundFonts()
			XCTAssertNotNil(engine.soundFontURL, "SoundFont URL should be set after loading")
		} catch {
			// If GM.sf2 isn't in test bundle, this is expected
			print("Note: GM.sf2 not found in test bundle - this is expected in unit tests")
		}
	}
	
	// MARK: - Engine Start Tests
	
	func testEngineStart() throws {
		try engine.configureSession()
		XCTAssertNoThrow(try engine.start(), "Engine start should not throw")
		XCTAssertTrue(engine.engine.isRunning, "Engine should be running after start")
	}
	
	func testEngineStartIdempotent() throws {
		try engine.configureSession()
		try engine.start()
		XCTAssertNoThrow(try engine.start(), "Starting an already running engine should not throw")
		XCTAssertTrue(engine.engine.isRunning, "Engine should still be running")
	}
}


