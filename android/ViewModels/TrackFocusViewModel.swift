import SwiftUI
import Combine

/// Edge used for resizing notes
enum HorizontalEdge {
    case leading
    case trailing
}

/// ViewModel for the Track Focus piano roll editor
@MainActor
final class TrackFocusViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let looperVM: LooperViewModel
    let trackId: UUID
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published State (including forwarded from looperVM)
    
    @Published var isPlaying: Bool = false
    @Published var currentBeat: Double = 0
    @Published var track: Track
    @Published var selectedNoteId: UUID? = nil
    @Published var selectedNoteIds: Set<UUID> = []  // For multi-select
    @Published var isMultiSelectMode = false  // Toggle for multi-select
    @Published var gridStep: Double = 0 // Default OFF (no grid snapping)
    @Published var showingQuantizeSheet = false
    @Published var hideEmptyDrumRows = false  // Toggle for hiding empty drum rows
    
    // Minimum note duration (used when gridStep is off/0)
    private let minNoteDuration: Double = 0.125  // 1/32 note as minimum
    
    // MARK: - Undo Stack
    
    private var undoStack: [[MidiNote]] = []
    private let maxUndoSteps = 50
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    // MARK: - Editing State
    
    /// Note being actively dragged
    @Published var draggedNoteId: UUID? = nil
    
    /// Whether we're resizing (true) or moving (false) the dragged note
    @Published var isResizing = false
    
    /// Which edge is being resized: .leading (left) or .trailing (right)
    @Published var resizeEdge: HorizontalEdge = .trailing
    
    /// Preview of where the note would end up during drag
    @Published var dragPreviewStartBeat: Double? = nil
    @Published var dragPreviewDuration: Double? = nil
    @Published var dragPreviewPitch: UInt8? = nil
    
    /// Resize mode - when true, dragging resizes instead of moves
    @Published var isResizeMode = false
    
    /// Add notes mode - when true, tapping empty space adds a note
    @Published var isAddNoteMode = false
    
    /// Delete mode - when true, tapping a note deletes it immediately
    @Published var isDeleteMode = false
    
    /// Last selected note duration (for new notes)
    @Published var lastNoteDuration: Double = 0.25
    
    // MARK: - Multi-Drag State
    
    /// Whether we're currently dragging multiple notes
    @Published var isMultiDragging = false
    
    /// Starting positions of all notes being dragged (captured at drag start)
    var multiDragStartPositions: [UUID: (startBeat: Double, pitch: UInt8)] = [:]
    
    /// Delta values for multi-drag preview (applied to all selected notes)
    @Published var multiDragDeltaBeats: Double = 0
    @Published var multiDragDeltaPitch: Int = 0
    
    // MARK: - Background Lock State (for tap-to-select-then-drag)
    
    /// When true, the ScrollView is locked and only the selected item can be dragged
    /// Computed based on selection state - true when any note or playhead is selected
    var isBackgroundLocked: Bool {
        selectedNoteId != nil || 
        isPlayheadSelected || 
        (isMultiSelectMode && !selectedNoteIds.isEmpty)
    }
    
    /// When true, the playhead is selected (for dragging)
    @Published var isPlayheadSelected: Bool = false
    
    /// Clipboard for copied notes (relative to first note's position)
    private var copiedNotes: [MidiNote] = []
    private var copyBaseStartBeat: Double = 0  // Reference point for paste
    
    /// Horizontal zoom level (1.0 = default, 2.0 = zoomed in 2x)
    @Published var zoomLevel: CGFloat = 1.0
    
    /// Vertical zoom level (1.0 = default, scales row height)
    @Published var verticalZoomLevel: CGFloat = 1.0
    
    /// Min/max zoom limits
    let minZoom: CGFloat = 0.5
    let maxZoom: CGFloat = 4.0
    let minVerticalZoom: CGFloat = 0.6
    let maxVerticalZoom: CGFloat = 2.5
    
    // MARK: - Computed Properties
    
    var loopLengthBeats: Double {
        looperVM.loopLengthBeats
    }
    
    /// The track's own recorded length (used for drum grid and playhead sync)
    var trackLengthBeats: Double {
        track.recordedLengthBeats
    }
    
    var bpm: Double {
        looperVM.bpm
    }
    
    var selectedNote: MidiNote? {
        guard let id = selectedNoteId else { return nil }
        return track.notes.first { $0.id == id }
    }
    
    /// Minimum and maximum pitch in the track (for piano roll range)
    var pitchRange: ClosedRange<UInt8> {
        guard !track.notes.isEmpty else {
            return 48...72 // Default 2 octaves from C3
        }
        let minPitch = track.notes.map(\.pitch).min() ?? 48
        let maxPitch = track.notes.map(\.pitch).max() ?? 72
        // Add some padding
        let paddedMin = max(0, Int(minPitch) - 4)
        let paddedMax = min(127, Int(maxPitch) + 4)
        return UInt8(paddedMin)...UInt8(paddedMax)
    }
    
    // MARK: - Initialization
    
    init(track: Track, looperVM: LooperViewModel) {
        self.track = track
        self.trackId = track.id
        self.looperVM = looperVM
        
        // Subscribe to looperVM changes to forward to @Published properties
        setupBindings()
    }
    
    private func setupBindings() {
        // Forward isPlaying changes
        looperVM.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
            }
            .store(in: &cancellables)
        
        // Forward currentPosition changes (throttled to reduce load)
        // NOTE: currentPosition is in SECONDS, we need to convert to BEATS for the playhead
        looperVM.$currentPosition
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true) // ~60fps
            .sink { [weak self] positionInSeconds in
                guard let self = self else { return }
                // Convert seconds to beats: beats = seconds * (bpm / 60)
                let secondsPerBeat = 60.0 / self.looperVM.bpm
                let positionInBeats = positionInSeconds / secondsPerBeat
                self.currentBeat = positionInBeats
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Undo
    
    /// Save current state before making an edit
    func saveUndoState() {
        undoStack.append(track.notes)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
    }
    
    /// Undo the last edit
    func undo() {
        guard let previousNotes = undoStack.popLast() else { return }
        track.notes = previousNotes
        selectedNoteId = nil
        syncToLooper()
        HapticManager.shared.selectionChanged()
    }
    
    // MARK: - Note Selection
    
    func selectNote(_ noteId: UUID?) {
        selectedNoteId = noteId
        isPlayheadSelected = false  // Deselect playhead when selecting a note
        // Track the duration of selected note for new notes
        if let noteId = noteId,
           let note = track.notes.first(where: { $0.id == noteId }) {
            lastNoteDuration = note.durationBeats
        }
        HapticManager.shared.selectionChanged()
    }
    
    func deselectNote() {
        selectedNoteId = nil
        isResizeMode = false
    }
    
    /// Select the playhead for dragging
    func selectPlayhead() {
        selectedNoteId = nil
        isPlayheadSelected = true
        HapticManager.shared.selectionChanged()
    }
    
    /// Deselect everything and unlock background
    func deselectAll() {
        selectedNoteId = nil
        selectedNoteIds.removeAll()
        isPlayheadSelected = false
        isResizeMode = false
        clearMultiDragState()
    }
    
    /// Toggle resize mode for the selected note
    func toggleResizeMode() {
        guard selectedNoteId != nil else { return }
        isResizeMode.toggle()
        HapticManager.shared.selectionChanged()
    }
    
    /// Exit resize mode
    func exitResizeMode() {
        isResizeMode = false
    }
    
    /// Toggle add note mode (mutually exclusive with delete mode)
    func toggleAddNoteMode() {
        isAddNoteMode.toggle()
        if isAddNoteMode {
            isDeleteMode = false
            isResizeMode = false
        }
        HapticManager.shared.selectionChanged()
    }
    
    /// Toggle delete mode (mutually exclusive with add note mode)
    func toggleDeleteMode() {
        isDeleteMode.toggle()
        if isDeleteMode {
            isAddNoteMode = false
            isResizeMode = false
        }
        HapticManager.shared.selectionChanged()
    }
    
    /// Exit all special modes
    func exitAllModes() {
        isAddNoteMode = false
        isDeleteMode = false
        isResizeMode = false
        isMultiSelectMode = false
    }
    
    // MARK: - Multi-Select
    
    /// Toggle multi-select mode
    func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            // Keep the single selected note if any
            if let firstSelected = selectedNoteIds.first {
                selectedNoteId = firstSelected
            }
            selectedNoteIds.removeAll()
        } else {
            // Add current selection to multi-select
            if let currentId = selectedNoteId {
                selectedNoteIds.insert(currentId)
            }
            isAddNoteMode = false
            isDeleteMode = false
            isResizeMode = false
        }
        HapticManager.shared.selectionChanged()
    }
    
    /// Toggle selection for a note in multi-select mode
    func toggleNoteSelection(_ noteId: UUID) {
        if selectedNoteIds.contains(noteId) {
            selectedNoteIds.remove(noteId)
        } else {
            selectedNoteIds.insert(noteId)
        }
        // Update single selection to last selected
        selectedNoteId = selectedNoteIds.first
        HapticManager.shared.selectionChanged()
    }
    
    /// Select multiple notes at once (for selection box)
    func selectNotes(_ noteIds: Set<UUID>) {
        selectedNoteIds = noteIds
        selectedNoteId = noteIds.first
        HapticManager.shared.selectionChanged()
    }
    
    /// Clear all selection
    func clearSelection() {
        selectedNoteIds.removeAll()
        selectedNoteId = nil
    }
    
    /// Check if a note is selected (works in both modes)
    func isNoteSelected(_ noteId: UUID) -> Bool {
        if isMultiSelectMode {
            return selectedNoteIds.contains(noteId)
        } else {
            return selectedNoteId == noteId
        }
    }
    
    /// Get all currently selected notes
    var selectedNotes: [MidiNote] {
        if isMultiSelectMode {
            return track.notes.filter { selectedNoteIds.contains($0.id) }
        } else if let id = selectedNoteId {
            return track.notes.filter { $0.id == id }
        }
        return []
    }
    
    // MARK: - Copy & Paste
    
    /// Copy selected notes to clipboard
    func copySelectedNotes() {
        let notesToCopy = selectedNotes
        guard !notesToCopy.isEmpty else { return }
        
        // Sort by start beat and find the earliest note
        let sorted = notesToCopy.sorted { $0.startBeat < $1.startBeat }
        copyBaseStartBeat = sorted.first?.startBeat ?? 0
        
        // Store notes with relative positions
        copiedNotes = sorted.map { note in
            MidiNote(
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: note.startBeat - copyBaseStartBeat,  // Relative to first note
                durationBeats: note.durationBeats
            )
        }
        
        HapticManager.shared.selectionChanged()
    }
    
    /// Paste notes from clipboard at the current playhead position
    func pasteNotes() {
        guard !copiedNotes.isEmpty else { return }
        
        saveUndoState()
        
        let pastePosition = currentBeat
        var newNoteIds: Set<UUID> = []
        
        for note in copiedNotes {
            let newStartBeat = pastePosition + note.startBeat
            
            // Only add if it fits within the loop
            guard newStartBeat >= 0 && newStartBeat + note.durationBeats <= loopLengthBeats else { continue }
            
            let newNote = MidiNote(
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: newStartBeat,
                durationBeats: note.durationBeats
            )
            track.notes.append(newNote)
            newNoteIds.insert(newNote.id)
        }
        
        track.notes.sort { $0.startBeat < $1.startBeat }
        
        // Select the newly pasted notes
        if isMultiSelectMode {
            selectedNoteIds = newNoteIds
        }
        selectedNoteId = newNoteIds.first
        
        syncToLooper()
        HapticManager.shared.selectionChanged()
    }
    
    /// Check if there are notes to paste
    var canPaste: Bool {
        !copiedNotes.isEmpty
    }
    
    /// Check if there are notes selected to copy
    var canCopy: Bool {
        !selectedNotes.isEmpty
    }
    
    // MARK: - Zoom
    
    /// Set zoom level with bounds checking
    func setZoom(_ level: CGFloat) {
        zoomLevel = max(minZoom, min(maxZoom, level))
    }
    
    /// Zoom in by a factor
    func zoomIn() {
        setZoom(zoomLevel * 1.25)
    }
    
    /// Zoom out by a factor
    func zoomOut() {
        setZoom(zoomLevel / 1.25)
    }
    
    /// Reset zoom to default
    func resetZoom() {
        zoomLevel = 1.0
        verticalZoomLevel = 1.0
    }
    
    // MARK: - Vertical Zoom
    
    /// Set vertical zoom level with bounds checking
    func setVerticalZoom(_ level: CGFloat) {
        verticalZoomLevel = max(minVerticalZoom, min(maxVerticalZoom, level))
    }
    
    /// Zoom in vertically
    func zoomInVertical() {
        setVerticalZoom(verticalZoomLevel * 1.25)
    }
    
    /// Zoom out vertically
    func zoomOutVertical() {
        setVerticalZoom(verticalZoomLevel / 1.25)
    }
    
    // MARK: - Note Movement
    
    func moveNote(_ noteId: UUID, toStartBeat newStartBeat: Double, toPitch newPitch: UInt8? = nil) {
        guard let index = track.notes.firstIndex(where: { $0.id == noteId }) else { return }
        
        saveUndoState()
        
        let note = track.notes[index]
        
        // Snap to grid and clamp to loop bounds
        let snappedBeat = snapToGrid(newStartBeat)
        let clampedBeat = clampStartBeat(snappedBeat, duration: note.durationBeats)
        
        track.notes[index].startBeat = clampedBeat
        
        // Update pitch if provided
        if let pitch = newPitch {
            track.notes[index].pitch = max(0, min(127, pitch))
        }
        
        syncToLooper()
    }
    
    // MARK: - Note Resizing
    
    func resizeNote(_ noteId: UUID, toDuration newDuration: Double, newStartBeat: Double? = nil) {
        guard let index = track.notes.firstIndex(where: { $0.id == noteId }) else { return }
        
        saveUndoState()
        
        // Snap to grid and clamp
        let snappedDuration = snapToGrid(newDuration)
        let startBeat = newStartBeat ?? track.notes[index].startBeat
        let clampedDuration = clampDuration(snappedDuration, startBeat: startBeat)
        
        track.notes[index].durationBeats = max(gridStep > 0 ? gridStep : minNoteDuration, clampedDuration)
        
        // Update start beat if resizing from left edge
        if let newStart = newStartBeat {
            track.notes[index].startBeat = max(0, snapToGrid(newStart))
        }
        
        syncToLooper()
    }
    
    // MARK: - Note Deletion
    
    func deleteNote(_ noteId: UUID) {
        saveUndoState()
        track.notes.removeAll { $0.id == noteId }
        if selectedNoteId == noteId {
            selectedNoteId = nil
        }
        syncToLooper()
        HapticManager.shared.warning()
    }
    
    // MARK: - Note Addition
    
    func addNote(pitch: UInt8, startBeat: Double, duration: Double = 0.25, velocity: UInt8 = 100) {
        saveUndoState()
        
        let snappedStart = snapToGrid(startBeat)
        let snappedDuration = max(gridStep > 0 ? gridStep : minNoteDuration, snapToGrid(duration))
        
        let note = MidiNote(
            pitch: pitch,
            velocity: velocity,
            startBeat: clampStartBeat(snappedStart, duration: snappedDuration),
            durationBeats: clampDuration(snappedDuration, startBeat: snappedStart)
        )
        
        track.notes.append(note)
        track.notes.sort { $0.startBeat < $1.startBeat }
        selectedNoteId = note.id
        syncToLooper()
        
        // Play preview sound for the added note
        looperVM.previewNote(pitch: pitch, velocity: velocity, trackId: trackId)
        
        HapticManager.shared.selectionChanged()
    }
    
    // MARK: - Quantization
    
    func quantizeTrack(division: QuantizeDivision) {
        saveUndoState()
        let quantizer = Quantizer(bpm: bpm, division: division)
        track.notes = quantizer.quantize(notes: track.notes, loopLengthBeats: loopLengthBeats)
        syncToLooper()
        HapticManager.shared.selectionChanged()
    }
    
    func setGridStep(_ division: QuantizeDivision) {
        gridStep = division.beatFraction ?? 0  // 0 = no grid snapping (off)
    }
    
    // MARK: - Instrument Change
    
    func setInstrument(_ instrument: Instrument) {
        track.instrumentName = instrument.rawValue
        track.instrumentProgram = instrument.programNumber
        looperVM.setTrackInstrument(track, instrument: instrument)
    }
    
    // MARK: - Transport Controls
    
    func togglePlayback() {
        looperVM.togglePlayPause()
    }
    
    func restart() {
        looperVM.restartPlayback()
    }
    
    func seekTo(beat: Double) {
        let clampedBeat = max(0, min(beat, loopLengthBeats))
        // Convert beats to seconds for the looper (which uses seconds internally)
        let secondsPerBeat = 60.0 / looperVM.bpm
        let positionInSeconds = clampedBeat * secondsPerBeat
        looperVM.seekToPosition(positionInSeconds)
    }
    
    // MARK: - Grid Snapping
    
    func snapToGrid(_ beat: Double) -> Double {
        return Quantizer.snap(beat, toGrid: gridStep)
    }
    
    func clampStartBeat(_ beat: Double, duration: Double) -> Double {
        let minBeat: Double = 0
        let maxBeat = loopLengthBeats - duration
        return max(minBeat, min(beat, maxBeat))
    }
    
    func clampDuration(_ duration: Double, startBeat: Double) -> Double {
        return Quantizer.clampDuration(duration, startBeat: startBeat, loopLengthBeats: loopLengthBeats, gridStep: gridStep)
    }
    
    // MARK: - Drag Handling
    
    func beginDrag(noteId: UUID, isResizing: Bool, resizeEdge: HorizontalEdge = .trailing) {
        draggedNoteId = noteId
        self.isResizing = isResizing
        self.resizeEdge = resizeEdge
        
        if let note = track.notes.first(where: { $0.id == noteId }) {
            dragPreviewStartBeat = note.startBeat
            dragPreviewDuration = note.durationBeats
            dragPreviewPitch = note.pitch
        }
    }
    
    func updateDragPosition(newStartBeat: Double, newPitch: UInt8) {
        dragPreviewStartBeat = max(0, snapToGrid(newStartBeat))
        dragPreviewPitch = max(0, min(127, newPitch))
    }
    
    func updateDragResize(newDuration: Double, newStartBeat: Double? = nil) {
        dragPreviewDuration = max(gridStep > 0 ? gridStep : minNoteDuration, snapToGrid(newDuration))
        if let start = newStartBeat {
            dragPreviewStartBeat = max(0, snapToGrid(start))
        }
    }
    
    func endDrag() {
        guard let noteId = draggedNoteId else { return }
        
        if isResizing {
            if let duration = dragPreviewDuration {
                // For left edge resize, also update start beat
                let newStart = resizeEdge == .leading ? dragPreviewStartBeat : nil
                resizeNote(noteId, toDuration: duration, newStartBeat: newStart)
            }
        } else {
            if let startBeat = dragPreviewStartBeat {
                moveNote(noteId, toStartBeat: startBeat, toPitch: dragPreviewPitch)
            }
        }
        
        clearDragState()
    }
    
    func cancelDrag() {
        clearDragState()
    }
    
    private func clearDragState() {
        draggedNoteId = nil
        dragPreviewStartBeat = nil
        dragPreviewDuration = nil
        dragPreviewPitch = nil
        isResizing = false
        resizeEdge = .trailing
    }
    
    // MARK: - Multi-Drag Handling
    
    /// Begin dragging multiple selected notes
    func beginMultiDrag() {
        guard isMultiSelectMode && !selectedNoteIds.isEmpty else { return }
        
        isMultiDragging = true
        multiDragDeltaBeats = 0
        multiDragDeltaPitch = 0
        
        // Capture starting positions of all selected notes
        multiDragStartPositions.removeAll()
        for noteId in selectedNoteIds {
            if let note = track.notes.first(where: { $0.id == noteId }) {
                multiDragStartPositions[noteId] = (startBeat: note.startBeat, pitch: note.pitch)
            }
        }
    }
    
    /// Update multi-drag preview with delta from start position
    func updateMultiDragPosition(deltaBeats: Double, deltaPitch: Int) {
        multiDragDeltaBeats = snapToGrid(deltaBeats)
        multiDragDeltaPitch = deltaPitch
    }
    
    /// Get preview position for a note during multi-drag
    func multiDragPreviewPosition(for noteId: UUID) -> (startBeat: Double, pitch: UInt8)? {
        guard isMultiDragging,
              let startPos = multiDragStartPositions[noteId] else { return nil }
        
        let newStartBeat = max(0, startPos.startBeat + multiDragDeltaBeats)
        let newPitch = max(0, min(127, Int(startPos.pitch) + multiDragDeltaPitch))
        
        return (startBeat: newStartBeat, pitch: UInt8(newPitch))
    }
    
    /// Commit multi-drag - move all selected notes by the delta
    func endMultiDrag() {
        guard isMultiDragging else { return }
        
        saveUndoState()
        
        // Apply delta to all selected notes
        for noteId in selectedNoteIds {
            guard let startPos = multiDragStartPositions[noteId],
                  let index = track.notes.firstIndex(where: { $0.id == noteId }) else { continue }
            
            let note = track.notes[index]
            
            // Calculate new position
            let newStartBeat = startPos.startBeat + multiDragDeltaBeats
            let newPitch = Int(startPos.pitch) + multiDragDeltaPitch
            
            // Clamp values
            let clampedBeat = clampStartBeat(snapToGrid(newStartBeat), duration: note.durationBeats)
            let clampedPitch = UInt8(max(0, min(127, newPitch)))
            
            track.notes[index].startBeat = clampedBeat
            track.notes[index].pitch = clampedPitch
        }
        
        syncToLooper()
        clearMultiDragState()
    }
    
    /// Cancel multi-drag without applying changes
    func cancelMultiDrag() {
        clearMultiDragState()
    }
    
    /// Clear multi-drag state
    private func clearMultiDragState() {
        isMultiDragging = false
        multiDragStartPositions.removeAll()
        multiDragDeltaBeats = 0
        multiDragDeltaPitch = 0
    }
    
    // MARK: - Sync to Looper
    
    private func syncToLooper() {
        looperVM.updateTrack(track)
    }
}

