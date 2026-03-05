import SwiftUI

/// Filled accent button — primary CTA throughout the app.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TCFont.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TCSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TCRadius.md)
                    .fill(TCColor.accent)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Outline accent button — secondary actions (share, history, etc.)
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TCFont.callout)
            .foregroundStyle(TCColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TCSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TCRadius.md)
                    .strokeBorder(TCColor.accent.opacity(TCOverlay.medium), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
