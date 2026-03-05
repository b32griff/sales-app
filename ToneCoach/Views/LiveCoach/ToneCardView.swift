import SwiftUI

/// Tone grading card — shows last 10 phrase grades with haptic feedback.
/// Extracted into its own file to avoid merge conflicts with other
/// LiveCoachView.swift workstreams (volume graph, cadence UI, etc.)
struct ToneCard: View {
    let state: ToneState

    // Haptic generators — created once, reused per event
    private let successHaptic = UINotificationFeedbackGenerator()
    private let failHaptic = UIImpactFeedbackGenerator(style: .light)

    /// Last 3 phrase results for the strip display.
    private var recentPhrases: [AudioEngine.PhraseResult] {
        Array(state.phraseResults.suffix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TCSpacing.sm) {
            // Header: title + pass-rate %
            HStack {
                Text("Sentence Endings")
                    .font(TCFont.headline)
                    .foregroundStyle(TCColor.textPrimary)
                Spacer()
                if state.phrasesAnalyzed > 0 {
                    Text("\(state.passRate)%")
                        .font(TCFont.metricSmall)
                        .foregroundStyle(scoreColor)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: state.passRate)
                }
            }

            if state.phraseResults.isEmpty {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: TCSpacing.xs) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(TCColor.textTertiary)
                        Text("Finish a sentence to see results")
                            .font(TCFont.callout)
                            .foregroundStyle(TCColor.textTertiary)
                    }
                    .padding(.vertical, TCSpacing.sm)
                    Spacer()
                }
            } else {
                // Per-phrase strip — last 3 phrases, large and clear
                VStack(spacing: TCSpacing.xs) {
                    ForEach(recentPhrases) { result in
                        PhraseStripRow(result: result)
                            .id(result.id)
                            .transition(
                                .move(edge: .bottom)
                                .combined(with: .opacity)
                            )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state.phraseResults.count)
                .onChange(of: state.phraseResults.count) { _, _ in
                    if let last = state.phraseResults.last {
                        fireHaptic(for: last.grade)
                    }
                }

                // Footer: count + target
                HStack {
                    Text(footerCountLabel)
                        .font(TCFont.caption)
                        .foregroundStyle(TCColor.textTertiary)
                    Spacer()
                    HStack(spacing: TCSpacing.xxs) {
                        Image(systemName: "target")
                            .font(.system(size: 11))
                        Text("End \(state.desiredTone == .down ? "DOWN" : "UP")")
                            .font(TCFont.caption)
                    }
                    .foregroundStyle(TCColor.textTertiary)
                }
            }
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
    }

    // MARK: - Computed Display Values

    private var gradedCount: Int {
        state.phraseResults.filter { $0.grade != .unknown }.count
    }

    private var unknownCount: Int {
        state.phraseResults.filter { $0.grade == .unknown }.count
    }

    private var footerCountLabel: String {
        if unknownCount > 0 {
            return "\(gradedCount) graded \u{00B7} \(unknownCount) unclear"
        }
        return "\(state.phrasesAnalyzed) phrases"
    }

    private var scoreColor: Color {
        switch state.status {
        case .good:    return TCColor.good
        case .warning: return TCColor.accent
        case .bad:     return TCColor.bad
        case .idle:    return TCColor.textSecondary
        }
    }

    // MARK: - Haptics (one-shot per phrase, skip unknowns)

    private func fireHaptic(for grade: PhraseGrade) {
        switch grade {
        case .pass:
            successHaptic.notificationOccurred(.success)
        case .fail:
            failHaptic.impactOccurred()
        case .unknown:
            break
        }
    }
}

// MARK: - Per-phrase strip row (replaces tiny dot icons)

struct PhraseStripRow: View {
    let result: AudioEngine.PhraseResult
    @State private var appeared = false

    var body: some View {
        HStack(spacing: TCSpacing.sm) {
            // Grade icon — large and clear
            ZStack {
                Circle()
                    .fill(gradeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: gradeSymbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(gradeColor)
            }

            // Tone direction
            VStack(alignment: .leading, spacing: 2) {
                Text(gradeLabel)
                    .font(TCFont.callout)
                    .foregroundStyle(gradeColor)
                Text(toneDirectionLabel)
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }

            Spacer()
        }
        .padding(.vertical, TCSpacing.xxs)
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private var gradeSymbol: String {
        switch result.grade {
        case .pass:    return "checkmark"
        case .fail:    return "xmark"
        case .unknown: return "minus"
        }
    }

    private var gradeLabel: String {
        switch result.grade {
        case .pass:    return "Pass"
        case .fail:    return "Fail"
        case .unknown: return "Unclear"
        }
    }

    private var gradeColor: Color {
        switch result.grade {
        case .pass:    return TCColor.good
        case .fail:    return TCColor.bad
        case .unknown: return TCColor.textTertiary
        }
    }

    private var toneDirectionLabel: String {
        switch result.endingTone {
        case .down:    return "Ended down"
        case .up:      return "Ended up"
        case .unknown: return "Tone unclear"
        }
    }
}

// MARK: - Grade Icon (SF Symbol, scale-in animation) — kept for other consumers

struct GradeIcon: View {
    let grade: PhraseGrade
    @State private var appeared = false

    private let iconSize: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(gradeColor.opacity(0.15))
                .frame(width: iconSize, height: iconSize)
            Image(systemName: gradeSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(gradeColor)
        }
        .scaleEffect(appeared ? 1.0 : 0.3)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }

    private var gradeSymbol: String {
        switch grade {
        case .pass:    return "checkmark"
        case .fail:    return "xmark"
        case .unknown: return "minus"
        }
    }

    private var gradeColor: Color {
        switch grade {
        case .pass:    return TCColor.good
        case .fail:    return TCColor.bad
        case .unknown: return TCColor.textTertiary
        }
    }
}

