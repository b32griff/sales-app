import Foundation
import SwiftData

/// ViewModel for the history screen — loads sessions and prepares trend data,
/// streaks, personal bests, and comparison deltas.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var trendPeriodDays: Int = 14

    func load(context: ModelContext) {
        sessions = SessionStore.fetchAll(in: context)
    }

    // MARK: - Trend Data

    /// Sessions filtered to the selected trend period, oldest first.
    var trendSessions: [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -trendPeriodDays, to: Date()) ?? Date()
        return sessions.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    var scoreTrend: [(Date, Double)] {
        trendSessions.map { ($0.date, Double($0.authorityScore)) }
    }

    var volumeTrend: [(Date, Double)] {
        trendSessions.map { ($0.date, $0.dbInRangePercent) }
    }

    var cadenceTrend: [(Date, Double)] {
        trendSessions.map { ($0.date, $0.averageWPM) }
    }

    var toneTrend: [(Date, Double)] {
        trendSessions.map { ($0.date, $0.downTonePercent) }
    }

    var pauseTrend: [(Date, Double)] {
        trendSessions.map { ($0.date, $0.pauseRatio * 100) }
    }

    // MARK: - Streak

    /// Consecutive days with at least one session, ending today or yesterday.
    var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build a set of unique session days
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })

        // Start from today (or yesterday if no session today yet)
        var checkDay = today
        if !sessionDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDay = yesterday
        }

        var streak = 0
        while sessionDays.contains(checkDay) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prev
        }
        return streak
    }

    /// Total number of sessions.
    var totalSessions: Int { sessions.count }

    // MARK: - Summary Stats

    /// Best authority score ever achieved.
    var bestScore: Int {
        sessions.map(\.authorityScore).max() ?? 0
    }

    /// Average authority score over last 7 sessions.
    var recentAvgScore: Int {
        let recent = Array(sessions.prefix(7))
        guard !recent.isEmpty else { return 0 }
        let sum = recent.reduce(0) { $0 + $1.authorityScore }
        return sum / recent.count
    }

    /// Total practice time across all sessions, formatted.
    var totalPracticeTime: String {
        let total = sessions.reduce(0) { $0 + $1.durationSeconds }
        let hours = Int(total) / 3600
        let mins = (Int(total) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    // MARK: - Delta (latest vs previous session)

    /// Score improvement from previous session to latest.
    /// Returns nil if fewer than 2 sessions.
    var scoreDelta: Int? {
        guard sessions.count >= 2 else { return nil }
        return sessions[0].authorityScore - sessions[1].authorityScore
    }

    /// The previous session (second most recent). Used for per-metric deltas.
    var previousSession: Session? {
        sessions.count >= 2 ? sessions[1] : nil
    }

    func delete(session: Session, context: ModelContext) {
        SessionStore.delete(session, in: context)
        load(context: context)
    }
}
