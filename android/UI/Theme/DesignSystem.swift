import SwiftUI

// MARK: - Color Palette

/// Tish88 Design System - Dark studio aesthetic with neon accents
extension Color {
	
	// MARK: - Background Colors
	
	/// Primary background - deep charcoal
	static let tishBackground = Color(hex: "0D0D0D")
	
	/// Secondary background - slightly lighter for cards/surfaces
	static let tishSurface = Color(hex: "1A1A1A")
	
	/// Tertiary background - for elevated elements
	static let tishElevated = Color(hex: "242424")
	
	// MARK: - Accent Colors
	
	/// Primary accent - electric cyan
	static let tishAccent = Color(hex: "00E5FF")
	
	/// Secondary accent - hot magenta
	static let tishAccentSecondary = Color(hex: "FF0080")
	
	/// Tertiary accent - warm amber for warnings/highlights
	static let tishAccentTertiary = Color(hex: "FFB800")
	
	// MARK: - Semantic Colors
	
	/// Recording state - vibrant red
	static let tishRecording = Color(hex: "FF3B3B")
	
	/// Playing state - bright green
	static let tishPlaying = Color(hex: "00FF88")
	
	/// Overdub state - purple blend
	static let tishOverdub = Color(hex: "B366FF")
	
	/// Metronome beat flash
	static let tishBeat = Color(hex: "FFFFFF").opacity(0.9)
	
	/// Downbeat flash - more intense
	static let tishDownbeat = Color(hex: "00E5FF")
	
	// MARK: - Text Colors
	
	/// Primary text - near white
	static let tishTextPrimary = Color(hex: "F5F5F5")
	
	/// Secondary text - muted gray
	static let tishTextSecondary = Color(hex: "9E9E9E")
	
	/// Tertiary text - very muted
	static let tishTextTertiary = Color(hex: "616161")
	
	// MARK: - Keyboard Colors
	
	/// White key default
	static let tishKeyWhite = Color(hex: "F8F8F8")
	
	/// White key pressed
	static let tishKeyWhitePressed = Color(hex: "00E5FF").opacity(0.3)
	
	/// Black key default
	static let tishKeyBlack = Color(hex: "1A1A1A")
	
	/// Black key pressed
	static let tishKeyBlackPressed = Color(hex: "00E5FF").opacity(0.5)
	
	/// Key border/separator
	static let tishKeyBorder = Color(hex: "333333")
	
	// MARK: - Gradients
	
	/// Background gradient - subtle depth
	static var tishBackgroundGradient: LinearGradient {
		LinearGradient(
			colors: [
				Color(hex: "0D0D0D"),
				Color(hex: "141418"),
				Color(hex: "0D0D0D")
			],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}
	
	/// Accent gradient - for buttons and highlights
	static var tishAccentGradient: LinearGradient {
		LinearGradient(
			colors: [
				Color(hex: "00E5FF"),
				Color(hex: "00B8D4")
			],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}
	
	/// Recording gradient - pulsing red
	static var tishRecordingGradient: LinearGradient {
		LinearGradient(
			colors: [
				Color(hex: "FF3B3B"),
				Color(hex: "CC0000")
			],
			startPoint: .top,
			endPoint: .bottom
		)
	}
}

// MARK: - Hex Color Extension

extension Color {
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)
		let a, r, g, b: UInt64
		switch hex.count {
		case 3: // RGB (12-bit)
			(a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
		case 6: // RGB (24-bit)
			(a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
		case 8: // ARGB (32-bit)
			(a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
		default:
			(a, r, g, b) = (1, 1, 1, 0)
		}
		
		self.init(
			.sRGB,
			red: Double(r) / 255,
			green: Double(g) / 255,
			blue: Double(b) / 255,
			opacity: Double(a) / 255
		)
	}
}

// MARK: - Typography

extension Font {
	
	/// Large title - app name, major headers
	static let tishLargeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
	
	/// Title - section headers
	static let tishTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
	
	/// Headline - button labels, important text
	static let tishHeadline = Font.system(size: 16, weight: .semibold, design: .rounded)
	
	/// Body - regular text
	static let tishBody = Font.system(size: 14, weight: .regular, design: .default)
	
	/// Caption - secondary information
	static let tishCaption = Font.system(size: 12, weight: .regular, design: .default)
	
	/// Mono - BPM, timing displays
	static let tishMono = Font.system(size: 16, weight: .medium, design: .monospaced)
	
	/// Mono large - big BPM display
	static let tishMonoLarge = Font.system(size: 24, weight: .bold, design: .monospaced)
}

// MARK: - Spacing

enum TishSpacing {
	/// 4pt
	static let xs: CGFloat = 4
	/// 8pt
	static let sm: CGFloat = 8
	/// 12pt
	static let md: CGFloat = 12
	/// 16pt
	static let lg: CGFloat = 16
	/// 24pt
	static let xl: CGFloat = 24
	/// 32pt
	static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum TishRadius {
	/// 4pt - subtle rounding
	static let sm: CGFloat = 4
	/// 8pt - standard buttons
	static let md: CGFloat = 8
	/// 12pt - cards and containers
	static let lg: CGFloat = 12
	/// 16pt - large cards
	static let xl: CGFloat = 16
	/// Full circle
	static let full: CGFloat = 9999
}

// MARK: - Shadows

extension View {
	/// Subtle glow effect for pressed/active states
	func tishGlow(color: Color = .tishAccent, radius: CGFloat = 8) -> some View {
		self.shadow(color: color.opacity(0.5), radius: radius, x: 0, y: 0)
	}
	
	/// Elevation shadow for cards
	func tishElevation(level: Int = 1) -> some View {
		let radius = CGFloat(level * 4)
		let opacity = Double(level) * 0.1
		return self.shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: radius / 2)
	}
}

// MARK: - Button Styles

struct TishButtonStyle: ButtonStyle {
	var isActive: Bool = false
	var color: Color = .tishAccent
	
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.tishHeadline)
			.foregroundColor(isActive ? .tishBackground : .tishTextPrimary)
			.padding(.horizontal, TishSpacing.lg)
			.padding(.vertical, TishSpacing.sm)
			.background(
				RoundedRectangle(cornerRadius: TishRadius.md)
					.fill(isActive ? color : Color.tishSurface)
			)
			.overlay(
				RoundedRectangle(cornerRadius: TishRadius.md)
					.stroke(color.opacity(isActive ? 0 : 0.5), lineWidth: 1)
			)
			.scaleEffect(configuration.isPressed ? 0.95 : 1.0)
			.animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
	}
}

struct TishTransportButtonStyle: ButtonStyle {
	var isActive: Bool = false
	var activeColor: Color = .tishAccent
	
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.foregroundColor(isActive ? activeColor : .tishTextSecondary)
			.padding(TishSpacing.sm)
			.background(
				Circle()
					.fill(isActive ? activeColor.opacity(0.2) : Color.tishSurface)
			)
			.overlay(
				Circle()
					.stroke(isActive ? activeColor : Color.tishKeyBorder, lineWidth: 1)
			)
			.scaleEffect(configuration.isPressed ? 0.9 : 1.0)
			.animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
			.tishGlow(color: activeColor, radius: isActive ? 6 : 0)
	}
}

