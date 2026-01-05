import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
	func application(_ application: UIApplication,
					supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
		[.landscapeLeft, .landscapeRight]
	}
}

@main
struct LoopaApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@StateObject private var looperVM = LooperViewModel()
	
	var body: some Scene {
		WindowGroup {
			LooperView()
				.environmentObject(looperVM)
				.onOpenURL { url in
					handleIncomingFile(url)
				}
		}
	}
	
	/// Handle incoming .loopa files when user taps them
	private func handleIncomingFile(_ url: URL) {
		print("📂 Received file: \(url.path)")
		
		// Check if this is a .loopa file
		guard SessionExporter.shared.canHandle(url: url) else {
			print("⚠️ Not a .loopa file: \(url.pathExtension)")
			return
		}
		
		// Import the session
		guard let session = SessionExporter.shared.importSession(from: url) else {
			print("❌ Failed to import session from: \(url.path)")
			return
		}
		
		// Load the imported session into the app
		Task { @MainActor in
			looperVM.loadImportedSession(session)
		}
	}
}
