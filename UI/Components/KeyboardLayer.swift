import SwiftUI

/// Static visual layer for piano key rendering
struct KeyboardLayer: View {
	let startNote: UInt8
	let count: Int
	
	private var layoutEngine: KeyboardLayoutEngine {
		KeyboardLayoutEngine(startNote: startNote, count: count)
	}
	
	var body: some View {
		GeometryReader { geo in
			let frames = layoutEngine.buildSeparatedFrames(size: geo.size)
			
			ZStack(alignment: .topLeading) {
				// White keys first (underneath)
				ForEach(frames.whites.indices, id: \.self) { idx in
					let f = frames.whites[idx]
					Rectangle()
						.fill(Color.white)
						.frame(width: f.width, height: f.height)
						.position(x: f.midX, y: f.midY)
				}
				
				// Black keys on top
				ForEach(frames.blacks.indices, id: \.self) { idx in
					let f = frames.blacks[idx]
					Rectangle()
						.fill(Color.black)
						.frame(width: f.width, height: f.height)
						.position(x: f.midX, y: f.midY)
				}
			}
		}
	}
}
