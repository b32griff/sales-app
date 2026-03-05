import SwiftUI

/// ToneCoach brand color palette — dark, premium coaching aesthetic.
enum TCColor {
    // MARK: - Brand
    static let accent      = Color(hex: 0x6C5CE7) // Purple
    static let accentLight = Color(hex: 0xA29BFE)

    // MARK: - Pass / Fail (only green & red)
    static let good        = Color(hex: 0x34D399) // Green — pass
    static let bad         = Color(hex: 0xEF4444) // Red — fail

    // MARK: - Deprecated — use accent for mid-range states
    static let warning     = accent

    // MARK: - Surfaces
    static let background  = Color(hex: 0x0D0D12)
    static let surface     = Color(hex: 0x1A1A24)
    static let surfaceAlt  = Color(hex: 0x24243A)

    // MARK: - Text
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary  = Color.white.opacity(0.35)
}

// MARK: - Hex Initializer
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
