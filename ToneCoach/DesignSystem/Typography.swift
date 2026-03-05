import SwiftUI

/// ToneCoach type scale — SF Pro with specific weights for premium feel.
enum TCFont {
    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title       = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let title2      = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold)
    static let body        = Font.system(size: 17, weight: .regular)
    static let callout     = Font.system(size: 16, weight: .medium)
    static let caption     = Font.system(size: 13, weight: .medium)
    static let metric      = Font.system(size: 48, weight: .bold, design: .rounded)
    static let metricSmall = Font.system(size: 28, weight: .bold, design: .rounded)
    static let mono        = Font.system(size: 14, weight: .medium, design: .monospaced)

    // MARK: - Small UI text (badges, axis labels, mini stats)
    static let micro       = Font.system(size: 10, weight: .medium)
    static let badge       = Font.system(size: 12, weight: .semibold)
    static let badgeBody   = Font.system(size: 12, weight: .medium)
    static let smallDetail = Font.system(size: 11, weight: .medium)
}

/// Canonical icon sizes — use with `.font(.system(size:))` on SF Symbols.
enum TCIcon {
    static let hero: CGFloat   = 64   // Onboarding splash, empty states
    static let large: CGFloat  = 48   // Permission steps, calibration
    static let medium: CGFloat = 20   // Inline section icons
    static let small: CGFloat  = 16   // Card detail icons
    static let mini: CGFloat   = 14   // Row-level icons
    static let tiny: CGFloat   = 12   // Badge icons
}
