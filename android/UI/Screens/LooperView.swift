import SwiftUI

/// Main looper view with multi-track recording
struct LooperView: View {
	/// ViewModel injected from App via EnvironmentObject (single instance for whole app)
	@EnvironmentObject private var vm: LooperViewModel
	@State private var tracksVM: TracksViewModel?
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	/// Preview position during drag (nil when not dragging)
	@State private var seekPreviewPosition: Double? = nil
	
	/// New session confirmation alert
	@State private var showNewSessionAlert = false
	@State private var shouldClearAfterSave = false
	
	// MARK: - iPad Detection & Sizing
	
	private var isIPad: Bool { sizeClass == .regular }
	
	// Transport button sizes - enlarged for iPad
	private var transportButtonSize: CGFloat { isIPad ? 100 : 60 }
	private var transportIconSize: CGFloat { isIPad ? 36 : 22 }
	private var transportStopSize: CGFloat { isIPad ? 32 : 20 }
	private var transportPauseWidth: CGFloat { isIPad ? 11 : 7 }
	private var transportPauseHeight: CGFloat { isIPad ? 36 : 22 }
	private var transportStrokeWidth: CGFloat { isIPad ? 5 : 3 }
	private var transportSpacing: CGFloat { isIPad ? 36 : 20 }
	
	// Octave button width - enlarged for iPad
	private var octaveButtonWidth: CGFloat { isIPad ? 80 : 44 }
	private var octaveIconSize: CGFloat { isIPad ? 26 : 16 }
	private var octaveLabelSize: CGFloat { isIPad ? 14 : 9 }
	
	// Top bar sizes - enlarged for iPad
	private var topBarIconSize: CGFloat { isIPad ? 26 : 16 }
	private var topBarTextSize: CGFloat { isIPad ? 22 : 14 }
	private var topBarSmallTextSize: CGFloat { isIPad ? 15 : 10 }
	private var topBarButtonPadH: CGFloat { isIPad ? 20 : 12 }
	private var topBarButtonPadV: CGFloat { isIPad ? 16 : 8 }
	private var logoMainSize: CGFloat { isIPad ? 44 : 24 }
	private var logoInfinitySize: CGFloat { isIPad ? 56 : 32 }
	
	// Quantize button - enlarged for iPad
	private var quantizeTextSize: CGFloat { isIPad ? 36 : 22 }
	private var quantizeSubtextSize: CGFloat { isIPad ? 18 : 11 }
	
	var body: some View {
		GeometryReader { geo in
			ZStack {
				// Background
				LinearGradient(
					colors: [Color(hex: "0D0D1A"), Color(hex: "1A1A2E")],
					startPoint: .top,
					endPoint: .bottom
				)
				.ignoresSafeArea()
				
				VStack(spacing: 0) {
					// Error banner
					if let error = vm.audioError {
						errorBanner(error)
					}
					
					// Top controls
					topBar(geo: geo)
						.padding(.horizontal, isIPad ? 24 : 16)
						.padding(.top, isIPad ? 16 : 8)
					
					if isIPad {
						// iPad layout: Loop progress at top, transport in middle
						loopProgress
							.padding(.horizontal, 24)
							.padding(.top, 24)
							.padding(.bottom, 16)
						
						Spacer()
						
						// Transport controls centered in middle section (aligned with TRACKS button)
						transportControls
							.padding(.horizontal, 24)
						
						Spacer()
					} else {
						// iPhone layout: Loop progress + transport together
						VStack(spacing: 12) {
							loopProgress
							transportControls
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)
						
						Spacer()
					}
					
					// Keyboard or Vocal Waveform (depending on mode)
					if vm.isVocalMode {
						// Vocal mode: show waveform visualization
						VocalWaveformView(
							audioLevel: vm.vocalRecorder.currentLevel,
							isRecording: vm.isRecordingVocals,
							isCountingIn: vm.isCountingIn,
							countInBeat: vm.countInBeat
						)
						.frame(height: isIPad ? geo.size.height * 0.50 : nil)
						.padding(.horizontal, isIPad ? 24 : 16)
						.padding(.bottom, isIPad ? 16 : 8)
						.onAppear {
							vm.vocalRecorder.startMonitoring()
						}
						.onDisappear {
							vm.vocalRecorder.stopMonitoring()
						}
					} else {
						// Instrument mode: show keyboard with octave controls
						HStack(spacing: 0) {
							// Octave down button
							Button {
								vm.octaveDown()
							} label: {
								VStack(spacing: 4) {
									Image(systemName: "chevron.down")
										.font(.system(size: octaveIconSize, weight: .bold))
									Text("OCT")
										.font(.system(size: octaveLabelSize, weight: .bold))
								}
								.foregroundColor(vm.octaveOffset > -2 ? .white : .white.opacity(0.3))
								.frame(width: octaveButtonWidth)
								.frame(maxHeight: .infinity)
								.background(Color(hex: "2A2A4A"))
							}
							.disabled(vm.octaveOffset <= -2)
							
							// Keyboard
							VStack(spacing: 0) {
								// Octave indicator (hidden for drum kit)
								if !vm.currentInstrument.isDrumKit {
									Text(vm.currentOctaveName)
										.font(.system(size: isIPad ? 14 : 11, weight: .bold, design: .monospaced))
										.foregroundColor(.white.opacity(0.5))
										.frame(height: isIPad ? 24 : 16)
								} else {
									Spacer().frame(height: isIPad ? 24 : 16)
								}
								
								FullKeyboardView(
									startNote: vm.startNote,
									keyCount: vm.keyCount,
									isDrumKit: vm.currentInstrument.isDrumKit
								) { event in
									switch event {
									case .down(let note, let velocity):
										vm.noteOn(note, velocity: velocity)
									case .up(let note):
										vm.noteOff(note)
									}
								}
							}
							
							// Octave up button
							Button {
								vm.octaveUp()
							} label: {
								VStack(spacing: 4) {
									Image(systemName: "chevron.up")
										.font(.system(size: octaveIconSize, weight: .bold))
									Text("OCT")
										.font(.system(size: octaveLabelSize, weight: .bold))
								}
								.foregroundColor(vm.octaveOffset < 2 ? .white : .white.opacity(0.3))
								.frame(width: octaveButtonWidth)
								.frame(maxHeight: .infinity)
								.background(Color(hex: "2A2A4A"))
							}
							.disabled(vm.octaveOffset >= 2)
						}
						// On iPad, constrain keyboard height to ~50% of screen
						.frame(height: isIPad ? geo.size.height * 0.50 : nil)
						.padding(.bottom, isIPad ? 16 : 8)
					}
				}
				
				// Right-edge Tracks button
				tracksButton(geo: geo)
			}
		}
		.preferredColorScheme(.dark)
		.onAppear {
			tracksVM = TracksViewModel(looperVM: vm)
		}
		.onChange(of: vm.isVocalMode) { _, isVocal in
			// Start/stop input monitoring when vocal mode changes
			if isVocal {
				vm.vocalRecorder.startMonitoring()
			} else {
				vm.vocalRecorder.stopMonitoring()
			}
		}
		// On iPad, use fullScreenCover for TracksView; on iPhone, use sheet
		.sheet(isPresented: Binding(
			get: { vm.showingTracksSheet && sizeClass != .regular },
			set: { if !$0 { vm.showingTracksSheet = false } }
		)) {
			if let tracksVM = tracksVM {
				TracksView(vm: tracksVM)
					.presentationDetents([.medium, .large])
			}
		}
		.fullScreenCover(isPresented: Binding(
			get: { vm.showingTracksSheet && sizeClass == .regular },
			set: { if !$0 { vm.showingTracksSheet = false } }
		)) {
			if let tracksVM = tracksVM {
				TracksView(vm: tracksVM)
			}
		}
		.fullScreenCover(isPresented: $vm.showingBPMEditor) {
			BPMEditorView(bpm: $vm.bpm)
		}
		.fullScreenCover(item: $vm.selectedTrackForFocus) { track in
			TrackFocusViewWrapper(track: track, looperVM: vm)
		}
		.sheet(isPresented: $vm.showingSaveSheet) {
			SaveSessionSheet(
				sessionName: vm.currentSessionName.isEmpty ? "Session \(vm.savedSessions.count + 1)" : vm.currentSessionName,
				onSave: { name in
					vm.saveCurrentSession(name: name)
					vm.showingSaveSheet = false
					// If triggered from New Session, clear after saving
					if shouldClearAfterSave {
						vm.clearAll()
						vm.currentSessionName = ""
						shouldClearAfterSave = false
					}
				},
				onCancel: {
					vm.showingSaveSheet = false
					shouldClearAfterSave = false
				}
			)
			.presentationDetents([.height(200)])
		}
		.sheet(isPresented: $vm.showingLoadSheet) {
			LoadSessionSheet(
				sessions: vm.savedSessions,
				onLoad: { session in
					vm.loadSession(session)
					vm.showingLoadSheet = false
				},
				onDelete: { session in
					vm.deleteSession(session)
				},
				onCancel: {
					vm.showingLoadSheet = false
				}
			)
			.presentationDetents([.medium, .large])
		}
		.alert("Microphone Access Required", isPresented: $vm.showMicPermissionAlert) {
			Button("Open Settings") {
				if let url = URL(string: UIApplication.openSettingsURLString) {
					UIApplication.shared.open(url)
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("To record vocals, please allow microphone access in Settings.")
		}
		.alert("Headphones Recommended", isPresented: $vm.showHeadphoneRecommendation) {
			Button("Continue Recording") {
				vm.continueVocalRecordingAfterRecommendation()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("For best results, use headphones while recording vocals. This prevents the backing tracks from being picked up by your microphone.")
		}
		.alert("Save Session?", isPresented: $showNewSessionAlert) {
			Button("Save") {
				shouldClearAfterSave = true
				vm.showingSaveSheet = true
			}
			Button("Don't Save", role: .destructive) {
				vm.clearAll()
				vm.currentSessionName = ""
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Do you want to save your current session before starting a new one?")
		}
		.sheet(isPresented: $vm.showingSettings) {
			SettingsView()
		}
	}
	
	// MARK: - Right-edge Tracks Button
	
	private func tracksButton(geo: GeometryProxy) -> some View {
		// On iPad, position centered vertically (aligned with transport controls in middle)
		let tracksIconSize: CGFloat = isIPad ? 24 : 14
		let tracksLabelSize: CGFloat = isIPad ? 14 : 8
		let tracksCountSize: CGFloat = isIPad ? 22 : 12
		let tracksPadV: CGFloat = isIPad ? 28 : 16
		let tracksPadH: CGFloat = isIPad ? 18 : 8
		let tracksCorner: CGFloat = isIPad ? 20 : 12
		
		// On iPad: account for loop progress at top and keyboard at bottom
		// Loop progress is ~130pt, keyboard is 50% of screen
		let loopAndTopBarHeight: CGFloat = isIPad ? 180 : 0  // approximate
		let keyboardHeight: CGFloat = isIPad ? geo.size.height * 0.50 : 0
		
		return VStack {
			if isIPad {
				// Top spacer accounts for loop progress section
				Spacer()
					.frame(height: loopAndTopBarHeight)
			}
			
			Spacer()
			
			HStack {
				Spacer()
				
				Button {
					vm.showingTracksSheet = true
				} label: {
					VStack(spacing: isIPad ? 8 : 6) {
						Image(systemName: "chevron.left")
							.font(.system(size: tracksIconSize, weight: .bold))
						
						Text("TRACKS")
							.font(.system(size: tracksLabelSize, weight: .bold))
							.tracking(1)
						
						if !vm.tracks.isEmpty {
							Text("\(vm.tracks.count)")
								.font(.system(size: tracksCountSize, weight: .bold, design: .rounded))
								.foregroundColor(Color(hex: "00FFCC"))
						}
					}
					.foregroundColor(.white.opacity(0.8))
					.padding(.vertical, tracksPadV)
					.padding(.horizontal, tracksPadH)
					.background(
						RoundedRectangle(cornerRadius: tracksCorner)
							.fill(Color(hex: "2A2A4A"))
							.shadow(color: .black.opacity(0.3), radius: isIPad ? 6 : 4, x: -2, y: 0)
					)
				}
				.accessibilityIdentifier("tracksButton")
				.padding(.trailing, isIPad ? 8 : 0)
				.offset(x: isIPad ? 0 : 4) // Only offset on iPhone for edge effect
			}
			
			Spacer()
			
			if isIPad {
				// Bottom spacer accounts for keyboard
				Spacer()
					.frame(height: keyboardHeight)
			}
		}
	}
	
	// MARK: - Top Bar
	
	private func topBar(geo: GeometryProxy) -> some View {
		HStack(spacing: isIPad ? 16 : 12) {
			// Instrument picker (disabled during recording)
			Menu {
				ForEach(Instrument.allCases) { instrument in
					Button {
						vm.selectInstrument(instrument)
					} label: {
						HStack {
							Image(systemName: instrument.icon)
							Text(instrument.rawValue)
							if vm.currentInstrument == instrument && !vm.isVocalMode {
								Spacer()
								Image(systemName: "checkmark")
							}
						}
					}
				}
				
				Divider()
				
				// Vocals/Microphone option
				Button {
					vm.enableVocalMode()
				} label: {
					HStack {
						Image(systemName: "mic.fill")
						Text("Vocals")
						if vm.isVocalMode {
							Spacer()
							Image(systemName: "checkmark")
						}
					}
				}
			} label: {
				HStack(spacing: isIPad ? 10 : 8) {
					Image(systemName: vm.isVocalMode ? "mic.fill" : vm.currentInstrument.icon)
						.font(.system(size: topBarIconSize))
					Text(vm.isVocalMode ? "Vocals" : vm.currentInstrument.rawValue)
						.font(.system(size: topBarTextSize, weight: .semibold))
					Image(systemName: "chevron.down")
						.font(.system(size: isIPad ? 11 : 9))
				}
				.foregroundColor(vm.isRecording || vm.isRecordingVocals ? .white.opacity(0.4) : .white)
				.padding(.horizontal, topBarButtonPadH)
				.padding(.vertical, topBarButtonPadV)
				.background(vm.isRecording || vm.isRecordingVocals ? Color(hex: "1A1A2A") : (vm.isVocalMode ? Color(hex: "3A2A4A") : Color(hex: "2A2A4A")))
				.cornerRadius(isIPad ? 10 : 8)
			}
			.disabled(vm.isRecording || vm.isRecordingVocals)
			.allowsHitTesting(!vm.isRecording && !vm.isRecordingVocals)
			
			Spacer()
			
			// Title - "Loopa" with infinity symbol for "oo"
			HStack(spacing: 0) {
				Text("L")
					.font(.system(size: logoMainSize, weight: .black, design: .rounded))
				Text("∞")
					.font(.system(size: logoInfinitySize, weight: .black))
					.baselineOffset(isIPad ? 3 : 2)
				Text("PA")
					.font(.system(size: logoMainSize, weight: .black, design: .rounded))
			}
			.foregroundColor(.white)
			
			Spacer()
			
			// BPM button (opens editor)
			Button {
				vm.showingBPMEditor = true
			} label: {
				HStack(spacing: isIPad ? 6 : 4) {
					Text("BPM")
						.font(.system(size: topBarSmallTextSize, weight: .medium))
						.foregroundColor(.white.opacity(0.5))
					Text("\(Int(vm.bpm))")
						.font(.system(size: isIPad ? 20 : 16, weight: .bold, design: .monospaced))
						.foregroundColor(.white)
				}
				.padding(.horizontal, topBarButtonPadH)
				.padding(.vertical, topBarButtonPadV)
				.background(Color(hex: "2A2A4A"))
				.cornerRadius(isIPad ? 10 : 8)
			}
			.accessibilityIdentifier("bpmButton")
			
			// Metronome toggle
			Button {
				vm.toggleMetronome()
			} label: {
				Image(systemName: vm.isMetronomeOn ? "metronome.fill" : "metronome")
					.font(.system(size: isIPad ? 24 : 18))
					.foregroundColor(vm.isMetronomeOn ? Color(hex: "00FFCC") : .white.opacity(0.5))
			}
			.padding(topBarButtonPadV)
			.background(Color(hex: "2A2A4A"))
			.cornerRadius(isIPad ? 10 : 8)
			
			// Bar count picker
			Menu {
				ForEach(BarCount.allCases) { count in
					Button {
						vm.setBarCount(count)
					} label: {
						HStack {
							Text(count.displayName)
							if vm.barCount == count {
								Spacer()
								Image(systemName: "checkmark")
							}
						}
					}
				}
			} label: {
				HStack(spacing: isIPad ? 6 : 4) {
					Text("\(vm.barCount.rawValue)")
						.font(.system(size: isIPad ? 20 : 16, weight: .bold))
					Text("BARS")
						.font(.system(size: isIPad ? 11 : 9, weight: .medium))
				}
				.foregroundColor(.white)
				.padding(.horizontal, isIPad ? 14 : 10)
				.padding(.vertical, topBarButtonPadV)
				.background(Color(hex: "2A2A4A"))
				.cornerRadius(isIPad ? 10 : 8)
			}
			
			// Save/Load/Share menu
			Menu {
				Button {
					if vm.tracks.isEmpty {
						// No tracks, just reset session name
						vm.currentSessionName = ""
					} else {
						// Show save confirmation
						showNewSessionAlert = true
					}
				} label: {
					Label("New Session", systemImage: "plus")
				}
				
				Divider()
				
				Button {
					vm.showingSaveSheet = true
				} label: {
					Label("Save Session", systemImage: "square.and.arrow.down")
				}
				.disabled(vm.tracks.isEmpty)
				
				Button {
					vm.loadSavedSessions()
					vm.showingLoadSheet = true
				} label: {
					Label("Load Session", systemImage: "folder")
				}
				
				if !vm.tracks.isEmpty {
					Divider()
					
					Button {
						vm.shareCurrentSession()
					} label: {
						Label("Share Beat", systemImage: "square.and.arrow.up")
					}
					
					Button {
						vm.exportToAudio()
					} label: {
						Label("Export to Audio", systemImage: "waveform")
					}
					.disabled(vm.isExporting)
					
					Divider()
					
					Button(role: .destructive) {
						vm.clearAll()
					} label: {
						Label("Clear All", systemImage: "trash")
					}
				}
				
				Divider()
				
				Button {
					vm.showingSettings = true
				} label: {
					Label("Settings", systemImage: "gear")
				}
			} label: {
				ZStack {
					Image(systemName: "ellipsis.circle")
						.font(.system(size: isIPad ? 24 : 18))
						.foregroundColor(.white.opacity(0.7))
						.opacity(vm.isExporting ? 0 : 1)
					
					if vm.isExporting {
						ProgressView()
							.progressViewStyle(CircularProgressViewStyle(tint: .white))
							.scaleEffect(isIPad ? 1.0 : 0.8)
					}
				}
			}
			.padding(topBarButtonPadV)
			.background(Color(hex: "2A2A4A"))
			.cornerRadius(isIPad ? 10 : 8)
		}
	}
	
	// MARK: - Beat Color Helper
	
	/// Determines the color for a beat indicator
	/// All beats are treated equally regardless of track length or looping status
	private func beatIndicatorColor(beat: Int, isCurrentBeat: Bool, isDownbeat: Bool) -> Color {
		if isCurrentBeat {
			return Color(hex: "00FFCC")
		}
		return isDownbeat ? Color.white.opacity(0.3) : Color.white.opacity(0.15)
	}
	
	// MARK: - Loop Progress
	
	private var loopProgress: some View {
		let canSeek = !vm.isRecording && !vm.isRecordingVocals && !vm.isCountingIn
		
		// Calculate which beat to highlight (preview position takes precedence)
		// Uses synchronizedBeat for audio-visual sync (reads directly from looper timing)
		let displayBeat: Int = {
			if let previewPos = seekPreviewPosition {
				let secondsPerBeat = 60.0 / vm.bpm
				let rawBeat = Int(previewPos / secondsPerBeat)
				return vm.totalBeats > 0 ? rawBeat % vm.totalBeats : 0
			}
			// Use synchronized beat for precise audio-visual alignment
			return vm.synchronizedBeat
		}()
		
		// Calculate progress fraction for the bar (preview position takes precedence)
		// Uses synchronizedProgressFraction for audio-visual sync (reads directly from looper timing)
		let displayFraction: Double = {
			if let previewPos = seekPreviewPosition {
				guard vm.loopLengthSeconds > 0 else { return 0 }
				return previewPos / vm.loopLengthSeconds
			}
			// Use synchronized progress fraction for precise audio-visual alignment
			// This reads directly from the looper's timing, bypassing Combine latency
			return vm.synchronizedProgressFraction
		}()
		
		let beatIndicatorHeight: CGFloat = isIPad ? 48 : 24
		let beatIndicatorSmallHeight: CGFloat = isIPad ? 32 : 16
		let progressBarHeight: CGFloat = isIPad ? 16 : 8
		let loopPadH: CGFloat = isIPad ? 40 : 20
		let loopPadV: CGFloat = isIPad ? 36 : 16
		
		return VStack(spacing: isIPad ? 12 : 8) {
			// Beat indicators (tappable) with color-coding for track looping
			GeometryReader { geo in
				HStack(spacing: isIPad ? 6 : 4) {
					ForEach(0..<vm.totalBeats, id: \.self) { beat in
						let isCurrentBeat = displayBeat == beat && (vm.isPlaying || seekPreviewPosition != nil || vm.isPaused)
						let isDownbeat = beat % 4 == 0
						
						// Determine beat color based on track coverage
						let beatColor = beatIndicatorColor(
							beat: beat,
							isCurrentBeat: isCurrentBeat,
							isDownbeat: isDownbeat
						)
						
						RoundedRectangle(cornerRadius: isIPad ? 4 : 3)
							.fill(beatColor)
							.frame(height: isDownbeat ? beatIndicatorHeight : beatIndicatorSmallHeight)
							.contentShape(Rectangle())
							.onTapGesture {
								guard canSeek else { return }
								// Calculate position for start of this beat
								let secondsPerBeat = 60.0 / vm.bpm
								let targetPosition = Double(beat) * secondsPerBeat
								vm.seekToPosition(targetPosition)
							}
					}
				}
			}
			.frame(height: isIPad ? 52 : 28)
			
			// Progress bar (tappable and draggable to seek)
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
						.fill(Color.white.opacity(0.1))
					
					RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
						.fill(
							LinearGradient(
								colors: [Color(hex: "00FFCC"), Color(hex: "00CCFF")],
								startPoint: .leading,
								endPoint: .trailing
							)
						)
						.frame(width: geo.size.width * displayFraction)
						// No animation - instant updates ensure audio-visual sync at loop boundaries
				}
				.contentShape(Rectangle()) // Make entire area tappable
				.gesture(
					DragGesture(minimumDistance: 0)
						.onChanged { value in
							guard canSeek else { return }
							let fraction = max(0, min(1, value.location.x / geo.size.width))
							seekPreviewPosition = fraction * vm.loopLengthSeconds
						}
						.onEnded { value in
							guard canSeek else { return }
							let fraction = max(0, min(1, value.location.x / geo.size.width))
							let targetPosition = fraction * vm.loopLengthSeconds
							seekPreviewPosition = nil
							vm.seekToPosition(targetPosition)
						}
				)
			}
			.frame(height: progressBarHeight)
		}
		.padding(.horizontal, loopPadH)
		.padding(.vertical, loopPadV)
		.background(Color(hex: "1A1A30").opacity(0.8))
		.cornerRadius(isIPad ? 20 : 16)
	}
	
	// MARK: - Transport Controls
	
	private var transportControls: some View {
		HStack(spacing: transportSpacing) {
			Spacer()
			
			// Record button (handles both instrument and vocal recording based on mode)
			Button {
				if vm.isVocalMode {
					vm.toggleVocalRecordingWithResume()
				} else {
					vm.toggleRecordingWithResume()
				}
			} label: {
				ZStack {
					Circle()
						.fill(vm.isCountingIn ? Color(hex: "FF9500") : 
							  (vm.isRecording || vm.isRecordingVocals) ? Color.red : 
							  (vm.isVocalMode ? Color(hex: "FF9500") : Color(hex: "FF3B30")))
						.frame(width: transportButtonSize, height: transportButtonSize)
					
					if vm.isCountingIn {
						Text("\(vm.countInBeat)")
							.font(.system(size: isIPad ? 36 : 28, weight: .bold, design: .rounded))
							.foregroundColor(.white)
					} else if vm.isRecording || vm.isRecordingVocals {
						RoundedRectangle(cornerRadius: isIPad ? 5 : 4)
							.fill(Color.white)
							.frame(width: transportStopSize, height: transportStopSize)
					} else if vm.isVocalMode {
						Image(systemName: "mic.fill")
							.font(.system(size: transportIconSize))
							.foregroundColor(.white)
					} else {
						Circle()
							.fill(Color.white)
							.frame(width: transportStopSize, height: transportStopSize)
					}
				}
				.shadow(color: vm.isCountingIn ? .orange.opacity(0.5) : 
						(vm.isRecording || vm.isRecordingVocals) ? .red.opacity(0.5) : .clear, radius: isIPad ? 16 : 12)
				.animation(.easeInOut(duration: 0.15), value: vm.countInBeat)
			}
			.accessibilityIdentifier("recordButton")
			
			// Play/Pause button
			Button {
				vm.togglePlayPause()
			} label: {
				ZStack {
					Circle()
						.stroke(vm.isPlaying ? Color(hex: "34C759") : (vm.isPaused ? Color(hex: "FF9500") : Color(hex: "4A4A6A")), lineWidth: transportStrokeWidth)
						.frame(width: transportButtonSize, height: transportButtonSize)
					
					Circle()
						.fill(vm.isPlaying ? Color(hex: "34C759").opacity(0.2) : (vm.isPaused ? Color(hex: "FF9500").opacity(0.2) : Color(hex: "2A2A4A")))
						.frame(width: transportButtonSize, height: transportButtonSize)
					
					if vm.isPlaying {
						HStack(spacing: isIPad ? 9 : 7) {
							RoundedRectangle(cornerRadius: isIPad ? 3 : 2)
								.fill(Color.white)
								.frame(width: transportPauseWidth, height: transportPauseHeight)
							RoundedRectangle(cornerRadius: isIPad ? 3 : 2)
								.fill(Color.white)
								.frame(width: transportPauseWidth, height: transportPauseHeight)
						}
					} else {
						Image(systemName: "play.fill")
							.font(.system(size: transportIconSize))
							.foregroundColor(.white)
							.offset(x: isIPad ? 3 : 2)
					}
				}
			}
			.accessibilityIdentifier("playPauseButton")
			
			// Restart button
			Button {
				vm.restartPlayback()
			} label: {
				ZStack {
					Circle()
						.stroke(Color(hex: "00CCFF"), lineWidth: transportStrokeWidth)
						.frame(width: transportButtonSize, height: transportButtonSize)
					
					Circle()
						.fill(Color(hex: "00CCFF").opacity(0.2))
						.frame(width: transportButtonSize, height: transportButtonSize)
					
					Image(systemName: "arrow.counterclockwise")
						.font(.system(size: transportIconSize, weight: .bold))
						.foregroundColor(.white)
				}
			}
			.accessibilityIdentifier("restartButton")
			.disabled(vm.tracks.isEmpty && !vm.isRecording && !vm.isRecordingVocals && !vm.isPaused && !vm.isPlaying)
			.opacity(vm.tracks.isEmpty && !vm.isRecording && !vm.isRecordingVocals && !vm.isPaused && !vm.isPlaying ? 0.5 : 1)
			
			// Quantize button
			Button {
				vm.cycleQuantization()
			} label: {
				VStack(spacing: isIPad ? 3 : 2) {
					Text("Q")
						.font(.system(size: quantizeTextSize, weight: .bold, design: .rounded))
					Text(vm.quantizeDivision.rawValue)
						.font(.system(size: quantizeSubtextSize, weight: .bold, design: .monospaced))
				}
				.foregroundColor(vm.quantizeDivision == .off ? .white.opacity(0.5) : Color(hex: "00FFCC"))
				.frame(width: transportButtonSize, height: transportButtonSize)
				.background(
					RoundedRectangle(cornerRadius: isIPad ? 16 : 12)
						.fill(Color(hex: "2A2A4A"))
						.overlay(
							RoundedRectangle(cornerRadius: isIPad ? 16 : 12)
								.stroke(vm.quantizeDivision == .off ? Color.clear : Color(hex: "00FFCC").opacity(0.5), lineWidth: 1)
						)
				)
			}
			.accessibilityIdentifier("quantizeButton")
			
			Spacer()
		}
		.padding(.vertical, isIPad ? 12 : 8)
	}
	
	// MARK: - Error Banner
	
	private func errorBanner(_ message: String) -> some View {
		HStack {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundColor(.orange)
			Text(message)
				.font(.system(size: 13))
				.foregroundColor(.white)
			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(Color.orange.opacity(0.2))
	}
}

// MARK: - Save Session Sheet

struct SaveSessionSheet: View {
	@State var sessionName: String
	let onSave: (String) -> Void
	let onCancel: () -> Void
	
	var body: some View {
		NavigationView {
			VStack(spacing: 20) {
				TextField("Session Name", text: $sessionName)
					.textFieldStyle(.roundedBorder)
					.font(.system(size: 18))
					.padding(.horizontal)
				
				Spacer()
			}
			.padding(.top, 20)
			.navigationTitle("Save Session")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: onCancel)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						onSave(sessionName)
					}
					.disabled(sessionName.isEmpty)
				}
			}
		}
	}
}

// MARK: - Load Session Sheet

struct LoadSessionSheet: View {
	let sessions: [SavedSession]
	let onLoad: (SavedSession) -> Void
	let onDelete: (SavedSession) -> Void
	let onCancel: () -> Void
	
	var body: some View {
		NavigationView {
			List {
				if sessions.isEmpty {
					Text("No saved sessions")
						.foregroundColor(.secondary)
						.padding()
				} else {
					ForEach(sessions) { session in
						Button {
							onLoad(session)
						} label: {
							VStack(alignment: .leading, spacing: 4) {
								Text(session.name)
									.font(.headline)
									.foregroundColor(.primary)
								
								HStack(spacing: 12) {
									Label("\(session.tracks.count) tracks", systemImage: "music.note.list")
									Label("\(Int(session.bpm)) BPM", systemImage: "metronome")
									Label("\(session.barCount) bars", systemImage: "repeat")
								}
								.font(.caption)
								.foregroundColor(.secondary)
								
								Text(session.lastModifiedAt, style: .relative)
									.font(.caption2)
									.foregroundColor(.secondary)
							}
							.padding(.vertical, 4)
						}
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							Button(role: .destructive) {
								onDelete(session)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
				}
			}
			.navigationTitle("Load Session")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: onCancel)
				}
			}
		}
	}
}

#Preview {
	LooperView()
		.environmentObject(LooperViewModel())
}
