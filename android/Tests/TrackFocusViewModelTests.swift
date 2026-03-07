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
    
    // MARK: - Copy & Paste Tests
    
    func testCopyPastePreservesRelativeOffsets() {
        // Create a track with notes at specific positions
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 2.0, durationBeats: 0.5),
                MidiNote(pitch: 64, velocity: 100, startBeat: 4.0, durationBeats: 0.5),
                MidiNote(pitch: 67, velocity: 100, startBeat: 6.0, durationBeats: 0.5)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        
        // Enable multi-select mode and select all notes
        testVM.toggleMultiSelectMode()
        let noteIds = Set(testVM.track.notes.map { $0.id })
        testVM.selectNotes(noteIds)
        
        // Copy the notes (should store relative offsets: 0.0, 2.0, 4.0)
        testVM.copySelectedNotes()
        
        // Verify we can paste
        XCTAssertTrue(testVM.canPaste)
        
        // Set playhead to beat 10.0
        testVM.currentBeat = 10.0
        
        // Clear existing notes for easier verification
        let originalNoteIds = testVM.track.notes.map { $0.id }
        for id in originalNoteIds {
            testVM.deleteNote(id)
        }
        XCTAssertEqual(testVM.track.notes.count, 0)
        
        // Paste the notes
        testVM.pasteNotes()
        
        // Should have 3 notes with preserved relative offsets
        XCTAssertEqual(testVM.track.notes.count, 3)
        
        // Sort by startBeat to verify positions
        let pastedNotes = testVM.track.notes.sorted { $0.startBeat < $1.startBeat }
        
        // Notes should be at: 10.0, 12.0, 14.0 (playhead + relative offsets 0, 2, 4)
        XCTAssertEqual(pastedNotes[0].startBeat, 10.0, accuracy: 0.001)
        XCTAssertEqual(pastedNotes[1].startBeat, 12.0, accuracy: 0.001)
        XCTAssertEqual(pastedNotes[2].startBeat, 14.0, accuracy: 0.001)
        
        // Verify pitches are preserved
        XCTAssertEqual(pastedNotes[0].pitch, 60)
        XCTAssertEqual(pastedNotes[1].pitch, 64)
        XCTAssertEqual(pastedNotes[2].pitch, 67)
    }
    
    func testCopyPasteWithNonZeroFirstNote() {
        // Test that the leftmost note becomes the reference point
        // Notes at beats 5.0, 7.5, 10.0 -> relative offsets should be 0.0, 2.5, 5.0
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 5.0, durationBeats: 0.5),
                MidiNote(pitch: 64, velocity: 100, startBeat: 7.5, durationBeats: 0.5),
                MidiNote(pitch: 67, velocity: 100, startBeat: 10.0, durationBeats: 0.5)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        
        // Enable multi-select and select all
        testVM.toggleMultiSelectMode()
        testVM.selectNotes(Set(testVM.track.notes.map { $0.id }))
        
        // Copy
        testVM.copySelectedNotes()
        
        // Clear and set playhead to 0.0
        let originalIds = testVM.track.notes.map { $0.id }
        for id in originalIds { testVM.deleteNote(id) }
        testVM.currentBeat = 0.0
        
        // Paste
        testVM.pasteNotes()
        
        let pastedNotes = testVM.track.notes.sorted { $0.startBeat < $1.startBeat }
        
        // Notes should be at: 0.0, 2.5, 5.0 (relative to leftmost at 5.0)
        XCTAssertEqual(pastedNotes.count, 3)
        XCTAssertEqual(pastedNotes[0].startBeat, 0.0, accuracy: 0.001)
        XCTAssertEqual(pastedNotes[1].startBeat, 2.5, accuracy: 0.001)
        XCTAssertEqual(pastedNotes[2].startBeat, 5.0, accuracy: 0.001)
    }
    
    func testCopyPasteSingleNote() {
        // Single note should paste at playhead position
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 3.0, durationBeats: 1.0)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        
        // Select the single note (single select mode)
        testVM.selectNote(testVM.track.notes[0].id)
        
        // Copy
        testVM.copySelectedNotes()
        
        // Clear and set playhead
        testVM.deleteNote(testVM.track.notes[0].id)
        testVM.currentBeat = 8.0
        
        // Paste
        testVM.pasteNotes()
        
        XCTAssertEqual(testVM.track.notes.count, 1)
        XCTAssertEqual(testVM.track.notes[0].startBeat, 8.0, accuracy: 0.001)
        XCTAssertEqual(testVM.track.notes[0].pitch, 60)
        XCTAssertEqual(testVM.track.notes[0].durationBeats, 1.0, accuracy: 0.001)
    }
    
    func testCannotPasteWithEmptyClipboard() {
        XCTAssertFalse(focusVM.canPaste)
    }
    
    func testCanCopyWithSelection() {
        // No selection = cannot copy
        XCTAssertFalse(focusVM.canCopy)
        
        // With selection = can copy
        focusVM.selectNote(focusVM.track.notes[0].id)
        XCTAssertTrue(focusVM.canCopy)
    }
    
    // MARK: - Note Preview Tests
    
    func testAddNoteTriggersPreview() {
        // Adding a note should not crash even without audio engine initialized
        // The preview is triggered inside addNote
        let initialCount = focusVM.track.notes.count
        
        focusVM.addNote(pitch: 72, startBeat: 1.0, duration: 0.5, velocity: 90)
        
        // Note should be added
        XCTAssertEqual(focusVM.track.notes.count, initialCount + 1)
        
        // Find the new note
        let newNote = focusVM.track.notes.first { $0.pitch == 72 }
        XCTAssertNotNil(newNote)
        XCTAssertEqual(newNote?.velocity, 90)
    }
    
    func testAddDrumNoteTriggersPreview() {
        // Test with a drum track
        let drumTrack = Track(
            instrumentName: "Drums",
            instrumentProgram: 0,
            isDrumKit: true,
            notes: []
        )
        let drumFocusVM = TrackFocusViewModel(track: drumTrack, looperVM: looperVM)
        
        // Adding drum hit should work without crashing
        drumFocusVM.addNote(pitch: 36, startBeat: 0, duration: 0.25, velocity: 100)
        
        XCTAssertEqual(drumFocusVM.track.notes.count, 1)
        XCTAssertEqual(drumFocusVM.track.notes[0].pitch, 36) // Kick drum
    }
    
    func testAddNoteWithDifferentVelocities() {
        // Test that different velocities are preserved (for preview volume)
        // Use pitches that don't conflict with existing notes in the fixture
        focusVM.addNote(pitch: 72, startBeat: 6.0, duration: 0.5, velocity: 127)
        focusVM.addNote(pitch: 74, startBeat: 7.0, duration: 0.5, velocity: 64)
        focusVM.addNote(pitch: 76, startBeat: 8.0, duration: 0.5, velocity: 32)
        
        let loudNote = focusVM.track.notes.first { $0.pitch == 72 && $0.startBeat == 6.0 }
        let medNote = focusVM.track.notes.first { $0.pitch == 74 && $0.startBeat == 7.0 }
        let softNote = focusVM.track.notes.first { $0.pitch == 76 && $0.startBeat == 8.0 }
        
        XCTAssertEqual(loudNote?.velocity, 127)
        XCTAssertEqual(medNote?.velocity, 64)
        XCTAssertEqual(softNote?.velocity, 32)
    }
    
    // MARK: - Multi-Drag Tests
    
    func testMultiDragPreservesRelativePositions() {
        // Create track with notes at known positions
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 0.5),
                MidiNote(pitch: 64, velocity: 100, startBeat: 2.0, durationBeats: 0.5),
                MidiNote(pitch: 67, velocity: 100, startBeat: 3.0, durationBeats: 0.5)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        
        // Enable multi-select and select all notes
        testVM.toggleMultiSelectMode()
        let noteIds = Set(testVM.track.notes.map { $0.id })
        testVM.selectNotes(noteIds)
        
        // Begin multi-drag
        testVM.beginMultiDrag()
        XCTAssertTrue(testVM.isMultiDragging)
        XCTAssertEqual(testVM.multiDragStartPositions.count, 3)
        
        // Update drag position (move 2 beats to the right, 2 semitones up)
        testVM.updateMultiDragPosition(deltaBeats: 2.0, deltaPitch: 2)
        
        // End the drag
        testVM.endMultiDrag()
        
        // Verify all notes moved by the same delta
        let movedNotes = testVM.track.notes.sorted { $0.startBeat < $1.startBeat }
        
        // Notes should now be at 3.0, 4.0, 5.0 (each moved +2 beats)
        XCTAssertEqual(movedNotes[0].startBeat, 3.0, accuracy: 0.001)
        XCTAssertEqual(movedNotes[1].startBeat, 4.0, accuracy: 0.001)
        XCTAssertEqual(movedNotes[2].startBeat, 5.0, accuracy: 0.001)
        
        // Pitches should be 62, 66, 69 (each +2 semitones)
        XCTAssertEqual(movedNotes[0].pitch, 62)
        XCTAssertEqual(movedNotes[1].pitch, 66)
        XCTAssertEqual(movedNotes[2].pitch, 69)
    }
    
    func testMultiDragPreviewPositions() {
        // Create track with notes
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 0.5),
                MidiNote(pitch: 64, velocity: 100, startBeat: 1.0, durationBeats: 0.5)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        
        // Enable multi-select and select all
        testVM.toggleMultiSelectMode()
        testVM.selectNotes(Set(testVM.track.notes.map { $0.id }))
        
        // Begin multi-drag
        testVM.beginMultiDrag()
        
        // Update position
        testVM.updateMultiDragPosition(deltaBeats: 1.5, deltaPitch: -3)
        
        // Check preview positions for each note
        let note1 = testVM.track.notes[0]
        let note2 = testVM.track.notes[1]
        
        let preview1 = testVM.multiDragPreviewPosition(for: note1.id)
        let preview2 = testVM.multiDragPreviewPosition(for: note2.id)
        
        XCTAssertNotNil(preview1)
        XCTAssertNotNil(preview2)
        
        // First note: 0.0 + 1.5 = 1.5, pitch 60 - 3 = 57
        XCTAssertEqual(preview1?.startBeat ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(preview1?.pitch, 57)
        
        // Second note: 1.0 + 1.5 = 2.5, pitch 64 - 3 = 61
        XCTAssertEqual(preview2?.startBeat ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(preview2?.pitch, 61)
        
        // Cancel to clean up
        testVM.cancelMultiDrag()
        XCTAssertFalse(testVM.isMultiDragging)
    }
    
    func testBackgroundLockedWithMultiSelectNotes() {
        // Test that background is locked when notes are selected in multi-select mode
        focusVM.toggleMultiSelectMode()
        XCTAssertFalse(focusVM.isBackgroundLocked) // No notes selected yet
        
        // Select a note
        focusVM.toggleNoteSelection(focusVM.track.notes[0].id)
        XCTAssertTrue(focusVM.isBackgroundLocked) // Should be locked now
        
        // Deselect the note
        focusVM.toggleNoteSelection(focusVM.track.notes[0].id)
        XCTAssertFalse(focusVM.isBackgroundLocked) // Should be unlocked
    }
    
    func testMultiDragWithGridSnapping() {
        let testTrack = Track(
            instrumentName: "Piano",
            instrumentProgram: 0,
            isDrumKit: false,
            notes: [
                MidiNote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 0.5),
                MidiNote(pitch: 64, velocity: 100, startBeat: 1.0, durationBeats: 0.5)
            ]
        )
        let testVM = TrackFocusViewModel(track: testTrack, looperVM: looperVM)
        testVM.gridStep = 0.5 // Half-note grid
        
        // Enable multi-select and select all
        testVM.toggleMultiSelectMode()
        testVM.selectNotes(Set(testVM.track.notes.map { $0.id }))
        
        // Begin multi-drag
        testVM.beginMultiDrag()
        
        // Update with non-grid delta (0.3 should snap to 0.5)
        testVM.updateMultiDragPosition(deltaBeats: 0.3, deltaPitch: 0)
        
        // The delta should be snapped
        XCTAssertEqual(testVM.multiDragDeltaBeats, 0.5, accuracy: 0.001)
        
        testVM.cancelMultiDrag()
    }
    
    func testDeselectAllClearsMultiDragState() {
        focusVM.toggleMultiSelectMode()
        focusVM.selectNotes(Set(focusVM.track.notes.map { $0.id }))
        focusVM.beginMultiDrag()
        
        XCTAssertTrue(focusVM.isMultiDragging)
        XCTAssertFalse(focusVM.multiDragStartPositions.isEmpty)
        
        focusVM.deselectAll()
        
        XCTAssertFalse(focusVM.isMultiDragging)
        XCTAssertTrue(focusVM.multiDragStartPositions.isEmpty)
        XCTAssertTrue(focusVM.selectedNoteIds.isEmpty)
    }
}

