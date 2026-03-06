import SwiftUI

/// Compact coaching prompt pill — tap to dismiss.
struct CoachingBadge: View {
    let prompt: CoachingPrompt
    @State private var isVisible = false
    @State private var dismissed = false

    private var tintColor: Color {
        prompt.severity == .positive ? TCColor.good : TCColor.accent
    }

    var body: some View {
        if !dismissed {
            HStack(spacing: TCSpacing.xxs) {
                Image(systemName: prompt.icon)
                    .font(TCFont.badge)
                Text(prompt.message)
                    .font(TCFont.badgeBody)
                    .lineLimit(1)
            }
            .foregroundStyle(tintColor)
            .padding(.horizontal, TCSpacing.xs)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(tintColor.opacity(TCOverlay.light))
            )
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { isVisible = true }
                HapticEngine.shared.coachingNudge()
            }
            .onTapGesture {
                withAnimation(.easeIn(duration: 0.15)) { dismissed = true }
            }
        }
    }
}
