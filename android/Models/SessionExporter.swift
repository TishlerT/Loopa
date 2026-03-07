import Foundation
import UIKit

/// Handles exporting and importing .loopa session files
final class SessionExporter {
    static let shared = SessionExporter()
    
    private let fileManager = FileManager.default
    
    /// File extension for Loopa session files
    static let fileExtension = "loopa"
    
    /// UTI for Loopa session files
    static let contentType = "com.loopa.session"
    
    private init() {}
    
    // MARK: - Export
    
    /// Export a session to a shareable .loopa file
    /// - Parameter session: The session to export
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportSession(_ session: SavedSession) -> URL? {
        let fileName = sanitizeFileName(session.name) + ".\(Self.fileExtension)"
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(session)
            try data.write(to: tempURL)
            
            print("✓ Exported session to: \(tempURL.path)")
            return tempURL
        } catch {
            print("❌ Failed to export session: \(error)")
            return nil
        }
    }
    
    /// Export current session state to a shareable file
    /// - Parameters:
    ///   - name: Session name
    ///   - bpm: Current BPM
    ///   - barCount: Current bar count
    ///   - tracks: Current tracks
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportSession(name: String, bpm: Double, barCount: Int, tracks: [Track]) -> URL? {
        let session = SavedSession(
            name: name,
            bpm: bpm,
            barCount: barCount,
            tracks: tracks
        )
        return exportSession(session)
    }
    
    // MARK: - Import
    
    /// Import a session from a .loopa file URL
    /// - Parameter url: URL to the .loopa file
    /// - Returns: The imported session, or nil if import failed
    func importSession(from url: URL) -> SavedSession? {
        // Start accessing security-scoped resource if needed
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            var session = try decoder.decode(SavedSession.self, from: data)
            
            // Generate new ID to avoid conflicts with existing sessions
            session = SavedSession(
                id: UUID(),
                name: session.name + " (Imported)",
                bpm: session.bpm,
                barCount: session.barCount,
                tracks: session.tracks
            )
            
            print("✓ Imported session: \(session.name)")
            return session
        } catch {
            print("❌ Failed to import session: \(error)")
            return nil
        }
    }
    
    /// Check if a URL is a valid .loopa file
    func canHandle(url: URL) -> Bool {
        return url.pathExtension.lowercased() == Self.fileExtension
    }
    
    // MARK: - Helpers
    
    /// Sanitize a filename to remove invalid characters
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
}

// MARK: - Share Sheet Presenter

extension SessionExporter {
    /// Present a share sheet for the exported session file
    /// - Parameters:
    ///   - session: The session to share
    ///   - sourceView: The view to anchor the popover on iPad
    @MainActor
    func shareSession(_ session: SavedSession, from sourceView: UIView? = nil) {
        guard let fileURL = exportSession(session) else {
            print("❌ Failed to create shareable file")
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                // Fallback to center of screen
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
            }
        }
        
        // Present
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presentingVC = rootVC
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(activityVC, animated: true)
        }
    }
}

