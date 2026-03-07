import Foundation
import CoreGraphics

/// Shared keyboard layout engine for consistent key positioning
/// Used by both KeyboardView (hit testing) and KeyboardLayer (rendering)
struct KeyboardLayoutEngine {
	let startNote: UInt8
	let count: Int
	
	// MARK: - Key Frame Structure
	
	struct KeyFrame {
		let note: UInt8
		let rect: CGRect
		let isBlack: Bool
	}
	
	// MARK: - Computed Properties
	
	var whiteKeyCount: Int {
		var count = 0
		for i in 0..<self.count {
			let midi = Int(startNote) + i
			if !isBlack(midi: midi) {
				count += 1
			}
		}
		return count
	}
	
	// MARK: - Public API
	
	/// Check if a MIDI note is a black key
	func isBlack(midi: Int) -> Bool {
		let pc = midi % 12
		return [1, 3, 6, 8, 10].contains(pc)
	}
	
	/// Build all key frames for the given size
	func buildFrames(size: CGSize) -> [KeyFrame] {
		let w = size.width
		let h = size.height
		
		// Calculate whites before each key
		var whitesBefore: [Int] = Array(repeating: 0, count: count)
		var whiteCount = 0
		
		for i in 0..<count {
			let midi = Int(startNote) + i
			whitesBefore[i] = whiteCount
			if !isBlack(midi: midi) {
				whiteCount += 1
			}
		}
		
		let whiteW = w / CGFloat(max(1, whiteCount))
		var frames: [KeyFrame] = []
		
		// White keys
		var whiteIndex = 0
		for i in 0..<count {
			let midi = Int(startNote) + i
			if !isBlack(midi: midi) {
				let x = CGFloat(whiteIndex) * whiteW
				let rect = CGRect(x: x, y: 0, width: whiteW - 1, height: h)
				frames.append(KeyFrame(note: UInt8(midi), rect: rect, isBlack: false))
				whiteIndex += 1
			}
		}
		
		// Black keys
		for i in 0..<count {
			let midi = Int(startNote) + i
			if isBlack(midi: midi) {
				let prevW = whitesBefore[i] - 1
				let nextW = whitesBefore[i]
				if prevW >= 0 && nextW < whiteCount {
					let prevCenter = (CGFloat(prevW) * whiteW) + whiteW / 2
					let nextCenter = (CGFloat(nextW) * whiteW) + whiteW / 2
					let centerX = (prevCenter + nextCenter) / 2
					let bw = whiteW * 0.6
					let rect = CGRect(x: centerX - bw / 2, y: 0, width: bw, height: h * 0.6)
					frames.append(KeyFrame(note: UInt8(midi), rect: rect, isBlack: true))
				}
			}
		}
		
		return frames
	}
	
	/// Build separate white and black key frame arrays for rendering
	func buildSeparatedFrames(size: CGSize) -> (whites: [CGRect], blacks: [CGRect]) {
		let frames = buildFrames(size: size)
		let whites = frames.filter { !$0.isBlack }.map { $0.rect }
		let blacks = frames.filter { $0.isBlack }.map { $0.rect }
		return (whites, blacks)
	}
	
	/// Find the note at a given point, preferring black keys
	func noteAt(point: CGPoint, size: CGSize) -> UInt8 {
		let frames = buildFrames(size: size)
		
		// Prefer black keys hit-testing first
		if let hit = frames.first(where: { $0.isBlack && $0.rect.contains(point) }) {
			return hit.note
		}
		if let hit = frames.first(where: { !$0.isBlack && $0.rect.contains(point) }) {
			return hit.note
		}
		
		// Fallback to nearest horizontal mapping
		let x = max(0, min(Double(point.x / size.width), 1.0))
		let idx = Int((Double(count) * x).rounded(.down))
		return startNote &+ UInt8(max(0, min(count - 1, idx)))
	}
}

