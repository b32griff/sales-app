import SwiftUI

/// Post-session summary sheet with animated score, per-metric coaching, and delta vs previous.
struct SessionSummaryView: View {
    let session: Session
    let previousSession: Session?
    let onDismiss: () -> Void
    let onShare: () -> Void
    let onViewHistory: () -> Void

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    // Animation
    @State private var scoreAnimated = false
    @State private var metricsVisible = false

    init(session: Session,
         previousSession: Session? = nil,
         onDismiss: @escaping () -> Void,
         onShare: @escaping () -> Void,
         onViewHistory: @escaping () -> Void) {
        self.session = session
        self.previousSession = previousSession
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onViewHistory = onViewHistory
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TCSpacing.md) {
                // Authority Score Ring
                scoreRing
                    .padding(.top, TCSpacing.md)

                // Takeaway
                takeawayBanner

                // Metrics with coaching text
                metricsSection

                // CTA buttons
                ctaButtons
            }
            .padding(.bottom, TCSpacing.lg)
        }
        .background(TCColor.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                scoreAnimated = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                metricsVisible = true
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Score Ring

    private var scoreRing: some View {
        VStack(spacing: TCSpacing.xs) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(TCColor.surfaceAlt, lineWidth: 10)
                    .frame(width: 140, height: 140)

                // Animated progress ring
                Circle()
                    .trim(from: 0, to: scoreAnimated ? CGFloat(authorityScore) / 100 : 0)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor.opacity(0.6), scoreColor],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: TCSpacing.xxxs) {
                    Text("\(scoreAnimated ? authorityScore : 0)")
                        .font(TCFont.metric)
                        .foregroundStyle(scoreColor)
                        .contentTransition(.numericText())
                    Text(authorityLabel)
                        .font(TCFont.caption)
                        .foregroundStyle(TCColor.textSecondary)
                }
            }

            // Delta badge
            if let delta = scoreDelta {
                HStack(spacing: TCSpacing.xxs) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(abs(delta)) pts from last")
                        .font(TCFont.caption)
                }
                .foregroundStyle(delta >= 0 ? TCColor.good : TCColor.bad)
                .padding(.horizontal, TCSpacing.sm)
                .padding(.vertical, TCSpacing.xxs)
                .background(
                    Capsule()
                        .fill((delta >= 0 ? TCColor.good : TCColor.bad).opacity(0.15))
                )
            }
        }
    }

    // MARK: - Takeaway

    private var takeawayBanner: some View {
        HStack(spacing: TCSpacing.xs) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(TCColor.accent)
            Text(session.topTakeaway)
                .font(TCFont.caption)
                .foregroundStyle(TCColor.textSecondary)
        }
        .padding(.horizontal, TCSpacing.md)
        .padding(.vertical, TCSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.sm)
                .fill(TCColor.accent.opacity(0.1))
        )
        .padding(.horizontal, TCSpacing.md)
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(spacing: TCSpacing.xs) {
            coachMetric(
                icon: "arrow.down.right.circle.fill",
                label: "Down-tone",
                value: "\(Int(session.downTonePercent))%",
                pass: session.downTonePercent >= 50,
                coaching: toneCoaching,
                delta: metricDelta(\.downTonePercent)
            )

            coachMetric(
                icon: "speaker.wave.2.fill",
                label: "Volume",
                value: "\(Int(session.dbInRangePercent))%",
                pass: session.dbInRangePercent >= 50,
                coaching: volumeCoaching,
                delta: metricDelta(\.dbInRangePercent)
            )

            coachMetric(
                icon: "metronome.fill",
                label: "Speed",
                value: "\(Int(session.averageWPM)) wpm",
                pass: wpmInRange,
                coaching: speedCoaching,
                delta: nil
            )

            coachMetric(
                icon: "pause.circle.fill",
                label: "Pauses",
                value: String(format: "%.0f%%", session.pauseRatio * 100),
                pass: session.pauseRatio >= 0.15 && session.pauseRatio <= 0.25,
                coaching: pauseCoaching,
                delta: nil
            )

            if session.articulationScore > 0 {
                coachMetric(
                    icon: "text.word.spacing",
                    label: "Clarity",
                    value: "\(Int(session.articulationScore))%",
                    pass: session.articulationScore >= 70,
                    coaching: clarityCoaching,
                    delta: metricDelta(\.articulationScore)
                )
            }
        }
        .padding(.horizontal, TCSpacing.md)
        .opacity(metricsVisible ? 1 : 0)
        .offset(y: metricsVisible ? 0 : 12)
    }

    private func coachMetric(icon: String, label: String, value: String,
                             pass: Bool, coaching: String, delta: Int?) -> some View {
        HStack(spacing: TCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(pass ? TCColor.good : TCColor.bad)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: TCSpacing.xxxs) {
                HStack(spacing: TCSpacing.xs) {
                    Text(label)
                        .font(TCFont.callout)
                        .foregroundStyle(TCColor.textPrimary)
                    Spacer()
                    if let delta, delta != 0 {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(delta > 0 ? TCColor.good : TCColor.bad)
                    }
                    Text(value)
                        .font(TCFont.headline)
                        .foregroundStyle(pass ? TCColor.good : TCColor.bad)
                }
                Text(coaching)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(TCColor.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(TCSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
    }

    // MARK: - CTA

    private var ctaButtons: some View {
        VStack(spacing: TCSpacing.xs) {
            Button {
                onDismiss()
            } label: {
                Text("Practice Again")
                    .font(TCFont.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TCSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: TCRadius.md)
                            .fill(TCColor.accent)
                    )
            }

            HStack(spacing: TCSpacing.sm) {
                Button {
                    generateShareImage()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(TCFont.callout)
                        .foregroundStyle(TCColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TCSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: TCRadius.md)
                                .strokeBorder(TCColor.accent.opacity(0.4), lineWidth: 1)
                        )
                }

                Button {
                    onViewHistory()
                } label: {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                        .font(TCFont.callout)
                        .foregroundStyle(TCColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TCSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: TCRadius.md)
                                .strokeBorder(TCColor.accent.opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, TCSpacing.md)
    }

    // MARK: - Authority Score (delegates to Session.authorityScore)

    private var authorityScore: Int { session.authorityScore }

    private var scoreColor: Color {
        if authorityScore >= 70 { return TCColor.good }
        if authorityScore < 40 { return TCColor.bad }
        return TCColor.accent
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

    // MARK: - Deltas

    private var scoreDelta: Int? {
        guard let prev = previousSession else { return nil }
        return session.authorityScore - prev.authorityScore
    }

    private func metricDelta(_ keyPath: KeyPath<Session, Double>) -> Int? {
        guard let prev = previousSession else { return nil }
        let diff = Int(session[keyPath: keyPath]) - Int(prev[keyPath: keyPath])
        return diff
    }

    // MARK: - Per-Metric Coaching Text

    private var toneCoaching: String {
        if session.downTonePercent >= 70 { return "Strong authority. Your endings command attention." }
        if session.downTonePercent >= 50 { return "Getting there. Focus on dropping pitch at sentence ends." }
        return "Practice ending phrases with a downward pitch shift."
    }

    private var volumeCoaching: String {
        if session.dbInRangePercent >= 70 { return "Consistent projection. Your voice carries well." }
        if session.dbInRangePercent >= 50 { return "Some dips. Maintain steady breath support." }
        return "Work on keeping volume projected and even throughout."
    }

    private var speedCoaching: String {
        let settings = UserSettings.shared
        if session.averageWPM > settings.targetWPMMax { return "A bit fast. Slow down to build trust." }
        if session.averageWPM < settings.targetWPMMin { return "Pick up the pace slightly. You want energy." }
        return "Right in the sweet spot. Natural and engaging."
    }

    private var pauseCoaching: String {
        let ratio = session.pauseRatio
        if ratio >= 0.15 && ratio <= 0.25 { return "Great rhythm. Your pauses let key points land." }
        if ratio < 0.15 { return "Add more pauses. Let the buyer process what you said." }
        return "Tighten up. Too much dead air loses momentum."
    }

    private var clarityCoaching: String {
        if session.articulationScore >= 70 { return "Clear and crisp. Easy to follow." }
        if session.articulationScore >= 40 { return "Mostly clear. Slow down on key words." }
        return "Focus on enunciating clearly. Open your mouth more."
    }

    // MARK: - Share

    private func generateShareImage() {
        let renderer = ImageRenderer(content:
            SessionResultCard(session: session, showBranding: true)
                .padding(TCSpacing.lg)
                .background(TCColor.background)
                .frame(width: 380)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }
}

// MARK: - UIKit ShareSheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
