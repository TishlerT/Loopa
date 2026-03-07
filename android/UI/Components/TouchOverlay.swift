import SwiftUI
import UIKit

/// UIViewRepresentable bridge for multi-touch handling
struct TouchOverlay: UIViewRepresentable {
	var began: ((Set<UITouch>, UIView) -> Void)
	var moved: ((Set<UITouch>, UIView) -> Void)
	var ended: ((Set<UITouch>, UIView) -> Void)
	
	func makeUIView(context: Context) -> TouchView {
		let v = TouchView()
		v.isMultipleTouchEnabled = true
		v.onBegan = { [weak v] t, _ in if let v { began(t, v) } }
		v.onMoved = { [weak v] t, _ in if let v { moved(t, v) } }
		v.onEnded = { [weak v] t, _ in if let v { ended(t, v) } }
		v.onCancelled = { [weak v] t, _ in if let v { ended(t, v) } }
		return v
	}
	
	func updateUIView(_ uiView: TouchView, context: Context) {}
}

/// Custom UIView that captures all touch events
final class TouchView: UIView {
	var onBegan: ((Set<UITouch>, UIEvent?) -> Void)?
	var onMoved: ((Set<UITouch>, UIEvent?) -> Void)?
	var onEnded: ((Set<UITouch>, UIEvent?) -> Void)?
	var onCancelled: ((Set<UITouch>, UIEvent?) -> Void)?
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		onBegan?(touches, event)
	}
	
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		onMoved?(touches, event)
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		onEnded?(touches, event)
	}
	
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		onCancelled?(touches, event)
	}
}

