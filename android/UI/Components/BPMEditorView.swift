import SwiftUI

/// Simplified BPM Editor with +/- 5 buttons and tap-to-type
struct BPMEditorView: View {
    @Binding var bpm: Double
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private let minBPM: Double = 40
    private let maxBPM: Double = 240
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "0D0D1A")
                .ignoresSafeArea()
                .onTapGesture {
                    if isEditing {
                        applyTextValue()
                        isEditing = false
                    } else {
                        dismiss()
                    }
                }
            
            VStack(spacing: 0) {
                // Close button at top
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(20)
                }
                
                Spacer()
                
                // Main content - centered
                HStack(spacing: 40) {
                    // Minus button
                    Button {
                        adjustBPM(by: -5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(bpm <= minBPM ? .white.opacity(0.2) : .white)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .disabled(bpm <= minBPM)
                    
                    // BPM display (tappable to edit)
                    VStack(spacing: 8) {
                        if isEditing {
                            TextField("", text: $textValue)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 96, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 200)
                                .focused($isTextFieldFocused)
                                .onSubmit {
                                    applyTextValue()
                                    isEditing = false
                                }
                                .onAppear {
                                    isTextFieldFocused = true
                                }
                        } else {
                            Text("\(Int(bpm))")
                                .font(.system(size: 96, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .onTapGesture {
                                    textValue = "\(Int(bpm))"
                                    isEditing = true
                                }
                        }
                        
                        Text("BPM")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    // Plus button
                    Button {
                        adjustBPM(by: 5)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(bpm >= maxBPM ? .white.opacity(0.2) : .white)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .disabled(bpm >= maxBPM)
                }
                
                Spacer()
                
                // Hint text
                Text("Tap the number to type a value")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 40)
            }
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if !focused && isEditing {
                applyTextValue()
                isEditing = false
            }
        }
    }
    
    // MARK: - Actions
    
    private func adjustBPM(by delta: Double) {
        let newValue = max(minBPM, min(maxBPM, bpm + delta))
        bpm = newValue
        HapticManager.shared.selectionChanged()
    }
    
    private func applyTextValue() {
        guard let value = Double(textValue) else {
            return
        }
        let clamped = max(minBPM, min(maxBPM, value))
        bpm = clamped
        HapticManager.shared.selectionChanged()
    }
}

#Preview {
    BPMEditorView(bpm: .constant(120))
}
