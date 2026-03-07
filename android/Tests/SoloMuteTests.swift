import XCTest
@testable import Loopa

final class SoloMuteTests: XCTestCase {
    
    // MARK: - Track Audibility Tests
    
    func testUnmutedTrackIsAudibleWithNoSolo() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: false,
            isSolo: false
        )
        
        XCTAssertTrue(track.isAudible(anyTrackSoloed: false))
    }
    
    func testMutedTrackIsNotAudible() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: true,
            isSolo: false
        )
        
        // Muted tracks are never audible, regardless of solo state
        XCTAssertFalse(track.isAudible(anyTrackSoloed: false))
        XCTAssertFalse(track.isAudible(anyTrackSoloed: true))
    }
    
    func testSoloedTrackIsAudibleWhenAnySoloed() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: false,
            isSolo: true
        )
        
        XCTAssertTrue(track.isAudible(anyTrackSoloed: true))
    }
    
    func testNonSoloedTrackIsNotAudibleWhenAnySoloed() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: false,
            isSolo: false
        )
        
        // When any track is soloed, non-soloed tracks are not audible
        XCTAssertFalse(track.isAudible(anyTrackSoloed: true))
    }
    
    func testMutedSoloedTrackIsNotAudible() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: true,
            isSolo: true
        )
        
        // Mute takes precedence over solo
        XCTAssertFalse(track.isAudible(anyTrackSoloed: true))
    }
    
    // MARK: - Multiple Tracks Scenario Tests
    
    func testMultipleTracksNoSolo() {
        let tracks = [
            Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [], isMuted: false, isSolo: false),
            Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true, notes: [], isMuted: false, isSolo: false),
            Track(instrumentName: "Bass", instrumentProgram: 32, isDrumKit: false, notes: [], isMuted: true, isSolo: false)
        ]
        
        let anyTrackSoloed = tracks.contains { $0.isSolo }
        XCTAssertFalse(anyTrackSoloed)
        
        // Piano and Drums are audible, Bass is muted
        XCTAssertTrue(tracks[0].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertTrue(tracks[1].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertFalse(tracks[2].isAudible(anyTrackSoloed: anyTrackSoloed))
    }
    
    func testMultipleTracksWithOneSolo() {
        let tracks = [
            Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [], isMuted: false, isSolo: true),
            Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true, notes: [], isMuted: false, isSolo: false),
            Track(instrumentName: "Bass", instrumentProgram: 32, isDrumKit: false, notes: [], isMuted: false, isSolo: false)
        ]
        
        let anyTrackSoloed = tracks.contains { $0.isSolo }
        XCTAssertTrue(anyTrackSoloed)
        
        // Only Piano (soloed) is audible
        XCTAssertTrue(tracks[0].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertFalse(tracks[1].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertFalse(tracks[2].isAudible(anyTrackSoloed: anyTrackSoloed))
    }
    
    func testMultipleTracksWithMultipleSolos() {
        let tracks = [
            Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [], isMuted: false, isSolo: true),
            Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true, notes: [], isMuted: false, isSolo: true),
            Track(instrumentName: "Bass", instrumentProgram: 32, isDrumKit: false, notes: [], isMuted: false, isSolo: false)
        ]
        
        let anyTrackSoloed = tracks.contains { $0.isSolo }
        XCTAssertTrue(anyTrackSoloed)
        
        // Piano and Drums (both soloed) are audible
        XCTAssertTrue(tracks[0].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertTrue(tracks[1].isAudible(anyTrackSoloed: anyTrackSoloed))
        XCTAssertFalse(tracks[2].isAudible(anyTrackSoloed: anyTrackSoloed))
    }
    
    // MARK: - Vocal Track Tests
    
    func testVocalTrackAudibility() {
        let vocalTrack = Track(audioFileName: "vocals.m4a", isMuted: false, isSolo: false)
        
        XCTAssertTrue(vocalTrack.isVocal)
        XCTAssertTrue(vocalTrack.isAudible(anyTrackSoloed: false))
        
        // When another track is soloed
        XCTAssertFalse(vocalTrack.isAudible(anyTrackSoloed: true))
    }
    
    func testSoloedVocalTrack() {
        let vocalTrack = Track(audioFileName: "vocals.m4a", isMuted: false, isSolo: true)
        
        XCTAssertTrue(vocalTrack.isAudible(anyTrackSoloed: true))
    }
}

