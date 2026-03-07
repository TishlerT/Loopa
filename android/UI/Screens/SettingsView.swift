import SwiftUI

/// App settings and legal links
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAbout = false
    
    private let supportEmail = "support@tishstudios.com"
    private let privacyPolicyURL = URL(string: "https://tishstudios.com/privacy")!
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - About Section
                Section("About") {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Label("About Loopa", systemImage: "info.circle.fill")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("v\(appVersion)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Legal Section
                Section("Legal") {
                    Link(destination: privacyPolicyURL) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Support Section
                Section("Support") {
                    Link(destination: URL(string: "mailto:\(supportEmail)")!) {
                        HStack {
                            Label("Contact Support", systemImage: "envelope.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Credits Section
                Section("Credits") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developed by TishStudios")
                            .font(.footnote)
                        Text("SoundFont: FluidR3 GM (Public Domain)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
}

#Preview {
    SettingsView()
}
