import SwiftUI

struct SoundRow: View {
	let sound: Sound
	let onPlay: () -> Void

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				Text(sound.name).font(.headline).lineLimit(1)
				Text(attribution).font(.caption).foregroundColor(.secondary).lineLimit(1)
			}
			Spacer()
			Button("Play") { onPlay() }
		}
		.padding(.vertical, 6)
	}

	private var attribution: String {
		let user = sound.user?.username ?? "Unknown"
		let license = sound.license ?? ""
		return "by \(user) \(license)"
	}
}





