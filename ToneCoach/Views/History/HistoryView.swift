import SwiftUI
import SwiftData

/// Session history with streak banner, summary stats, trend charts, and session list.
struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ZStack {
                TCColor.background.ignoresSafeArea()

                if vm.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: TCSpacing.sm) {
                            // Streak + summary header
                            summaryHeader

                            // Trend charts
                            TrendChartView(
                                title: "Authority Score",
                                data: vm.scoreTrend,
                                unit: "pts",
                                color: TCColor.good
                            )

                            TrendChartView(
                                title: "Down-tone Score",
                                data: vm.toneTrend,
                                unit: "%",
                                color: TCColor.good
                            )

                            TrendChartView(
                                title: "Volume Consistency",
                                data: vm.volumeTrend,
                                unit: "%",
                                color: TCColor.accent
                            )

                            TrendChartView(
                                title: "Speed (WPM)",
                                data: vm.cadenceTrend,
                                unit: "wpm",
                                color: TCColor.accentLight
                            )

                            TrendChartView(
                                title: "Pause Ratio",
                                data: vm.pauseTrend,
                                unit: "%",
                                color: TCColor.accent
                            )

                            // Session list
                            sessionListSection
                        }
                        .padding(.top, TCSpacing.xs)
                        .padding(.bottom, TCSpacing.md)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.load(context: modelContext) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary Header (streak + stats)

    private var summaryHeader: some View {
        VStack(spacing: TCSpacing.sm) {
            // Streak banner
            if vm.currentStreak > 0 {
                HStack(spacing: TCSpacing.xs) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(streakColor)
                    VStack(alignment: .leading, spacing: TCSpacing.xxxs) {
                        Text("\(vm.currentStreak)-day streak")
                            .font(TCFont.headline)
                            .foregroundStyle(TCColor.textPrimary)
                        Text(streakEncouragement)
                            .font(TCFont.caption)
                            .foregroundStyle(TCColor.textSecondary)
                    }
                    Spacer()
                }
                .padding(TCSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: TCRadius.md)
                        .fill(streakColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: TCRadius.md)
                                .strokeBorder(streakColor.opacity(0.25), lineWidth: 1)
                        )
                )
                .padding(.horizontal, TCSpacing.md)
            }

            // Stats row
            HStack(spacing: TCSpacing.sm) {
                statBadge(value: "\(vm.bestScore)", label: "Best", color: TCColor.good)
                statBadge(value: "\(vm.recentAvgScore)", label: "Avg (7)", color: TCColor.accent)
                statBadge(value: vm.totalPracticeTime, label: "Time", color: TCColor.accentLight)
                statBadge(value: "\(vm.totalSessions)", label: "Sessions", color: TCColor.textSecondary)
            }
            .padding(.horizontal, TCSpacing.md)
        }
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: TCSpacing.xxs) {
            Text(value)
                .font(TCFont.metricSmall)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TCColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TCSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
    }

    private var streakColor: Color {
        if vm.currentStreak >= 7 { return Color(hex: 0xFF6B35) } // fire orange
        if vm.currentStreak >= 3 { return TCColor.accent }
        return TCColor.accentLight
    }

    private var streakEncouragement: String {
        switch vm.currentStreak {
        case 1:      return "You showed up. That's the hardest part."
        case 2:      return "Two days in. Building the habit."
        case 3...6:  return "Consistency is your superpower."
        case 7...13: return "A full week. Your voice is leveling up."
        case 14...:  return "Unstoppable. This is how closers are made."
        default:     return ""
        }
    }

    // MARK: - Session List

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: TCSpacing.sm) {
            HStack {
                Text("Sessions")
                    .font(TCFont.headline)
                    .foregroundStyle(TCColor.textPrimary)
                Spacer()
                Text("\(vm.sessions.count) total")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }
            .padding(.horizontal, TCSpacing.md)

            ForEach(vm.sessions, id: \.id) { session in
                sessionRow(session)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: TCSpacing.sm) {
            // Score badge with color ring
            ZStack {
                Circle()
                    .stroke(scoreColor(for: session.authorityScore).opacity(0.3), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(session.authorityScore) / 100)
                    .stroke(scoreColor(for: session.authorityScore), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(session.authorityScore)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(for: session.authorityScore))
            }

            VStack(alignment: .leading, spacing: TCSpacing.xxs) {
                Text(session.date, style: .date)
                    .font(TCFont.callout)
                    .foregroundStyle(TCColor.textPrimary)
                Text(formatDuration(session.durationSeconds))
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }

            Spacer()

            HStack(spacing: TCSpacing.sm) {
                miniStat(value: "\(Int(session.dbInRangePercent))%", label: "Vol")
                miniStat(value: "\(Int(session.averageWPM))", label: "WPM")
                miniStat(value: "\(Int(session.downTonePercent))%", label: "Tone")
            }
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
        .padding(.horizontal, TCSpacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TCSpacing.md) {
            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(TCColor.accent.opacity(0.5))

            VStack(spacing: TCSpacing.xs) {
                Text("Your journey starts here")
                    .font(TCFont.title2)
                    .foregroundStyle(TCColor.textPrimary)
                Text("Complete a practice session and your\nprogress will show up right here.")
                    .font(TCFont.body)
                    .foregroundStyle(TCColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: TCSpacing.xxs) {
                HStack(spacing: TCSpacing.md) {
                    placeholderStat("Score")
                    placeholderStat("Tone")
                    placeholderStat("Volume")
                    placeholderStat("WPM")
                }
            }
            .padding(TCSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TCRadius.md)
                    .fill(TCColor.surface)
            )
            .padding(.horizontal, TCSpacing.md)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func scoreColor(for score: Int) -> Color {
        if score >= 70 { return TCColor.good }
        if score < 40 { return TCColor.bad }
        return TCColor.accent
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: TCSpacing.xxxs) {
            Text(value)
                .font(TCFont.callout)
                .foregroundStyle(TCColor.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TCColor.textTertiary)
        }
    }

    private func placeholderStat(_ label: String) -> some View {
        VStack(spacing: TCSpacing.xxs) {
            Text("--")
                .font(TCFont.callout)
                .foregroundStyle(TCColor.textTertiary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TCColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }
}
