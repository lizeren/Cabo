import SwiftUI

// MARK: - Game Constants
enum GameConstants {
    static let cardsPerPlayer = 4
    static let initialPeeks = 2
    static let reactionWindowSeconds: TimeInterval = 5
    static let turnTimeLimitSeconds: TimeInterval = 60
    static let minPlayers = 2
    static let maxPlayers = 4
    
    // Server configuration - change this to your Mac's IP for device testing
    static let serverIP = "10.0.0.49"  // Use your Mac's local IP or "localhost" for simulator
}

// MARK: - Layout Constants
enum LayoutConstants {
    static let cardWidth: CGFloat = 50
    static let cardHeight: CGFloat = 70
    static let cardCornerRadius: CGFloat = 8
    static let cardSpacing: CGFloat = 8
    
    static let playerAreaHeight: CGFloat = 140
    static let opponentAreaHeight: CGFloat = 100
    
    static let buttonHeight: CGFloat = 50
    static let buttonCornerRadius: CGFloat = 12
    
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 8
}

// MARK: - Theme Colors
enum ThemeColors {
    // Primary palette - Deep midnight with electric accents
    static let background = Color(hex: "0D1117")
    static let cardTable = Color(hex: "161B22")
    static let cardBack = Color(hex: "1C2128")
    
    // Card colors
    static let cardFace = Color(hex: "F0F6FC")
    static let cardRed = Color(hex: "F85149")
    static let cardBlack = Color(hex: "21262D")
    
    // Accent colors
    static let primary = Color(hex: "58A6FF")
    static let secondary = Color(hex: "7EE787")
    static let warning = Color(hex: "D29922")
    static let danger = Color(hex: "F85149")
    
    // Text colors
    static let textPrimary = Color(hex: "F0F6FC")
    static let textSecondary = Color(hex: "8B949E")
    static let textMuted = Color(hex: "484F58")
    
    // State colors
    static let activePlayer = Color(hex: "238636")
    static let reactionWindow = Color(hex: "A371F7")
    static let caboHighlight = Color(hex: "F78166")
    
    // Gradients
    static let cardGradient = LinearGradient(
        colors: [Color(hex: "2D333B"), Color(hex: "22272E")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let buttonGradient = LinearGradient(
        colors: [Color(hex: "238636"), Color(hex: "2EA043")],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let dangerGradient = LinearGradient(
        colors: [Color(hex: "DA3633"), Color(hex: "F85149")],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Typography
enum Typography {
    static let cardRank = Font.system(size: 24, weight: .bold, design: .rounded)
    static let cardSmall = Font.system(size: 12, weight: .medium, design: .rounded)
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let subtitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 14, weight: .regular, design: .rounded)
    static let timer = Font.system(size: 32, weight: .heavy, design: .monospaced)
    static let roomCode = Font.system(size: 36, weight: .heavy, design: .monospaced)
}

// MARK: - Animation Durations
enum AnimationDurations {
    static let cardFlip: Double = 0.3
    static let cardMove: Double = 0.25
    static let buttonPress: Double = 0.1
    static let stateChange: Double = 0.2
    static let reactionCountdown: Double = 1.0
}

// MARK: - Haptic Feedback
enum HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - Color Extension
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

