import SwiftUI
import UIKit

/// Keyboard event (simplified - no left/right split)
enum FullKeyEvent {
	case down(note: UInt8, velocity: UInt8)
	case up(note: UInt8)
}

/// Full-width keyboard view with multi-touch support
struct FullKeyboardView: View {
	let startNote: UInt8
	let keyCount: Int
	let isDrumKit: Bool
	let onEvent: (FullKeyEvent) -> Void
	
	@State private var pressedNotes: Set<UInt8> = []
	@State private var touchMap: [ObjectIdentifier: UInt8] = [:]
	
	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .topLeading) {
				// Keyboard background
				Color(hex: "0A0A14")
				
				// Keys
				if isDrumKit {
					DrumPadLayout(
						padCount: min(keyCount, 16),
						pressedPads: pressedNotes,
						size: geo.size
					)
				} else {
					PianoKeyLayout(
						startNote: startNote,
						keyCount: keyCount,
						pressedKeys: pressedNotes,
						size: geo.size
					)
				}
				
				// Touch overlay
				FullTouchOverlay { touches, view, phase in
					handleTouches(touches, view: view, size: geo.size, phase: phase)
				}
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 12))
	}
	
	private func handleTouches(_ touches: Set<UITouch>, view: UIView, size: CGSize, phase: UITouch.Phase) {
		for touch in touches {
			let id = ObjectIdentifier(touch)
			let point = touch.location(in: view)
			
			// Calculate note from position
			let note: UInt8
			if isDrumKit {
				note = drumNoteAt(point, size: size)
			} else {
				note = pianoNoteAt(point, size: size)
			}
			
			switch phase {
			case .began:
				let velocity = velocityFromY(point.y, height: size.height)
				touchMap[id] = note
				pressedNotes.insert(note)
				onEvent(.down(note: note, velocity: velocity))
				
			case .moved:
				if let prevNote = touchMap[id], prevNote != note {
					// Slide to new note
					pressedNotes.remove(prevNote)
					onEvent(.up(note: prevNote))
					
					let velocity = velocityFromY(point.y, height: size.height)
					touchMap[id] = note
					pressedNotes.insert(note)
					onEvent(.down(note: note, velocity: velocity))
				}
				
			case .ended, .cancelled:
				if let prevNote = touchMap[id] {
					pressedNotes.remove(prevNote)
					onEvent(.up(note: prevNote))
					touchMap.removeValue(forKey: id)
				}
				
			default:
				break
			}
		}
	}
	
	private func velocityFromY(_ y: CGFloat, height: CGFloat) -> UInt8 {
		// Higher on key = softer, lower = harder
		let normalized = y / height
		let velocity = 60 + (1 - normalized) * 67 // Range: 60-127
		return UInt8(max(60, min(127, velocity)))
	}
	
	private func pianoNoteAt(_ point: CGPoint, size: CGSize) -> UInt8 {
		let engine = KeyboardLayoutEngine(startNote: startNote, count: keyCount)
		return engine.noteAt(point: point, size: size)
	}
	
	private func drumNoteAt(_ point: CGPoint, size: CGSize) -> UInt8 {
		// 4x4 grid of drum pads
		let cols = 4
		let rows = 4
		let padWidth = size.width / CGFloat(cols)
		let padHeight = size.height / CGFloat(rows)
		
		let col = Int(point.x / padWidth)
		let row = Int(point.y / padHeight)
		let index = row * cols + col
		
		return startNote + UInt8(max(0, min(15, index)))
	}
}

// MARK: - Piano Key Layout

struct PianoKeyLayout: View {
	let startNote: UInt8
	let keyCount: Int
	let pressedKeys: Set<UInt8>
	let size: CGSize
	
	var body: some View {
		let engine = KeyboardLayoutEngine(startNote: startNote, count: keyCount)
		let frames = engine.buildFrames(size: size)
		let whiteFrames = frames.filter { !$0.isBlack }
		let blackFrames = frames.filter { $0.isBlack }
		
		ZStack(alignment: .topLeading) {
			// White keys first (below black keys)
			ForEach(whiteFrames.indices, id: \.self) { index in
				let frame = whiteFrames[index]
				let isPressed = pressedKeys.contains(frame.note)
				
				RoundedRectangle(cornerRadius: 4)
					.fill(isPressed ? Color(hex: "00FFCC") : Color(hex: "F5F5F5"))
					.frame(width: frame.rect.width - 2, height: frame.rect.height)
					.position(x: frame.rect.midX, y: frame.rect.midY)
					.shadow(color: .black.opacity(0.2), radius: isPressed ? 0 : 2, y: isPressed ? 0 : 2)
			}
			
			// Black keys on top
			ForEach(blackFrames.indices, id: \.self) { index in
				let frame = blackFrames[index]
				let isPressed = pressedKeys.contains(frame.note)
				
				RoundedRectangle(cornerRadius: 3)
					.fill(isPressed ? Color(hex: "00CCAA") : Color(hex: "1A1A1A"))
					.frame(width: frame.rect.width, height: frame.rect.height)
					.position(x: frame.rect.midX, y: frame.rect.midY)
					.shadow(color: .black.opacity(0.4), radius: isPressed ? 0 : 2, y: isPressed ? 0 : 3)
			}
		}
	}
}

// MARK: - Drum Pad Layout

struct DrumPadLayout: View {
	let padCount: Int
	let pressedPads: Set<UInt8>
	let size: CGSize
	
	private let drumNames = [
		"KICK", "SNARE", "HI-HAT", "OPEN HH",
		"CLAP", "TOM 1", "TOM 2", "TOM 3",
		"CRASH", "RIDE", "RIM", "COWBELL",
		"CLAVE", "SHAKER", "TAMBOURINE", "PERC"
	]
	
	private let padColors = [
		"FF3B30", "FF9500", "FFCC00", "34C759",
		"5AC8FA", "007AFF", "5856D6", "AF52DE",
		"FF2D55", "FF6B6B", "4ECDC4", "45B7D1",
		"96CEB4", "FFEAA7", "DFE6E9", "B2BEC3"
	]
	
	var body: some View {
		let cols = 4
		let rows = 4
		let padWidth = size.width / CGFloat(cols)
		let padHeight = size.height / CGFloat(rows)
		let padding: CGFloat = 4
		
		ZStack(alignment: .topLeading) {
			ForEach(0..<min(padCount, 16), id: \.self) { index in
				let col = index % cols
				let row = index / cols
				let note = UInt8(48 + index) // startNote + index
				let isPressed = pressedPads.contains(note)
				
				let x = CGFloat(col) * padWidth + padWidth / 2
				let y = CGFloat(row) * padHeight + padHeight / 2
				
				ZStack {
					RoundedRectangle(cornerRadius: 8)
						.fill(
							LinearGradient(
								colors: [
									Color(hex: padColors[index]).opacity(isPressed ? 1 : 0.7),
									Color(hex: padColors[index]).opacity(isPressed ? 0.8 : 0.5)
								],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						.frame(width: padWidth - padding * 2, height: padHeight - padding * 2)
						.scaleEffect(isPressed ? 0.95 : 1.0)
						.animation(.easeOut(duration: 0.1), value: isPressed)
					
					Text(drumNames[index])
						.font(.system(size: 10, weight: .bold))
						.foregroundColor(.white.opacity(0.9))
				}
				.position(x: x, y: y)
			}
		}
	}
}

// MARK: - Touch Overlay

struct FullTouchOverlay: UIViewRepresentable {
	let onTouches: (Set<UITouch>, UIView, UITouch.Phase) -> Void
	
	func makeUIView(context: Context) -> TouchCaptureView {
		let view = TouchCaptureView()
		view.onTouches = onTouches
		view.isMultipleTouchEnabled = true
		view.backgroundColor = .clear
		return view
	}
	
	func updateUIView(_ uiView: TouchCaptureView, context: Context) {
		uiView.onTouches = onTouches
	}
	
	class TouchCaptureView: UIView {
		var onTouches: ((Set<UITouch>, UIView, UITouch.Phase) -> Void)?
		
		override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
			// Only capture touches that are within our bounds
			if bounds.contains(point) {
				return self
			}
			return nil
		}
		
		override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
			// Strictly check if point is inside our bounds
			return bounds.contains(point)
		}
		
		override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
			onTouches?(touches, self, .began)
		}
		
		override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
			onTouches?(touches, self, .moved)
		}
		
		override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
			onTouches?(touches, self, .ended)
		}
		
		override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
			onTouches?(touches, self, .cancelled)
		}
	}
}


