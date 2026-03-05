import SwiftUI

/// Consistent spacing scale (4-point grid).
enum TCSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat  = 4
    static let xs: CGFloat   = 8
    static let sm: CGFloat   = 12
    static let md: CGFloat   = 16
    static let lg: CGFloat   = 24
    static let xl: CGFloat   = 32
    static let xxl: CGFloat  = 48
    static let xxxl: CGFloat = 64
}

/// Corner radii.
enum TCRadius {
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let xl: CGFloat  = 24
    static let pill: CGFloat = 999
}

/// Canonical overlay/tint opacities — keeps accent usage consistent.
enum TCOverlay {
    static let subtle: Double  = 0.10  // Background tints, area fills
    static let light: Double   = 0.15  // Badge backgrounds, hover states
    static let medium: Double  = 0.30  // Border strokes, separators
    static let heavy: Double   = 0.50  // Muted icons, disabled states
}

/// Surface card background — the most repeated pattern in the app.
/// Usage: `.modifier(TCCard())` or `.modifier(TCCard(radius: .lg, stroke: true))`
struct TCCard: ViewModifier {
    var radius: CGFloat = TCRadius.md
    var stroke: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(TCSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(TCColor.surface)
                    .overlay(
                        stroke ?
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(TCColor.accent.opacity(TCOverlay.medium), lineWidth: 1)
                            : nil
                    )
            )
    }
}
