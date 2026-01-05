import XCTest
@testable import Loopa

@MainActor
final class TrackFocusViewModelTests: XCTestCase {
    
    private var looperVM: LooperViewModel!
    private var track: Track!
    private var focusVM: TrackFocusViewModel!
    
    override func setUp() async throws {
        looperVM = LooperViewModel()
        track = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1),
                MidiNote(pitch: 64, velocity: 90, startBeat: 2, durationBeats: 0.5),
                MidiNote(pitch: 67, velocity: 80, startBeat: 4, durationBeats: 2)
            ]
        )
        focusVM = TrackFocusViewModel(track: track, looperVM: looperVM)
    }
    
    override func tearDown() async throws {
        looperVM = nil
        track = nil
        focusVM = nil
    }
    
    // MARK: - Note Selection Tests
    
    func testSelectNote() {
        let noteId = focusVM.track.notes[0].id
        
        focusVM.selectNote(noteId)
        
        XCTAssertEqual(focusVM.selectedNoteId, noteId)
        XCTAssertNotNil(focusVM.selectedNote)
        XCTAssertEqual(focusVM.selectedNote?.pitch, 60)
    }
    
    func testDeselectNote() {
        let noteId = focusVM.track.notes[0].id
        focusVM.selectNote(noteId)
        
        focusVM.deselectNote()
        
        XCTAssertNil(focusVM.selectedNoteId)
        XCTAssertNil(focusVM.selectedNote)
    }
    
    // MARK: - Move Note Tests
    
    func testMoveNoteSnapsToGrid() {
        let note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25 // 1/16 note
        
        // Move to a position that's not on grid
        focusVM.moveNote(note.id, toStartBeat: 0.1)
        
        // Should snap to nearest grid point (0.0)
        let movedNote = focusVM.track.notes.first { $0.id == note.id }
        XCTAssertEqual(movedNote?.startBeat, 0.0)
    }
    
    func testMoveNoteSnapsToGridEighthNote() {
        let note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        
        // Move to 0.4 beats - should snap to 0.5
        focusVM.moveNote(note.id, toStartBeat: 0.4)
        
        let movedNote = focusVM.track.notes.first { $0.id == note.id }
        XCTAssertEqual(movedNote?.startBeat, 0.5)
    }
    
    func testMoveNoteClampsToBounds() {
        let note = focusVM.track.notes[0]
        let loopLength = focusVM.loopLengthBeats
        
        // Try to move past loop end
        focusVM.moveNote(note.id, toStartBeat: loopLength + 5)
        
        let movedNote = focusVM.track.notes.first { $0.id == note.id }
        // Should be clamped so that note end doesn't exceed loop
        XCTAssertLessThanOrEqual(movedNote!.endBeat, loopLength)
    }
    
    func testMoveNoteClampsToStart() {
        let note = focusVM.track.notes[0]
        
        // Try to move before loop start
        focusVM.moveNote(note.id, toStartBeat: -5)
        
        let movedNote = focusVM.track.notes.first { $0.id == note.id }
        XCTAssertGreaterThanOrEqual(movedNote!.startBeat, 0)
    }
    
    // MARK: - Resize Note Tests
    
    func testResizeNoteMinimumDuration() {
        let note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        
        // Try to resize to very small duration
        focusVM.resizeNote(note.id, toDuration: 0.05)
        
        let resizedNote = focusVM.track.notes.first { $0.id == note.id }
        // Should be at least one grid step
        XCTAssertGreaterThanOrEqual(resizedNote!.durationBeats, focusVM.gridStep)
    }
    
    func testResizeNoteSnapsToGrid() {
        let note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        
        // Resize to non-grid value
        focusVM.resizeNote(note.id, toDuration: 0.6)
        
        let resizedNote = focusVM.track.notes.first { $0.id == note.id }
        // Should snap to 0.5 (nearest grid)
        XCTAssertEqual(resizedNote?.durationBeats, 0.5)
    }
    
    func testResizeNoteClampsToBounds() {
        // Move note near end of loop
        let note = focusVM.track.notes[0]
        let loopLength = focusVM.loopLengthBeats
        focusVM.moveNote(note.id, toStartBeat: loopLength - 2)
        
        // Try to resize beyond loop
        focusVM.resizeNote(note.id, toDuration: 10)
        
        let resizedNote = focusVM.track.notes.first { $0.id == note.id }
        XCTAssertLessThanOrEqual(resizedNote!.endBeat, loopLength)
    }
    
    // MARK: - Delete Note Tests
    
    func testDeleteNoteRemovesFromTrack() {
        let initialCount = focusVM.track.notes.count
        let noteToDelete = focusVM.track.notes[0]
        
        focusVM.deleteNote(noteToDelete.id)
        
        XCTAssertEqual(focusVM.track.notes.count, initialCount - 1)
        XCTAssertNil(focusVM.track.notes.first { $0.id == noteToDelete.id })
    }
    
    func testDeleteSelectedNoteDeselectsIt() {
        let note = focusVM.track.notes[0]
        focusVM.selectNote(note.id)
        
        focusVM.deleteNote(note.id)
        
        XCTAssertNil(focusVM.selectedNoteId)
    }
    
    // Note: Delete confirmation flow was removed - notes now delete directly
    
    // MARK: - Add Note Tests
    
    func testAddNote() {
        let initialCount = focusVM.track.notes.count
        
        focusVM.addNote(pitch: 72, startBeat: 6, duration: 1)
        
        XCTAssertEqual(focusVM.track.notes.count, initialCount + 1)
        
        // Find the note by pitch (72 is unique in the test)
        let addedNote = focusVM.track.notes.first { $0.pitch == 72 }
        XCTAssertNotNil(addedNote)
        XCTAssertEqual(addedNote?.pitch, 72)
        XCTAssertEqual(addedNote?.startBeat, 6.0)
    }
    
    func testAddNoteSnapsToGrid() {
        focusVM.gridStep = 0.25
        
        focusVM.addNote(pitch: 72, startBeat: 0.1, duration: 0.6)
        
        // Find the note we just added by pitch (72 is unique)
        let addedNote = focusVM.track.notes.first { $0.pitch == 72 }
        XCTAssertNotNil(addedNote)
        XCTAssertEqual(addedNote?.startBeat, 0.0) // Snapped from 0.1
        XCTAssertEqual(addedNote?.durationBeats, 0.5) // Snapped from 0.6
    }
    
    func testAddNoteSelectsIt() {
        focusVM.addNote(pitch: 72, startBeat: 6, duration: 1)
        
        // Find the note we just added by pitch (72 is unique)
        let addedNote = focusVM.track.notes.first { $0.pitch == 72 }
        XCTAssertNotNil(addedNote)
        XCTAssertEqual(focusVM.selectedNoteId, addedNote?.id)
    }
    
    // MARK: - Chord Tests
    
    func testChordsRemainIndependent() {
        // Add a chord (multiple notes at same beat)
        focusVM.addNote(pitch: 60, startBeat: 8, duration: 1)
        focusVM.addNote(pitch: 64, startBeat: 8, duration: 1)
        focusVM.addNote(pitch: 67, startBeat: 8, duration: 1)
        
        let chordNotes = focusVM.track.notes.filter { $0.startBeat == 8 }
        XCTAssertEqual(chordNotes.count, 3)
        
        // Move one note of the chord
        let noteToMove = chordNotes.first { $0.pitch == 64 }!
        focusVM.moveNote(noteToMove.id, toStartBeat: 10)
        
        // Other chord notes should remain at beat 8
        let remainingChord = focusVM.track.notes.filter { $0.startBeat == 8 }
        XCTAssertEqual(remainingChord.count, 2)
        
        // Moved note should be at beat 10
        let movedNote = focusVM.track.notes.first { $0.id == noteToMove.id }
        XCTAssertEqual(movedNote?.startBeat, 10)
    }
    
    // MARK: - Grid Step Tests
    
    func testSetGridStep() {
        focusVM.setGridStep(.eighth)
        XCTAssertEqual(focusVM.gridStep, 0.5)
        
        focusVM.setGridStep(.quarter)
        XCTAssertEqual(focusVM.gridStep, 1.0)
        
        focusVM.setGridStep(.sixteenth)
        XCTAssertEqual(focusVM.gridStep, 0.25)
        
        focusVM.setGridStep(.thirtysecond)
        XCTAssertEqual(focusVM.gridStep, 0.125)
    }
    
    // MARK: - Quantize Track Tests
    
    func testQuantizeTrack() {
        // Add notes at non-grid positions
        focusVM.addNote(pitch: 60, startBeat: 0.1, duration: 0.3)
        focusVM.addNote(pitch: 64, startBeat: 1.3, duration: 0.7)
        
        focusVM.quantizeTrack(division: .quarter)
        
        // Notes should be snapped to quarter note grid
        let notes = focusVM.track.notes.filter { $0.pitch >= 60 }
        let snappedToGrid = notes.allSatisfy { note in
            note.startBeat.truncatingRemainder(dividingBy: 1.0) == 0 &&
            note.durationBeats.truncatingRemainder(dividingBy: 1.0) == 0
        }
        XCTAssertTrue(snappedToGrid)
    }
}

