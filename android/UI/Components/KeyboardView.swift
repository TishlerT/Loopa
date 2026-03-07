import SwiftUI
import UIKit

// MARK: - Key Event

enum KeyEvent {
	case down(note: UInt8, velocity: UInt8, isLeft: Bool)
	case up(note: UInt8, isLeft: Bool)
}

// MARK: - Keyboard View with Visual Feedback

struct KeyboardView: View {
	let startNote: UInt8
	let count: Int
	var onEvent: (KeyEvent) -> Void
	
	@State private var touchMap: [ObjectIdentifier: UInt8] = [:] // touch -> note
	@State private var pressedNotes: [UInt8: PressedKeyInfo] = [:] // note -> press info
	
	private var layoutEngine: KeyboardLayoutEngine {
		KeyboardLayoutEngine(startNote: startNote, count: count)
	}
	
	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .topLeading) {
				// Background
				Color.tishBackground
				
				// Keys with visual feedback
				KeyboardLayerAnimated(
					startNote: startNote,
					count: count,
					pressedNotes: pressedNotes
				)
				
				// Touch capture layer
				TouchOverlay(began: { touches, view in
					for t in touches { handle(t, in: view, size: geo.size, isDown: true) }
				}, moved: { touches, view in
					for t in touches { handle(t, in: view, size: geo.size, isDown: nil) }
				}, ended: { touches, _ in
					for t in touches { endTouch(t) }
				})
			}
		}
	}
	
	// MARK: - Touch Handling
	
	private func handle(_ touch: UITouch, in view: UIView, size: CGSize, isDown: Bool?) {
		let id = ObjectIdentifier(touch)
		let p = touch.location(in: view)
		let note = layoutEngine.noteAt(point: p, size: size)
		let isLeft = p.x < size.width * 0.5
		let vel = UInt8(max(20, min(127, Int(127 - (p.y / size.height) * 100))))
		
		if let prev = touchMap[id], prev != note {
			// Note changed - release old, press new
			withAnimation(.easeOut(duration: 0.08)) {
				pressedNotes.removeValue(forKey: prev)
			}
			onEvent(.up(note: prev, isLeft: isLeft))
			
			touchMap[id] = note
			withAnimation(.easeOut(duration: 0.02)) {
				pressedNotes[note] = PressedKeyInfo(velocity: vel, isLeft: isLeft)
			}
			onEvent(.down(note: note, velocity: vel, isLeft: isLeft))
		} else if isDown == true {
			// New touch
			touchMap[id] = note
			withAnimation(.easeOut(duration: 0.02)) {
				pressedNotes[note] = PressedKeyInfo(velocity: vel, isLeft: isLeft)
			}
			onEvent(.down(note: note, velocity: vel, isLeft: isLeft))
		}
	}
	
	private func endTouch(_ touch: UITouch) {
		let id = ObjectIdentifier(touch)
		if let note = touchMap[id] {
			let isLeft = (touch.location(in: touch.view).x) < (touch.view?.bounds.width ?? 0) * 0.5
			withAnimation(.easeOut(duration: 0.15)) {
				pressedNotes.removeValue(forKey: note)
			}
			onEvent(.up(note: note, isLeft: isLeft))
			touchMap.removeValue(forKey: id)
		}
	}
}

// MARK: - Pressed Key Info

struct PressedKeyInfo {
	let velocity: UInt8
	let isLeft: Bool
	
	/// Normalized velocity (0-1)
	var normalizedVelocity: Double {
		Double(velocity) / 127.0
	}
}

// MARK: - Animated Keyboard Layer

struct KeyboardLayerAnimated: View {
	let startNote: UInt8
	let count: Int
	let pressedNotes: [UInt8: PressedKeyInfo]
	
	private var layoutEngine: KeyboardLayoutEngine {
		KeyboardLayoutEngine(startNote: startNote, count: count)
	}
	
	var body: some View {
		GeometryReader { geo in
			let frames = layoutEngine.buildFrames(size: geo.size)
			let whiteKeys = frames.filter { !$0.isBlack }
			let blackKeys = frames.filter { $0.isBlack }
			
			ZStack(alignment: .topLeading) {
				// White keys
				ForEach(whiteKeys, id: \.note) { key in
					KeyShape(
						frame: key.rect,
						isBlack: false,
						isPressed: pressedNotes[key.note] != nil,
						velocity: pressedNotes[key.note]?.normalizedVelocity ?? 0,
						isLeft: pressedNotes[key.note]?.isLeft ?? true
					)
				}
				
				// Black keys (on top)
				ForEach(blackKeys, id: \.note) { key in
					KeyShape(
						frame: key.rect,
						isBlack: true,
						isPressed: pressedNotes[key.note] != nil,
						velocity: pressedNotes[key.note]?.normalizedVelocity ?? 0,
						isLeft: pressedNotes[key.note]?.isLeft ?? true
					)
				}
			}
		}
	}
}

// MARK: - Individual Key Shape

struct KeyShape: View {
	let frame: CGRect
	let isBlack: Bool
	let isPressed: Bool
	let velocity: Double
	let isLeft: Bool
	
	var body: some View {
		let baseColor = isBlack ? Color.tishKeyBlack : Color.tishKeyWhite
		let pressedColor = isLeft ? Color.tishAccent : Color.tishAccentSecondary
		
		// Velocity affects the glow intensity
		let glowIntensity = isPressed ? velocity : 0
		
		ZStack {
			// Key background
			RoundedRectangle(cornerRadius: isBlack ? 3 : 4)
				.fill(isPressed ? pressedColor.opacity(0.3 + velocity * 0.3) : baseColor)
			
			// Border
			RoundedRectangle(cornerRadius: isBlack ? 3 : 4)
				.stroke(
					isPressed ? pressedColor : Color.tishKeyBorder,
					lineWidth: isPressed ? 2 : (isBlack ? 0 : 1)
				)
			
			// Velocity indicator (bottom bar for pressed keys)
			if isPressed {
				VStack {
					Spacer()
					RoundedRectangle(cornerRadius: 2)
						.fill(pressedColor)
						.frame(height: 4)
						.padding(.horizontal, 2)
						.padding(.bottom, 2)
				}
			}
		}
		.frame(width: frame.width, height: frame.height)
		.position(x: frame.midX, y: frame.midY)
		.shadow(
			color: isPressed ? pressedColor.opacity(glowIntensity * 0.6) : .clear,
			radius: isPressed ? 8 * velocity : 0
		)
		.animation(.easeOut(duration: 0.05), value: isPressed)
	}
}
