import SwiftUI

/// Premium share card — designed to screenshot well on social media.
/// Gradient header, big score, compact metrics, date stamp, branding.
struct SessionResultCard: View {
    let session: Session
    let showBranding: Bool

    init(session: Session, showBranding: Bool = true) {
        self.session = session
        self.showBranding = showBranding
    }

    private var authorityScore: Int { session.authorityScore }

    var body: some View {
        VStack(spacing: 0) {
            // Gradient header with score
            headerSection

            // Metrics grid
            metricsSection

            // Footer
            footerSection
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 6)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(authorityScore) / 100)
                    .stroke(
                        LinearGradient(
                            colors: [scoreColor.opacity(0.8), scoreColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(authorityScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(authorityLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Text(formattedDate)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1A2E),
                    Color(hex: 0x16213E),
                    Color(hex: 0x0F3460).opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                shareMetric(
                    icon: "arrow.down.right.circle.fill",
                    label: "Down-tone",
                    value: "\(Int(session.downTonePercent))%",
                    good: session.downTonePercent >= 50
                )
                shareMetric(
                    icon: "speaker.wave.2.fill",
                    label: "Volume",
                    value: "\(Int(session.dbInRangePercent))%",
                    good: session.dbInRangePercent >= 50
                )
                shareMetric(
                    icon: "metronome.fill",
                    label: "Speed",
                    value: "\(Int(session.averageWPM))",
                    good: wpmInRange
                )
            }

            HStack(spacing: 12) {
                shareMetric(
                    icon: "pause.circle.fill",
                    label: "Pauses",
                    value: String(format: "%.0f%%", session.pauseRatio * 100),
                    good: session.pauseRatio >= 0.15 && session.pauseRatio <= 0.25
                )
                if session.articulationScore > 0 {
                    shareMetric(
                        icon: "text.word.spacing",
                        label: "Clarity",
                        value: "\(Int(session.articulationScore))%",
                        good: session.articulationScore >= 70
                    )
                }
                shareMetric(
                    icon: "clock.fill",
                    label: "Duration",
                    value: formattedDuration,
                    good: true
                )
            }
        }
        .padding(16)
        .background(Color(hex: 0x1A1A24))
    }

    private func shareMetric(icon: String, label: String, value: String, good: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(good ? Color(hex: 0x34D399) : Color(hex: 0xEF4444))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if showBranding {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 12))
                    Text("ToneCoach")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x6C5CE7))
            }
            Spacer()
            Text(session.topTakeaway)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x141420))
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        if authorityScore >= 70 { return Color(hex: 0x34D399) }
        if authorityScore < 40 { return Color(hex: 0xEF4444) }
        return Color(hex: 0x6C5CE7)
    }

    private var authorityLabel: String {
        switch authorityScore {
        case 90...100: return "Commanding"
        case 75..<90:  return "Confident"
        case 60..<75:  return "Developing"
        default:       return "Building"
        }
    }

    private var wpmInRange: Bool {
        let settings = UserSettings.shared
        return session.averageWPM >= settings.targetWPMMin && session.averageWPM <= settings.targetWPMMax
    }

    private var formattedDate: String {
        session.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var formattedDuration: String {
        let m = Int(session.durationSeconds) / 60
        let s = Int(session.durationSeconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
