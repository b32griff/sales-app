import Foundation

// MARK: - Configuration

/// Tunable constants for tone classification.
/// Each field name maps to a potential Settings / RemoteConfig key for A/B testing.
struct ToneClassifierConfig {
    /// Analysis windows to try (ms). Classifier picks the one with best R².
    /// Key: `tone_analysis_windows`
    var analysisWindowsMs: [Double] = [300, 500, 700]

    /// Hz/s slope required to enter a down/up state from flat.
    /// Key: `tone_slope_enter`
    var slopeThresholdEnter: Double = 12

    /// Hz/s slope required to exit a down/up state back to flat.
    /// Key: `tone_slope_exit`
    var slopeThresholdExit: Double = 5

    /// Minimum pitched frames required in any single window.
    /// Key: `tone_min_pitch_points`
    var minPitchPoints: Int = 5

    /// Minimum ratio of pitched frames to expected frames in the window.
    /// Key: `tone_min_voiced_fraction`
    var minVoicedFraction: Double = 0.25

    /// Minimum phrase duration (seconds). Shorter phrases → unknown.
    /// Key: `tone_min_phrase_duration`
    var minPhraseDuration: Double = 0.4

    /// R² below this → unknown (not enough linear fit).
    /// Key: `tone_confidence_threshold`
    var confidenceThreshold: Double = 0.35

    /// Phrase-end timestamps within this window are the same phrase.
    /// Key: `tone_dedup_tolerance`
    var dedupTolerance: Double = 0.05

    /// Max deviation ratio from median for outlier filter.
    /// Key: `tone_outlier_deviation`
    var outlierDeviationRatio: Double = 0.4

    /// If more than this fraction of raw points are outliers → tooNoisy.
    /// Key: `tone_max_outlier_ratio`
    var maxOutlierRatio: Double = 0.5

    static let `default` = ToneClassifierConfig()
}

// MARK: - Verdict

/// Complete per-phrase classification result with explicit unknown policy.
struct PhraseVerdict {
    let direction: ToneDirection
    let confidence: Double        // 0...1 (R²)
    let slopeHzPerSec: Double
    let reason: UnknownReason?    // nil → successfully classified as up/down
    let debugOverlay: String      // Non-empty in DEBUG builds only

    var isUnknown: Bool { reason != nil }
}

// MARK: - Classifier

/// Classifies the intonation at the end of each phrase.
///
/// Stability guarantees:
/// - Adaptive analysis window: tries configurable windows, picks highest R²
/// - Octave-jump outlier filtering before regression
/// - 6-gate unknown policy: each gate has an explicit reason
/// - Hysteresis: once classified, requires a stronger counter-signal to flip
/// - Phrase-end dedup: prevents repeated results for the same phrase
/// - Debug overlay: full diagnostic string for every classification
final class DownToneClassifier {
    let config: ToneClassifierConfig
    private let pitchDetector: PitchDetector

    // Track last direction for hysteresis
    private var lastDirection: ToneDirection = .flat

    private static let maxResults = 50
    private(set) var phraseResults: [PhraseVerdict] = []

    // Dedup: track last classified phrase-end timestamp
    private var lastClassifiedPhraseEnd: Double = 0

    init(pitchDetector: PitchDetector, config: ToneClassifierConfig = .default) {
        self.pitchDetector = pitchDetector
        self.config = config
    }

    // MARK: - Classify

    /// Analyze the tone at the end of a phrase.
    ///
    /// Returns a `PhraseVerdict` with an explicit `reason` when the result
    /// is unknown. A nil reason means the phrase was successfully classified.
    func analyzePhrase(phraseEndTime: Double, phraseDuration: Double = .infinity) -> PhraseVerdict {
        var snap = AnalysisSnapshot(phraseDuration: phraseDuration, phraseEndTime: phraseEndTime)

        // ── Gate 1: Dedup ──
        if abs(phraseEndTime - lastClassifiedPhraseEnd) < config.dedupTolerance {
            return makeVerdict(&snap, reason: .deduplicate, append: false)
        }
        lastClassifiedPhraseEnd = phraseEndTime

        // ── Gate 2: Phrase too short ──
        if phraseDuration < config.minPhraseDuration {
            return makeVerdict(&snap, reason: .phraseTooShort)
        }

        // ── Adaptive window search ──
        for windowMs in config.analysisWindowsMs {
            let recentPitch = pitchDetector.recentPitch(lastMs: windowMs, before: phraseEndTime)
            guard recentPitch.count >= config.minPitchPoints else { continue }

            var times = recentPitch.map { $0.time }
            var pitches = recentPitch.map { $0.pitch }
            let rawCount = pitches.count

            let filtered = filterPitchOutliers(
                times: times, pitches: pitches,
                maxDeviationRatio: config.outlierDeviationRatio
            )
            times = filtered.times
            pitches = filtered.pitches
            let outlierCount = rawCount - pitches.count

            guard times.count >= config.minPitchPoints else { continue }

            let expectedPoints = max(1.0, windowMs / 73.0)
            let voicedFraction = Double(times.count) / expectedPoints

            let classification = classifyPitchSlope(
                pitchValues: pitches,
                timeValues: times,
                slopeThreshold: config.slopeThresholdEnter
            )

            if classification.confidence > snap.r2 {
                snap.r2 = classification.confidence
                snap.slope = classification.slopeHzPerSec
                snap.rawDirection = classification.direction
                snap.windowMs = windowMs
                snap.pointCount = times.count
                snap.rawCount = rawCount
                snap.outlierCount = outlierCount
                snap.voicedFraction = voicedFraction
            }
        }

        // ── Gate 3: No window had enough data ──
        guard snap.pointCount > 0 else {
            return makeVerdict(&snap, reason: .tooFewSamples)
        }

        // ── Gate 4: Too noisy (high outlier ratio) ──
        if snap.rawCount > 0 && Double(snap.outlierCount) / Double(snap.rawCount) > config.maxOutlierRatio {
            return makeVerdict(&snap, reason: .tooNoisy)
        }

        // ── Gate 5: Low voiced fraction ──
        if snap.voicedFraction < config.minVoicedFraction {
            return makeVerdict(&snap, reason: .lowVoicedFraction)
        }

        // ── Gate 6: Low confidence ──
        if snap.r2 < config.confidenceThreshold {
            return makeVerdict(&snap, reason: .lowConfidence)
        }

        // ── Hysteresis ──
        let direction = applyHysteresis(rawDirection: snap.rawDirection, slope: snap.slope)
        snap.finalDirection = direction

        // ── Gate 7: Flat (not enough slope to classify as up or down) ──
        if direction == .flat {
            return makeVerdict(&snap, reason: .tooFlat)
        }

        // ── Success: classified as upward or downward ──
        lastDirection = direction
        return makeVerdict(&snap, reason: nil)
    }

    // MARK: - Hysteresis

    private func applyHysteresis(rawDirection: ToneDirection, slope: Double) -> ToneDirection {
        switch lastDirection {
        case .downward:
            if slope > config.slopeThresholdEnter { return .upward }
            if slope > -config.slopeThresholdExit { return .flat }
            return .downward
        case .upward:
            if slope < -config.slopeThresholdEnter { return .downward }
            if slope < config.slopeThresholdExit { return .flat }
            return .upward
        case .flat:
            return rawDirection
        }
    }

    // MARK: - Verdict Builder

    /// Internal snapshot of per-phrase analysis data, used to build the verdict and overlay.
    private struct AnalysisSnapshot {
        var slope: Double = 0
        var r2: Double = -1
        var rawDirection: ToneDirection = .flat
        var finalDirection: ToneDirection = .flat
        var pointCount: Int = 0
        var rawCount: Int = 0
        var outlierCount: Int = 0
        var windowMs: Double = 0
        var voicedFraction: Double = 0
        var phraseDuration: Double = .infinity
        var phraseEndTime: Double = 0
    }

    private func makeVerdict(_ snap: inout AnalysisSnapshot, reason: UnknownReason?, append: Bool = true) -> PhraseVerdict {
        let dir = reason == nil ? snap.finalDirection : .flat
        let conf = reason == nil ? snap.r2 : (snap.r2 > 0 ? snap.r2 : 0)

        let verdict = PhraseVerdict(
            direction: dir,
            confidence: max(0, conf),
            slopeHzPerSec: snap.slope,
            reason: reason,
            debugOverlay: buildOverlay(snap: snap, direction: dir, reason: reason)
        )

        if append {
            appendResult(verdict)
        }

        #if DEBUG
        if !verdict.debugOverlay.isEmpty {
            print("[ToneClassifier] \(verdict.debugOverlay)")
        }
        #endif

        return verdict
    }

    // MARK: - Debug Overlay

    private func buildOverlay(snap: AnalysisSnapshot, direction: ToneDirection, reason: UnknownReason?) -> String {
        #if DEBUG
        let arrow: String
        if let r = reason {
            arrow = "? [\(r.rawValue)]"
        } else {
            switch direction {
            case .downward: arrow = "v"
            case .upward:   arrow = "^"
            case .flat:     arrow = "-"
            }
        }

        var parts: [String] = [arrow]

        if snap.windowMs > 0 {
            parts.append("slope=\(String(format: "%.1f", snap.slope))Hz/s")
            parts.append("R2=\(String(format: "%.2f", snap.r2))")
            parts.append("pts=\(snap.pointCount)/\(snap.rawCount)")
            parts.append("win=\(Int(snap.windowMs))ms")
            parts.append("vf=\(String(format: "%.2f", snap.voicedFraction))")
        }

        if snap.phraseDuration < .infinity {
            parts.append("dur=\(String(format: "%.2f", snap.phraseDuration))s")
        }

        return parts.joined(separator: " ")
        #else
        return ""
        #endif
    }

    // MARK: - Stats

    private func appendResult(_ verdict: PhraseVerdict) {
        phraseResults.append(verdict)
        if phraseResults.count > Self.maxResults {
            phraseResults.removeFirst(phraseResults.count - Self.maxResults)
        }
    }

    /// Percentage of successfully-classified phrases that ended downward.
    /// Unknown results are excluded from the denominator.
    var downTonePercent: Double {
        let classified = phraseResults.filter { !$0.isUnknown }
        guard !classified.isEmpty else { return 0 }
        let downCount = classified.filter { $0.direction == .downward }.count
        return Double(downCount) / Double(classified.count) * 100
    }

    /// Percentage of successfully-classified phrases that ended upward.
    var upTonePercent: Double {
        let classified = phraseResults.filter { !$0.isUnknown }
        guard !classified.isEmpty else { return 0 }
        let upCount = classified.filter { $0.direction == .upward }.count
        return Double(upCount) / Double(classified.count) * 100
    }

    var lastResult: PhraseVerdict? {
        phraseResults.last
    }

    func lastPhrasePitchContour() -> [Double] {
        let recent = pitchDetector.recentPitch(lastMs: 500)
        return recent.map { $0.pitch }
    }

    func reset() {
        phraseResults.removeAll()
        lastDirection = .flat
        lastClassifiedPhraseEnd = 0
    }
}
