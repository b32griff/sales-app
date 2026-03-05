import Foundation

// MARK: - Shared Snapshot Contracts
//
// These value types define the integration boundary between producers
// (AudioEngine / LiveCoachBinder) and consumers (views, summary, share card, etc.).
//
// RULES FOR ALL WORKSTREAMS:
//   1. Add fields here ONLY — do not duplicate snapshot state elsewhere.
//   2. All fields are let — snapshots are immutable once created.
//   3. If you need a new field, add it here with a default value so
//      existing call sites don't break.
//
// OWNERSHIP: Only AudioEngine (via LiveCoachBinder) produces these.
//            Any view or ViewModel may consume them read-only.

// MARK: - Live Metric Snapshots (real-time, ~12 Hz)

/// Point-in-time volume reading for UI consumption.
struct VolumeSnapshot: Sendable {
    let db: Double
    let status: MeterStatus
    let dbHistory: [Double]

    static let idle = VolumeSnapshot(db: -80, status: .idle, dbHistory: [])
}

/// Point-in-time tone analysis for UI consumption.
struct ToneSnapshot: Sendable {
    let phraseResults: [PhraseSnapshotEntry]
    let passRate: Int           // 0-100
    let phrasesAnalyzed: Int
    let status: MeterStatus

    static let idle = ToneSnapshot(phraseResults: [], passRate: 0, phrasesAnalyzed: 0, status: .idle)
}

/// A single phrase result, decoupled from AudioEngine.PhraseResult.
struct PhraseSnapshotEntry: Identifiable, Sendable {
    let id: UUID
    let endingTone: PhraseEndingTone
    let grade: PhraseGrade
    let confidence: Double

    init(id: UUID = UUID(), endingTone: PhraseEndingTone, grade: PhraseGrade, confidence: Double) {
        self.id = id
        self.endingTone = endingTone
        self.grade = grade
        self.confidence = confidence
    }
}

/// Point-in-time cadence reading for UI consumption.
struct CadenceSnapshot: Sendable {
    let wpm: Double
    let label: String           // formatted for display, e.g. "142" or "--"
    let status: MeterStatus
    let rangeLabel: String      // e.g. "135-185 wpm"
    let bannerMessage: String?  // nil = no banner

    static let idle = CadenceSnapshot(wpm: 0, label: "--", status: .idle, rangeLabel: "", bannerMessage: nil)
}

// MARK: - Session Summary Snapshot (post-session, computed once)

/// Immutable summary of a completed session for the summary sheet,
/// share card, and history row. Decoupled from the SwiftData Session model.
struct SessionSummarySnapshot: Sendable {
    let id: UUID
    let date: Date
    let durationSeconds: Double

    // Volume
    let averageDB: Double
    let dbInRangePercent: Double

    // Cadence
    let averageWPM: Double
    let pauseRatio: Double
    let averagePauseSec: Double
    let powerPauseCount: Int

    // Tone
    let downTonePercent: Double
    let upTonePercent: Double
    let phraseCount: Int
    let articulationScore: Double

    // Derived
    var authorityScore: Int {
        let toneScore = downTonePercent
        let volumeScore = dbInRangePercent

        let settings = UserSettings.shared
        let wpmRange = settings.targetWPMMax - settings.targetWPMMin
        let wpmMid = settings.wpmMidpoint
        let wpmDeviation = wpmRange > 0 ? abs(averageWPM - wpmMid) / (wpmRange / 2) : 1
        let speedScore = max(0, (1.0 - wpmDeviation)) * 100

        let pauseRatioPct = pauseRatio * 100
        let pauseScore: Double = (pauseRatioPct >= 15 && pauseRatioPct <= 25) ? 100 :
                                  (pauseRatioPct >= 10 && pauseRatioPct <= 35) ? 60 : 30

        return Int(toneScore * 0.35 + volumeScore * 0.30 + speedScore * 0.20 + pauseScore * 0.15)
    }

    /// Create from a SwiftData Session model.
    init(from session: Session) {
        self.id = session.id
        self.date = session.date
        self.durationSeconds = session.durationSeconds
        self.averageDB = session.averageDB
        self.dbInRangePercent = session.dbInRangePercent
        self.averageWPM = session.averageWPM
        self.pauseRatio = session.pauseRatio
        self.averagePauseSec = session.averagePauseSec
        self.powerPauseCount = session.powerPauseCount
        self.downTonePercent = session.downTonePercent
        self.upTonePercent = session.upTonePercent
        self.phraseCount = session.phraseCount
        self.articulationScore = session.articulationScore
    }
}
