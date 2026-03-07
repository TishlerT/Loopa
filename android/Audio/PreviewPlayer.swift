import Foundation
import AVFoundation
import CryptoKit

final class PreviewPlayer: ObservableObject {
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private var buffer: AVAudioPCMBuffer?

	init() {
		engine.attach(player)
		engine.connect(player, to: engine.mainMixerNode, format: nil)
		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
		try? engine.start()
	}

	func play(url: URL) async throws {
		let data: Data
		if let cached = try? Data(contentsOf: cacheURL(for: url)), !cached.isEmpty {
			data = cached
		} else {
			let (d, _) = try await URLSession.shared.data(from: url)
			data = d
			try? data.write(to: cacheURL(for: url), options: .atomic)
		}
		let file = try AVAudioFile(forReading: writeTemp(data: data))
		let format = file.processingFormat
		let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
		try file.read(into: buf)
		buffer = buf
		player.stop()
		player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
		if !engine.isRunning { try engine.start() }
		player.play()
	}

	func stop() { player.stop() }

	private func cacheURL(for url: URL) -> URL {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return dir.appendingPathComponent(url.absoluteString.sha1 + ".mp3")
	}

	private func writeTemp(data: Data) throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
		try data.write(to: url, options: .atomic)
		return url
	}
}

private extension String {
	var sha1: String {
		let data = Data(self.utf8)
		let digest = Insecure.SHA1.hash(data: data)
		return digest.map { String(format: "%02x", $0) }.joined()
	}
}





