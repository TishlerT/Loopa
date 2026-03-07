import SwiftUI
import UIKit

// MARK: - Disable Scroll Momentum Modifier

/// A modifier that disables scroll momentum/deceleration in a ScrollView
struct DisableScrollMomentum: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Find and configure UIScrollViews to disable momentum
                DispatchQueue.main.async {
                    for window in UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows }) {
                        disableMomentum(in: window)
                    }
                }
            }
    }
    
    private func disableMomentum(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.decelerationRate = .init(rawValue: 0.99)  // Nearly instant stop
        }
        for subview in view.subviews {
            disableMomentum(in: subview)
        }
    }
}

extension View {
    func disableScrollMomentum() -> some View {
        modifier(DisableScrollMomentum())
    }
}

/// Canvas-based piano roll view for displaying and editing MIDI notes
struct PianoRollCanvasView: View {
    @ObservedObject var vm: TrackFocusViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var isIPad: Bool { sizeClass == .regular }
    
    // Layout constants - scale up for iPad
    private var keyLabelWidth: CGFloat { isIPad ? 100 : 66 }    // Piano key (40) + text label (60) on iPad
    private var baseRowHeight: CGFloat { isIPad ? 48 : 28 }    // Base height, scaled by vertical zoom
    private let handleWidth: CGFloat = 28      // Visual handle width
    private let handleHitWidth: CGFloat = 44   // Larger hit area for easier grabbing
    private let minNoteWidth: CGFloat = 22  // Increased for easier selection
    private let minHitWidth: CGFloat = 30      // Minimum tap target for small notes (reduced from 44 for accuracy)
    private let blackKeyWidthRatio: CGFloat = 0.65  // Black keys are narrower
    
    // Piano key label sizes
    private var pianoKeyWidth: CGFloat { isIPad ? 40 : 26 }
    private var textLabelWidth: CGFloat { isIPad ? 60 : 40 }
    private var cNoteFontSize: CGFloat { isIPad ? 14 : 10 }
    private var otherNoteFontSize: CGFloat { isIPad ? 12 : 9 }
    
    // State for drag tracking
    @State private var dragStartLocation: CGPoint? = nil
    @State private var dragStartNoteState: (startBeat: Double, duration: Double, pitch: UInt8)? = nil
    
    // State to track if we're actively dragging a note (controls scroll lock)
    @State private var isNoteDragActive = false
    
    // State for playhead dragging
    @State private var isDraggingPlayhead = false
    @State private var playheadDragBeat: Double? = nil
    // Playhead hit area - tighter on iPad to reduce accidental selection
    private var playheadHitWidth: CGFloat { isIPad ? 20 : 30 }
    
    // State for pinch-to-zoom
    @State private var currentMagnification: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    
    // State for auto-scroll (passed via closure from ScrollViewReader)
    @State private var autoScrollToPitch: UInt8? = nil
    
    /// Computed row height based on vertical zoom
    private var rowHeight: CGFloat {
        baseRowHeight * vm.verticalZoomLevel
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let baseGridWidth = size.width - keyLabelWidth
            let zoomedGridWidth = baseGridWidth * vm.zoomLevel
            let gridWidth = max(zoomedGridWidth, 400)  // Minimum width
            let pitchRange = vm.pitchRange
            let pitchCount = Int(pitchRange.upperBound - pitchRange.lowerBound) + 1
            let scaledRowHeight = rowHeight  // Capture computed property for local use
            let totalHeight = CGFloat(pitchCount) * scaledRowHeight
            
            ScrollViewReader { scrollProxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        // Piano key labels (fixed on left)
                        VStack(spacing: 0) {
                            ForEach((pitchRange).reversed(), id: \.self) { pitch in
                                keyLabel(for: pitch)
                                    .frame(width: keyLabelWidth, height: scaledRowHeight)
                                    .id("pitch_\(pitch)")  // Add ID for scrolling
                            }
                        }
                        .frame(width: keyLabelWidth)
                        
                        // Canvas for grid, notes, and playhead
                        Canvas { context, canvasSize in
                            drawGrid(context: context, size: canvasSize, pitchRange: pitchRange, rowHeight: scaledRowHeight)
                            drawNotes(context: context, size: canvasSize, pitchRange: pitchRange, rowHeight: scaledRowHeight)
                            drawPlayhead(context: context, size: canvasSize)
                        }
                        .frame(width: gridWidth, height: totalHeight)
                    }
                    .frame(width: gridWidth + keyLabelWidth, height: totalHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(createDragGesture(gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: scaledRowHeight))
                    .simultaneousGesture(createLongPressGesture(gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: scaledRowHeight))
                    .simultaneousGesture(createDoubleTapGesture(gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: scaledRowHeight))
                    .simultaneousGesture(createTapGesture(gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: scaledRowHeight))
                }
                .scrollDisabled(isNoteDragActive)  // Only lock scroll during active note/playhead drag
                .scrollBounceBehavior(.basedOnSize)  // Reduce bounce
                .scrollIndicatorsFlash(onAppear: false)
                .disableScrollMomentum()  // Stop immediately when finger lifts
                .simultaneousGesture(createMagnificationGesture())
                .onAppear {
                    // Scroll to middle C (C4 = pitch 60) on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scrollProxy.scrollTo("pitch_60", anchor: .center)
                        }
                    }
                }
                .onChange(of: autoScrollToPitch) { _, newPitch in
                    // Auto-scroll to pitch when dragging note near edge
                    if let pitch = newPitch {
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollProxy.scrollTo("pitch_\(pitch)", anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(hex: "0D0D1A"))
    }
    
    // MARK: - Magnification Gesture (Pinch-to-Zoom)
    
    private func createMagnificationGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = lastMagnification * value.magnification
                vm.setZoom(newZoom)
            }
            .onEnded { value in
                lastMagnification = vm.zoomLevel
            }
    }
    
    // MARK: - Drawing
    
    private func drawGrid(context: GraphicsContext, size: CGSize, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) {
        let pitchCount = Int(pitchRange.upperBound - pitchRange.lowerBound) + 1
        
        // Horizontal lines (pitch rows)
        for i in 0...pitchCount {
            let y = CGFloat(i) * rowHeight
            let pitch = pitchRange.upperBound - UInt8(min(i, pitchCount - 1))
            let isBlackKey = [1, 3, 6, 8, 10].contains(Int(pitch) % 12)
            
            // Row background
            if i < pitchCount {
                let rowRect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
                context.fill(
                    Path(rowRect),
                    with: .color(isBlackKey ? Color.white.opacity(0.03) : Color.white.opacity(0.01))
                )
            }
            
            // Horizontal line
            var linePath = Path()
            linePath.move(to: CGPoint(x: 0, y: y))
            linePath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(linePath, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
        }
        
        // Vertical lines (beat grid)
        // Use gridStep if set, otherwise default to 0.25 (sixteenth notes) for visual grid
        let gridStep = vm.gridStep > 0 ? vm.gridStep : 0.25
        var beat: Double = 0
        while beat <= vm.loopLengthBeats {
            let x = CGFloat(beat / vm.loopLengthBeats) * size.width
            let isDownbeat = beat.truncatingRemainder(dividingBy: 4) == 0
            let isBeat = beat.truncatingRemainder(dividingBy: 1) == 0
            
            var linePath = Path()
            linePath.move(to: CGPoint(x: x, y: 0))
            linePath.addLine(to: CGPoint(x: x, y: size.height))
            
            let lineColor: Color = isDownbeat ? .white.opacity(0.3) : (isBeat ? .white.opacity(0.15) : .white.opacity(0.05))
            context.stroke(linePath, with: .color(lineColor), lineWidth: isDownbeat ? 1 : 0.5)
            
            beat += gridStep
        }
    }
    
    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        // Use drag position if dragging, otherwise current beat
        let displayBeat = playheadDragBeat ?? vm.currentBeat
        let x = CGFloat(displayBeat / vm.loopLengthBeats) * size.width
        
        // Determine if playhead is selected or being dragged
        let isSelected = vm.isPlayheadSelected || isDraggingPlayhead
        
        // Playhead line
        var linePath = Path()
        linePath.move(to: CGPoint(x: x, y: 0))
        linePath.addLine(to: CGPoint(x: x, y: size.height))
        
        // Cyan/teal color for playhead, brighter when selected
        let playheadColor = isSelected ? Color(hex: "00FFFF") : Color(hex: "00FFCC")
        let lineWidth: CGFloat = isSelected ? 3 : 2
        context.stroke(linePath, with: .color(playheadColor), lineWidth: lineWidth)
        
        // Playhead handle at top (triangle/diamond shape) - larger when selected
        let handleSize: CGFloat = isSelected ? 16 : 12
        var handlePath = Path()
        handlePath.move(to: CGPoint(x: x, y: 0))
        handlePath.addLine(to: CGPoint(x: x - handleSize/2, y: handleSize))
        handlePath.addLine(to: CGPoint(x: x + handleSize/2, y: handleSize))
        handlePath.closeSubpath()
        context.fill(handlePath, with: .color(playheadColor))
        
        // Glow effect when selected or dragging
        if isSelected {
            context.stroke(linePath, with: .color(playheadColor.opacity(0.3)), lineWidth: 8)
        }
    }
    
    private func drawNotes(context: GraphicsContext, size: CGSize, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) {
        let pitchCount = Int(pitchRange.upperBound - pitchRange.lowerBound) + 1
        
        for note in vm.track.notes {
            // Calculate base note position
            var displayBeat = note.startBeat
            var displayDuration = note.durationBeats
            var displayPitch = note.pitch
            
            // Check if this note is part of a multi-drag
            let isInMultiDrag = vm.isMultiDragging && vm.selectedNoteIds.contains(note.id)
            
            if isInMultiDrag {
                // Use multi-drag preview position
                if let previewPos = vm.multiDragPreviewPosition(for: note.id) {
                    displayBeat = previewPos.startBeat
                    displayPitch = previewPos.pitch
                }
            } else if note.id == vm.draggedNoteId {
                // Use preview values for single dragged note
                if vm.isResizing {
                    if let previewDuration = vm.dragPreviewDuration {
                        displayDuration = previewDuration
                    }
                    if vm.resizeEdge == .leading, let previewStart = vm.dragPreviewStartBeat {
                        displayBeat = previewStart
                    }
                } else {
                    if let previewStart = vm.dragPreviewStartBeat {
                        displayBeat = previewStart
                    }
                    if let previewPitch = vm.dragPreviewPitch {
                        displayPitch = previewPitch
                    }
                }
            }
            
            let x = CGFloat(displayBeat / vm.loopLengthBeats) * size.width
            let width = CGFloat(displayDuration / vm.loopLengthBeats) * size.width
            let pitchOffset = Int(pitchRange.upperBound) - Int(displayPitch)
            
            guard pitchOffset >= 0 && pitchOffset < pitchCount else { continue }
            
            let y = CGFloat(pitchOffset) * rowHeight + 2
            let height = rowHeight - 4
            
            let noteRect = CGRect(
                x: x,
                y: y,
                width: max(minNoteWidth, width),
                height: height
            )
            
            let isSelected = vm.isNoteSelected(note.id)
            let isDragging = note.id == vm.draggedNoteId || isInMultiDrag
            let isInResizeMode = isSelected && vm.isResizeMode
            
            // Note body
            var noteColor: Color = isSelected ? Color(hex: "00FFCC") : Color(hex: "5C7CFA")
            // In multi-select mode, show different color for selected notes
            if vm.isMultiSelectMode && isSelected {
                noteColor = Color(hex: "FFD700")  // Gold for multi-selected
            }
            // In delete mode, show red tint on all notes
            if vm.isDeleteMode {
                noteColor = Color(hex: "FF4444")
            }
            // In resize mode, show orange color to indicate mode
            let displayColor: Color = isInResizeMode ? Color(hex: "FF9500") : noteColor
            let bodyPath = RoundedRectangle(cornerRadius: 4).path(in: noteRect)
            context.fill(
                bodyPath,
                with: .color(displayColor.opacity(isDragging ? 0.7 : 0.9))
            )
            
            // Selection border and resize handles
            if isSelected {
                // Border - thicker and more visible in resize mode
                context.stroke(
                    bodyPath,
                    with: .color(.white),
                    lineWidth: isInResizeMode ? 3 : 2
                )
                
                // Handle opacity is higher in resize mode
                let handleOpacity: Double = isInResizeMode ? 0.6 : 0.25
                let handleOpacityRight: Double = isInResizeMode ? 0.7 : 0.35
                
                // Left resize handle (always visible on selected notes)
                let leftHandleVisualWidth = min(handleWidth, noteRect.width / 3)
                let leftHandleRect = CGRect(
                    x: noteRect.minX,
                    y: noteRect.minY,
                    width: leftHandleVisualWidth,
                    height: noteRect.height
                )
                let leftHandlePath = RoundedRectangle(cornerRadius: 2).path(in: leftHandleRect)
                context.fill(
                    leftHandlePath,
                    with: .color(.white.opacity(handleOpacity))
                )
                
                // Left grip lines
                if leftHandleVisualWidth > 12 {
                    let leftGripX = leftHandleRect.midX
                    for offset in [-2, 2] as [CGFloat] {
                        var gripPath = Path()
                        gripPath.move(to: CGPoint(x: leftGripX + offset, y: leftHandleRect.minY + 5))
                        gripPath.addLine(to: CGPoint(x: leftGripX + offset, y: leftHandleRect.maxY - 5))
                        context.stroke(gripPath, with: .color(.white.opacity(isInResizeMode ? 0.8 : 0.4)), lineWidth: isInResizeMode ? 2 : 1)
                    }
                }
                
                // Right resize handle
                let rightHandleVisualWidth = min(handleWidth, noteRect.width / 3)
                let rightHandleRect = CGRect(
                    x: noteRect.maxX - rightHandleVisualWidth,
                    y: noteRect.minY,
                    width: rightHandleVisualWidth,
                    height: noteRect.height
                )
                let rightHandlePath = RoundedRectangle(cornerRadius: 2).path(in: rightHandleRect)
                context.fill(
                    rightHandlePath,
                    with: .color(.white.opacity(handleOpacityRight))
                )
                
                // Right grip lines
                if rightHandleVisualWidth > 12 {
                    let rightGripX = rightHandleRect.midX
                    for offset in [-2, 2] as [CGFloat] {
                        var gripPath = Path()
                        gripPath.move(to: CGPoint(x: rightGripX + offset, y: rightHandleRect.minY + 5))
                        gripPath.addLine(to: CGPoint(x: rightGripX + offset, y: rightHandleRect.maxY - 5))
                        context.stroke(gripPath, with: .color(.white.opacity(0.5)), lineWidth: 1)
                    }
                }
            }
            
            // Velocity indicator (darker = lower velocity)
            let velocityAlpha = Double(note.velocity) / 127.0
            if velocityAlpha < 0.8 {
                let dimRect = CGRect(x: noteRect.minX + 1, y: noteRect.minY + 1, width: noteRect.width - 2, height: noteRect.height - 2)
                let dimPath = RoundedRectangle(cornerRadius: 3).path(in: dimRect)
                context.fill(
                    dimPath,
                    with: .color(.black.opacity(0.3 * (1 - velocityAlpha)))
                )
            }
        }
    }
    
    // MARK: - Key Labels (Visual Piano Keyboard)
    
    private func keyLabel(for pitch: UInt8) -> some View {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(pitch) / 12 - 1
        let noteName = noteNames[Int(pitch) % 12]
        let isBlackKey = noteName.contains("#")
        let isC = noteName == "C"
        
        let keyWidth = pianoKeyWidth
        let labelWidth = textLabelWidth
        let cFontSize = cNoteFontSize
        let otherFontSize = otherNoteFontSize
        
        return GeometryReader { geo in
            HStack(spacing: 0) {
                // LEFT ZONE: Visual Piano Key
                ZStack(alignment: .leading) {
                    // White key base
                    Rectangle()
                        .fill(isBlackKey ? Color(hex: "1A1A2E") : Color.white.opacity(0.95))
                        .frame(width: keyWidth, height: geo.size.height)
                    
                    // For black keys, overlay the black key portion
                    if isBlackKey {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "2A2A3E"))
                            .frame(width: keyWidth * blackKeyWidthRatio, height: geo.size.height - 2)
                            .shadow(color: .black.opacity(0.4), radius: 1, x: 1, y: 0)
                    }
                    
                    // Bottom border between keys
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(isBlackKey ? Color.white.opacity(0.1) : Color.black.opacity(0.15))
                            .frame(width: keyWidth, height: 0.5)
                    }
                }
                .frame(width: keyWidth)
                
                // RIGHT ZONE: Text Label
                ZStack {
                    Rectangle()
                        .fill(Color(hex: "1A1A2E"))
                    
                    // Show note name/octave
                    if isC {
                        Text("\(noteName)\(octave)")
                            .font(.system(size: cFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00FFCC"))
                    } else {
                        Text(isBlackKey ? "\(noteName.replacingOccurrences(of: "#", with: "♯"))\(octave)" : noteName)
                            .font(.system(size: otherFontSize, weight: isBlackKey ? .medium : .regular, design: .monospaced))
                            .foregroundColor(isBlackKey ? .white.opacity(0.5) : .white.opacity(0.7))
                    }
                    
                    // Bottom border
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5)
                    }
                    
                    // Right border to separate from grid
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1)
                    }
                }
                .frame(width: labelWidth)
            }
        }
    }
    
    // MARK: - Hit Testing
    
    /// Find a note at the given point, with expanded hit boxes for small notes
    private func noteAt(point: CGPoint, gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> MidiNote? {
        let adjustedX = point.x - keyLabelWidth
        guard adjustedX >= 0 else { return nil }
        
        let pitchOffset = Int(point.y / rowHeight)
        let tapPitch = Int(pitchRange.upperBound) - pitchOffset
        
        guard tapPitch >= Int(pitchRange.lowerBound) && tapPitch <= Int(pitchRange.upperBound) else { return nil }
        
        // Find note at this position, filtering by pitch proximity for accuracy
        for note in vm.track.notes {
            // Skip notes that are more than 1 semitone away from tap location
            let pitchDistance = abs(Int(note.pitch) - tapPitch)
            if pitchDistance > 1 { continue }
            
            let noteWidth = CGFloat(note.durationBeats / vm.loopLengthBeats) * gridWidth
            let noteX = CGFloat(note.startBeat / vm.loopLengthBeats) * gridWidth
            let notePitchOffset = Int(pitchRange.upperBound) - Int(note.pitch)
            let noteY = CGFloat(notePitchOffset) * rowHeight
            
            // Expand hit box for small notes
            let hitWidth = max(noteWidth, minHitWidth)
            let hitExpansion = (hitWidth - noteWidth) / 2
            
            let hitRect = CGRect(
                x: noteX - hitExpansion,
                y: noteY,
                width: hitWidth,
                height: rowHeight
            )
            
            if hitRect.contains(CGPoint(x: adjustedX, y: point.y)) {
                return note
            }
        }
        
        return nil
    }
    
    /// Determine if tap is on resize handle and which edge
    private func resizeEdgeAt(point: CGPoint, note: MidiNote, gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> HorizontalEdge? {
        let adjustedX = point.x - keyLabelWidth
        let noteStartX = CGFloat(note.startBeat / vm.loopLengthBeats) * gridWidth
        let noteEndX = CGFloat(note.endBeat / vm.loopLengthBeats) * gridWidth
        let noteWidth = noteEndX - noteStartX
        
        // Only allow resize handles on selected notes
        guard note.id == vm.selectedNoteId else { return nil }
        
        // Use larger hit area for easier grabbing
        let hitZone = handleHitWidth / 2
        
        // For small notes, use proportional zones (left third = left handle, right third = right handle)
        if noteWidth < handleHitWidth * 2 {
            let relativeX = adjustedX - noteStartX
            if relativeX < noteWidth / 3 {
                return .leading
            } else if relativeX > noteWidth * 2 / 3 {
                return .trailing
            }
            return nil // Middle third moves the note
        }
        
        // For larger notes, check if near the edges
        if adjustedX >= noteStartX - hitZone && adjustedX <= noteStartX + hitZone {
            return .leading
        }
        
        if adjustedX >= noteEndX - hitZone && adjustedX <= noteEndX + hitZone {
            return .trailing
        }
        
        return nil
    }
    
    private func pitchAt(point: CGPoint, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> UInt8? {
        let pitchOffset = Int(point.y / rowHeight)
        let pitch = Int(pitchRange.upperBound) - pitchOffset
        
        guard pitch >= Int(pitchRange.lowerBound) && pitch <= Int(pitchRange.upperBound) else { return nil }
        return UInt8(pitch)
    }
    
    private func beatAt(point: CGPoint, gridWidth: CGFloat) -> Double {
        let adjustedX = point.x - keyLabelWidth
        return (Double(max(0, adjustedX)) / Double(gridWidth)) * vm.loopLengthBeats
    }
    
    /// Check if point is near the playhead
    private func isOnPlayhead(point: CGPoint, gridWidth: CGFloat) -> Bool {
        let adjustedX = point.x - keyLabelWidth
        let playheadX = CGFloat(vm.currentBeat / vm.loopLengthBeats) * gridWidth
        return abs(adjustedX - playheadX) <= playheadHitWidth / 2
    }
    
    /// Determine which edge is nearest to the tap point (for resize mode)
    private func nearestResizeEdge(point: CGPoint, note: MidiNote, gridWidth: CGFloat) -> HorizontalEdge {
        let adjustedX = point.x - keyLabelWidth
        let noteStartX = CGFloat(note.startBeat / vm.loopLengthBeats) * gridWidth
        let noteEndX = CGFloat(note.endBeat / vm.loopLengthBeats) * gridWidth
        let noteMidX = (noteStartX + noteEndX) / 2
        
        return adjustedX < noteMidX ? .leading : .trailing
    }
    
    // MARK: - Gestures
    
    private func createTapGesture(gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // Only handle taps when not dragging
                guard dragStartLocation == nil else { return }
                
                // Check for note tap FIRST (higher priority than playhead)
                // This prevents accidental playhead selection when tapping near notes
                if let note = noteAt(point: value.location, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight) {
                    // Delete mode: immediately delete the note
                    if vm.isDeleteMode {
                        vm.deleteNote(note.id)
                        return
                    }
                    
                    // Multi-select mode: toggle note selection
                    if vm.isMultiSelectMode {
                        vm.toggleNoteSelection(note.id)
                        return
                    }
                    
                    if vm.selectedNoteId == note.id {
                        // Tapping already selected note - deselect and unlock background
                        vm.deselectAll()
                    } else {
                        // Selecting a different note - exit resize mode first
                        vm.exitResizeMode()
                        vm.selectNote(note.id)
                    }
                    return
                }
                
                // Check if tapping on playhead (only when paused and no note was tapped)
                if !vm.isPlaying && isOnPlayhead(point: value.location, gridWidth: gridWidth) {
                    if vm.isPlayheadSelected {
                        // Tapping already-selected playhead - deselect it
                        vm.deselectAll()
                    } else {
                        // Select the playhead
                        vm.selectPlayhead()
                    }
                    return
                }
                
                // Tapping empty space (no note, no playhead)
                if vm.isAddNoteMode {
                    // Add note mode: add a note at this position
                    if let pitch = pitchAt(point: value.location, pitchRange: pitchRange, rowHeight: rowHeight) {
                        let beat = beatAt(point: value.location, gridWidth: gridWidth)
                        vm.addNote(pitch: pitch, startBeat: beat, duration: vm.lastNoteDuration)
                    }
                } else if vm.isMultiSelectMode && !vm.selectedNoteIds.isEmpty {
                    // Multi-select mode with notes selected - do NOT deselect
                    // This allows panning the background without losing selection
                    return
                } else {
                    // Normal mode - deselect everything and unlock background
                    vm.deselectAll()
                }
            }
    }
    
    private func createDoubleTapGesture(gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if let note = noteAt(point: value.location, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight) {
                    // Double-tap on a note - select it and toggle resize mode
                    if vm.selectedNoteId == note.id {
                        vm.toggleResizeMode()
                    } else {
                        vm.selectNote(note.id)
                        vm.toggleResizeMode()
                    }
                }
            }
    }
    
    private func createDragGesture(gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> some Gesture {
        // Use low minimumDistance to quickly detect note drags and lock scroll
        // The simultaneousGesture allows scroll to work until we detect a note drag
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                handleDragChanged(value: value, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight)
            }
            .onEnded { _ in
                handleDragEnded()
            }
    }
    
    // Track if we're in a valid drag (note or playhead) vs empty space drag
    @State private var isValidDrag = false
    
    // Track if we're dragging multiple notes
    @State private var isMultiNoteDrag = false
    @State private var multiDragStartY: CGFloat = 0
    
    private func handleDragChanged(value: DragGesture.Value, gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) {
        // Initialize drag on first movement
        if dragStartLocation == nil {
            dragStartLocation = value.startLocation
            
            // Only allow dragging if playhead is already selected
            if vm.isPlayheadSelected && !vm.isPlaying {
                isDraggingPlayhead = true
                isValidDrag = true
                isNoteDragActive = true  // Lock scroll during playhead drag
                playheadDragBeat = vm.currentBeat
                return
            }
            
            // Check if we're in multi-select mode with notes selected
            if vm.isMultiSelectMode && !vm.selectedNoteIds.isEmpty {
                // Check if drag started on a selected note
                if let tappedNote = noteAt(point: value.startLocation, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight),
                   vm.selectedNoteIds.contains(tappedNote.id) {
                    // Start multi-note drag
                    isValidDrag = true
                    isMultiNoteDrag = true
                    isNoteDragActive = true  // Lock scroll during note drag
                    multiDragStartY = value.startLocation.y
                    vm.beginMultiDrag()
                    return
                }
                // Tapped on empty space or non-selected note - allow scroll (no drag)
                isValidDrag = false
                return
            }
            
            // Single-select mode: Only allow dragging if a note is already selected
            if let selectedId = vm.selectedNoteId,
               let note = track.notes.first(where: { $0.id == selectedId }) {
                isValidDrag = true
                isNoteDragActive = true  // Lock scroll during note drag
                
                // Only allow resize if in resize mode (activated by double-tap)
                if vm.isResizeMode {
                    let edge = nearestResizeEdge(point: value.startLocation, note: note, gridWidth: gridWidth)
                    vm.beginDrag(noteId: note.id, isResizing: true, resizeEdge: edge)
                    dragStartNoteState = (startBeat: note.startBeat, duration: note.durationBeats, pitch: note.pitch)
                } else {
                    // Normal mode: only move the note (no resize on single tap)
                    vm.beginDrag(noteId: note.id, isResizing: false)
                    dragStartNoteState = (startBeat: note.startBeat, duration: note.durationBeats, pitch: note.pitch)
                }
                return
            }
            
            // No selection - don't start a drag
            isValidDrag = false
            return
        }
        
        // If not a valid drag, don't process
        guard isValidDrag else { return }
        
        // Handle playhead dragging
        if isDraggingPlayhead {
            let beat = beatAt(point: value.location, gridWidth: gridWidth)
            playheadDragBeat = max(0, min(beat, vm.loopLengthBeats))
            return
        }
        
        guard let startLoc = dragStartLocation else { return }
        
        // Handle multi-note dragging
        if isMultiNoteDrag {
            let deltaX = value.location.x - startLoc.x
            let deltaBeats = (Double(deltaX) / Double(gridWidth)) * vm.loopLengthBeats
            
            // Calculate pitch delta from Y movement
            let deltaY = value.location.y - multiDragStartY
            let deltaPitchRows = Int(round(deltaY / rowHeight))
            let deltaPitch = -deltaPitchRows  // Negative because moving down decreases pitch
            
            vm.updateMultiDragPosition(deltaBeats: deltaBeats, deltaPitch: deltaPitch)
            return
        }
        
        // Update single-note drag preview
        guard let startState = dragStartNoteState,
              vm.draggedNoteId != nil else { return }
        
        let deltaX = value.location.x - startLoc.x
        let deltaBeats = (Double(deltaX) / Double(gridWidth)) * vm.loopLengthBeats
        
        if vm.isResizing {
            if vm.resizeEdge == .trailing {
                // Resize from right edge: change duration only
                let newDuration = startState.duration + deltaBeats
                vm.updateDragResize(newDuration: newDuration)
            } else {
                // Resize from left edge: change start and duration
                let newStartBeat = startState.startBeat + deltaBeats
                let newDuration = startState.duration - deltaBeats  // Duration shrinks when start moves right
                vm.updateDragResize(newDuration: newDuration, newStartBeat: newStartBeat)
            }
        } else {
            // Moving: update both position and pitch
            let newStartBeat = startState.startBeat + deltaBeats
            
            // Calculate pitch from absolute Y position (fixes note disappearing when dropped on pitch boundary)
            // Using floor() ensures consistent snapping - the row containing the touch point wins
            let currentY = value.location.y
            let pitchOffset = Int(floor(currentY / rowHeight))  // Which row from top (0-indexed)
            let targetPitch = Int(pitchRange.upperBound) - pitchOffset
            
            // Clamp to BOTH valid MIDI range (0-127) AND visible pitch range to prevent note from going off-screen
            let clampedPitch = UInt8(max(Int(pitchRange.lowerBound), min(Int(pitchRange.upperBound), targetPitch)))
            vm.updateDragPosition(newStartBeat: newStartBeat, newPitch: clampedPitch)
            
            // Trigger auto-scroll if pitch is near edge of range
            let pitchRange = vm.pitchRange
            let edgeBuffer: UInt8 = 2  // Scroll when within 2 semitones of edge
            if clampedPitch <= pitchRange.lowerBound + edgeBuffer && clampedPitch > 0 {
                // Near bottom edge, scroll down
                autoScrollToPitch = max(0, clampedPitch - edgeBuffer)
            } else if clampedPitch >= pitchRange.upperBound - edgeBuffer && clampedPitch < 127 {
                // Near top edge, scroll up
                autoScrollToPitch = min(127, clampedPitch + edgeBuffer)
            }
        }
    }
    
    // Helper to access track notes from gesture handlers
    private var track: Track { vm.track }
    
    private func handleDragEnded() {
        // Commit playhead position if dragging
        if isDraggingPlayhead, let beat = playheadDragBeat {
            vm.seekTo(beat: beat)
            isDraggingPlayhead = false
            playheadDragBeat = nil
            dragStartLocation = nil
            isValidDrag = false
            isNoteDragActive = false  // Unlock scroll
            autoScrollToPitch = nil
            return
        }
        
        // Handle multi-note drag end
        if isMultiNoteDrag {
            vm.endMultiDrag()
            isMultiNoteDrag = false
            multiDragStartY = 0
            dragStartLocation = nil
            isValidDrag = false
            isNoteDragActive = false  // Unlock scroll
            autoScrollToPitch = nil
            return
        }
        
        vm.endDrag()
        dragStartLocation = nil
        dragStartNoteState = nil
        isValidDrag = false
        isNoteDragActive = false  // Unlock scroll
        autoScrollToPitch = nil
    }
    
    private func createLongPressGesture(gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                // Don't delete if we're in the middle of a drag operation
                guard !isValidDrag && vm.draggedNoteId == nil else { return }
                
                switch value {
                case .second(true, let drag):
                    if let drag = drag,
                       let note = noteAt(point: drag.startLocation, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight) {
                        // Don't delete if this note is already selected (user is probably trying to drag it)
                        if vm.selectedNoteId == note.id { return }
                        vm.selectNote(note.id)
                        vm.deleteNote(note.id)
                    }
                default:
                    break
                }
            }
    }
}

// MARK: - Double Tap Extension for Adding Notes

extension PianoRollCanvasView {
    func handleDoubleTap(at point: CGPoint, gridWidth: CGFloat, pitchRange: ClosedRange<UInt8>, rowHeight: CGFloat) {
        // Check if tapping on existing note
        if noteAt(point: point, gridWidth: gridWidth, pitchRange: pitchRange, rowHeight: rowHeight) != nil {
            return // Don't add note on top of existing
        }
        
        // Add new note
        if let pitch = pitchAt(point: point, pitchRange: pitchRange, rowHeight: rowHeight) {
            let beat = beatAt(point: point, gridWidth: gridWidth)
            vm.addNote(pitch: pitch, startBeat: beat)
        }
    }
}

#Preview {
    let looperVM = LooperViewModel()
    let track = Track(
        instrumentName: "Piano",
        instrumentProgram: 0,
        isDrumKit: false,
        notes: [
            MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1),
            MidiNote(pitch: 64, velocity: 90, startBeat: 1, durationBeats: 0.5),
            MidiNote(pitch: 67, velocity: 80, startBeat: 2, durationBeats: 2),
            MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1),
            MidiNote(pitch: 72, velocity: 70, startBeat: 4, durationBeats: 0.25)
        ]
    )
    let focusVM = TrackFocusViewModel(track: track, looperVM: looperVM)
    
    return PianoRollCanvasView(vm: focusVM)
        .frame(height: 300)
        .background(Color(hex: "0D0D1A"))
}
