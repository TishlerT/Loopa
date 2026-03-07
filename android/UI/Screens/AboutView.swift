import SwiftUI

/// In-app About page
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    
                    // App Icon and Name
                    VStack(spacing: 12) {
                        Image("AppIcon")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .cornerRadius(22)
                            .shadow(radius: 5)
                        
                        // Fallback if AppIcon image isn't available
                        Text("L∞PA")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Description
                    VStack(spacing: 16) {
                        Text("Create music anywhere.")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Loopa is a loop-based music production app that lets you layer instruments, record vocals, and create beats — all from your iPhone or iPad.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 12) {
                        featureRow(icon: "pianokeys", text: "Play piano, drums, bass & more")
                        featureRow(icon: "repeat", text: "Record and loop multiple tracks")
                        featureRow(icon: "mic.fill", text: "Add vocals over your beats")
                        featureRow(icon: "slider.horizontal.3", text: "Mix with solo, mute & volume")
                        featureRow(icon: "pencil.and.outline", text: "Edit notes in the piano roll")
                        featureRow(icon: "square.and.arrow.up", text: "Share your creations")
                    }
                    .padding(.horizontal, 30)
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Credits
                    VStack(spacing: 8) {
                        Text("Developed by")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("TishStudios")
                            .font(.headline)
                        
                        Link(destination: URL(string: "https://tishstudios.com")!) {
                            HStack(spacing: 4) {
                                Text("tishstudios.com")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .font(.subheadline)
                        }
                        
                        Text("© 2025 TishStudios. All rights reserved.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

#Preview {
    AboutView()
}

