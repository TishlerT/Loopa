import XCTest
@testable import Loopa

/// Tests for track volume independence - verifying that changing one track's volume
/// does not affect other tracks' volumes
final class TrackVolumeTests: XCTestCase {
    
    // MARK: - Track Model Volume Tests
    
    func testTrackDefaultVolume() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: []
        )
        
        // Default volume is 0.8 (80%)
        XCTAssertEqual(track.volume, 0.8, accuracy: 0.001)
    }
    
    func testTrackCustomVolume() {
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.5
        )
        
        XCTAssertEqual(track.volume, 0.5, accuracy: 0.001)
    }
    
    func testVocalTrackDefaultVolume() {
        let vocalTrack = Track(audioFileName: "vocals.m4a")
        
        // Vocal tracks also default to 0.8
        XCTAssertEqual(vocalTrack.volume, 0.8, accuracy: 0.001)
    }
    
    func testVocalTrackCustomVolume() {
        let vocalTrack = Track(audioFileName: "vocals.m4a", volume: 0.3)
        
        XCTAssertEqual(vocalTrack.volume, 0.3, accuracy: 0.001)
    }
    
    // MARK: - MultiTrackLooper Volume Independence Tests
    
    func testSetTrackVolumeDoesNotAffectOtherTracks() {
        let looper = MultiTrackLooper()
        
        // Create two tracks with different volumes
        var track1 = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [MidiNote(pitch: 60, startBeat: 0, durationBeats: 1)],
            volume: 0.8
        )
        var track2 = Track(
            instrumentName: "Drums",
            instrumentProgram: 0,
            isDrumKit: true,
            notes: [MidiNote(pitch: 36, startBeat: 0, durationBeats: 0.5)],
            volume: 0.8
        )
        
        // Add tracks to looper by simulating recording completion
        looper.loadTracks([track1, track2])
        
        // Change track1's volume
        looper.setTrackVolume(track1.id, volume: 0.2)
        
        // Verify track1's volume changed
        let updatedTrack1 = looper.track(withId: track1.id)
        XCTAssertEqual(updatedTrack1?.volume, 0.2, accuracy: 0.001, "Track 1 volume should be 0.2")
        
        // Verify track2's volume is unchanged
        let updatedTrack2 = looper.track(withId: track2.id)
        XCTAssertEqual(updatedTrack2?.volume, 0.8, accuracy: 0.001, "Track 2 volume should remain 0.8")
    }
    
    func testSetMultipleTrackVolumesIndependently() {
        let looper = MultiTrackLooper()
        
        // Create three tracks
        let track1 = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.8
        )
        let track2 = Track(
            instrumentName: "Bass",
            instrumentProgram: 32,
            isDrumKit: false,
            notes: [],
            volume: 0.8
        )
        let track3 = Track(audioFileName: "vocals.m4a", volume: 0.8)
        
        looper.loadTracks([track1, track2, track3])
        
        // Set each track to a different volume
        looper.setTrackVolume(track1.id, volume: 0.1)
        looper.setTrackVolume(track2.id, volume: 0.5)
        looper.setTrackVolume(track3.id, volume: 0.9)
        
        // Verify each track has its independent volume
        XCTAssertEqual(looper.track(withId: track1.id)?.volume, 0.1, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: track2.id)?.volume, 0.5, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: track3.id)?.volume, 0.9, accuracy: 0.001)
    }
    
    func testVolumeClampingAtMinimum() {
        let looper = MultiTrackLooper()
        
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: []
        )
        looper.loadTracks([track])
        
        // Set volume below 0
        looper.setTrackVolume(track.id, volume: -0.5)
        
        // Should be clamped to 0
        XCTAssertEqual(looper.track(withId: track.id)?.volume, 0.0, accuracy: 0.001)
    }
    
    func testVolumeClampingAtMaximum() {
        let looper = MultiTrackLooper()
        
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: []
        )
        looper.loadTracks([track])
        
        // Set volume above 1
        looper.setTrackVolume(track.id, volume: 1.5)
        
        // Should be clamped to 1
        XCTAssertEqual(looper.track(withId: track.id)?.volume, 1.0, accuracy: 0.001)
    }
    
    func testVolumeAtZeroDoesNotAffectOtherTracks() {
        let looper = MultiTrackLooper()
        
        let track1 = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.8
        )
        let track2 = Track(
            instrumentName: "Drums",
            instrumentProgram: 0,
            isDrumKit: true,
            notes: [],
            volume: 0.8
        )
        
        looper.loadTracks([track1, track2])
        
        // Mute track1 by setting volume to 0
        looper.setTrackVolume(track1.id, volume: 0.0)
        
        // Track2 should still be at full volume
        XCTAssertEqual(looper.track(withId: track1.id)?.volume, 0.0, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: track2.id)?.volume, 0.8, accuracy: 0.001)
    }
    
    // MARK: - Mixed MIDI and Vocal Track Tests
    
    func testMIDIAndVocalVolumeIndependence() {
        let looper = MultiTrackLooper()
        
        let midiTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [MidiNote(pitch: 60, startBeat: 0, durationBeats: 1)],
            volume: 0.8
        )
        let vocalTrack = Track(audioFileName: "vocals.m4a", volume: 0.8)
        
        looper.loadTracks([midiTrack, vocalTrack])
        
        // Change MIDI track volume
        looper.setTrackVolume(midiTrack.id, volume: 0.3)
        
        // Vocal track should be unaffected
        XCTAssertEqual(looper.track(withId: midiTrack.id)?.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: vocalTrack.id)?.volume, 0.8, accuracy: 0.001)
        
        // Now change vocal track volume
        looper.setTrackVolume(vocalTrack.id, volume: 0.6)
        
        // MIDI track should still be at 0.3
        XCTAssertEqual(looper.track(withId: midiTrack.id)?.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: vocalTrack.id)?.volume, 0.6, accuracy: 0.001)
    }
    
    // MARK: - Track Deletion Volume Persistence Tests
    
    func testDeletingTrackDoesNotAffectRemainingVolumes() {
        let looper = MultiTrackLooper()
        
        let track1 = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [], volume: 0.3)
        let track2 = Track(instrumentName: "Bass", instrumentProgram: 32, isDrumKit: false, notes: [], volume: 0.5)
        let track3 = Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true, notes: [], volume: 0.7)
        
        looper.loadTracks([track1, track2, track3])
        
        // Delete middle track
        looper.deleteTrack(track2)
        
        // Remaining tracks should keep their volumes
        XCTAssertEqual(looper.track(withId: track1.id)?.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: track3.id)?.volume, 0.7, accuracy: 0.001)
        XCTAssertNil(looper.track(withId: track2.id))
    }
    
    // MARK: - Volume with Solo/Mute Interaction Tests
    
    func testVolumeIsPreservedWhenMuted() {
        let looper = MultiTrackLooper()
        
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.6
        )
        looper.loadTracks([track])
        
        // Mute the track
        looper.toggleMute(track)
        
        // Volume should be preserved even when muted
        let mutedTrack = looper.track(withId: track.id)
        XCTAssertTrue(mutedTrack?.isMuted ?? false)
        XCTAssertEqual(mutedTrack?.volume, 0.6, accuracy: 0.001)
    }
    
    func testVolumeIsPreservedWhenSoloed() {
        let looper = MultiTrackLooper()
        
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.4
        )
        looper.loadTracks([track])
        
        // Solo the track
        looper.toggleSolo(track)
        
        // Volume should be preserved when soloed
        let soloedTrack = looper.track(withId: track.id)
        XCTAssertTrue(soloedTrack?.isSolo ?? false)
        XCTAssertEqual(soloedTrack?.volume, 0.4, accuracy: 0.001)
    }
    
    func testChangingVolumeWhileMuted() {
        let looper = MultiTrackLooper()
        
        var track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            isMuted: true,
            volume: 0.8
        )
        looper.loadTracks([track])
        
        // Change volume while muted
        looper.setTrackVolume(track.id, volume: 0.2)
        
        // Volume should update even when muted
        let updatedTrack = looper.track(withId: track.id)
        XCTAssertTrue(updatedTrack?.isMuted ?? false)
        XCTAssertEqual(updatedTrack?.volume, 0.2, accuracy: 0.001)
    }
    
    // MARK: - Edge Cases
    
    func testSetVolumeForNonexistentTrack() {
        let looper = MultiTrackLooper()
        
        let track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [],
            volume: 0.8
        )
        looper.loadTracks([track])
        
        // Try to set volume for a UUID that doesn't exist
        let fakeId = UUID()
        looper.setTrackVolume(fakeId, volume: 0.5)
        
        // Original track should be unaffected
        XCTAssertEqual(looper.track(withId: track.id)?.volume, 0.8, accuracy: 0.001)
        XCTAssertNil(looper.track(withId: fakeId))
    }
    
    func testVolumeAfterLoadingSession() {
        let looper = MultiTrackLooper()
        
        // Create tracks with specific volumes
        let tracks = [
            Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [], volume: 0.3),
            Track(instrumentName: "Bass", instrumentProgram: 32, isDrumKit: false, notes: [], volume: 0.6),
            Track(audioFileName: "vocals.m4a", volume: 0.9)
        ]
        
        // Load tracks (simulates loading a session)
        looper.loadTracks(tracks)
        
        // Verify volumes are preserved after loading
        XCTAssertEqual(looper.track(withId: tracks[0].id)?.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: tracks[1].id)?.volume, 0.6, accuracy: 0.001)
        XCTAssertEqual(looper.track(withId: tracks[2].id)?.volume, 0.9, accuracy: 0.001)
    }
}

