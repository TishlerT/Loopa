import SwiftUI

/// Main content view for Loopa music production app
struct ContentView: View {
	@StateObject private var vm = TishViewModel()
	@State private var showSamples = false

	let leftChoices = ["Drum Kit", "808 Bass", "Piano", "E‑Piano", "Organ", "Strings", "Lead", "Pad"]
	let rightChoices = ["Piano", "E‑Piano", "Organ", "Strings", "Lead", "Pad", "Drum Kit", "808 Bass"]

	var body: some View {
		ZStack {
			// Background gradient
			Color.tishBackgroundGradient
				.ignoresSafeArea()
			
			VStack(spacing: 0) {
				// Error display
			if let err = vm.audioInitError {
					errorBanner(err)
			}
				
				// Top header with instrument pickers
				headerView
				
				// Loop visualization
				LoopVisualization(vm: vm)
					.padding(.horizontal, TishSpacing.lg)
					.padding(.vertical, TishSpacing.sm)
				
				// Transport controls
				TransportControls(vm: vm)
				
				// Keyboard (takes remaining space)
			KeyboardView(startNote: vm.startNote, count: vm.numSemitones) { event in
				switch event {
					case let .down(note, vel, isLeft):
						vm.noteOn(note: note, velocity: vel, isLeft: isLeft)
					case let .up(note, isLeft):
						vm.noteOff(note: note, isLeft: isLeft)
				}
			}
				.padding(.bottom, TishSpacing.sm)
		}
		}
		.preferredColorScheme(.dark)
		.sheet(isPresented: $showSamples) {
			SampleBrowserView()
	}
}

	// MARK: - Subviews
	
	private func errorBanner(_ message: String) -> some View {
		HStack {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundColor(.tishAccentTertiary)
			Text(message)
				.font(.tishCaption)
				.foregroundColor(.tishTextPrimary)
			Spacer()
		}
		.padding(.horizontal, TishSpacing.lg)
		.padding(.vertical, TishSpacing.sm)
		.background(Color.tishAccentTertiary.opacity(0.2))
	}

	private var headerView: some View {
		HStack(spacing: TishSpacing.md) {
			// Left instrument picker
			instrumentPicker(
				title: "L",
				selection: $vm.leftInstrument,
				choices: leftChoices,
				color: .tishAccent
			) { newValue in
				vm.changeLeftInstrument(newValue)
		}
			
			Spacer()
			
			// App title - "Loopa" with infinity symbol for "oo"
			VStack(spacing: 2) {
				HStack(spacing: 0) {
					Text("L")
						.font(.tishLargeTitle)
					Text("∞")
						.font(.system(size: 22, weight: .bold))
						.baselineOffset(2)
					Text("PA")
						.font(.tishLargeTitle)
				}
				.foregroundColor(.tishTextPrimary)
				.tracking(2)
				
				Text("MUSIC CREATOR")
					.font(.tishCaption)
					.foregroundColor(.tishTextSecondary)
					.tracking(2)
			}

			Spacer()
			
			// Right instrument picker
			instrumentPicker(
				title: "R",
				selection: $vm.rightInstrument,
				choices: rightChoices,
				color: .tishAccentSecondary
			) { newValue in
				vm.changeRightInstrument(newValue)
			}
			
			// Samples button
			Button {
				showSamples = true
			} label: {
				Image(systemName: "waveform")
					.font(.system(size: 18))
					.foregroundColor(.tishTextSecondary)
			}
			.padding(TishSpacing.sm)
			.background(Color.tishSurface)
			.cornerRadius(TishRadius.md)
		}
		.padding(.horizontal, TishSpacing.lg)
		.padding(.vertical, TishSpacing.sm)
				}
	
	private func instrumentPicker(
		title: String,
		selection: Binding<String>,
		choices: [String],
		color: Color,
		onChange: @escaping (String) -> Void
	) -> some View {
		Menu {
			ForEach(choices, id: \.self) { choice in
				Button {
					selection.wrappedValue = choice
					onChange(choice)
				} label: {
					HStack {
						Text(choice)
						if selection.wrappedValue == choice {
							Image(systemName: "checkmark")
			}
		}
	}
			}
		} label: {
			HStack(spacing: TishSpacing.xs) {
				Text(title)
					.font(.tishHeadline)
					.foregroundColor(color)
				
				VStack(alignment: .leading, spacing: 0) {
					Text(selection.wrappedValue)
						.font(.tishBody)
						.foregroundColor(.tishTextPrimary)
						.lineLimit(1)
				}
				
				Image(systemName: "chevron.down")
					.font(.system(size: 10))
					.foregroundColor(.tishTextSecondary)
			}
			.padding(.horizontal, TishSpacing.md)
			.padding(.vertical, TishSpacing.sm)
			.background(Color.tishSurface)
			.cornerRadius(TishRadius.md)
			.overlay(
				RoundedRectangle(cornerRadius: TishRadius.md)
					.stroke(color.opacity(0.3), lineWidth: 1)
			)
		}
	}
}

#Preview {
	ContentView()
}
