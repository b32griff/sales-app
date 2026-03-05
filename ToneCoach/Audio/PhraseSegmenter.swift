import Foundation

/// Segments speech into phrases by detecting pauses (silence gaps).
///
/// Per Hormozi: Pauses are one of the two variables in sales tone.
/// Short pause = draw attention to a point. Long pause = expect a response.
/// Research shows waiting up to 8 seconds after asking to buy closes 30% more.
///
/// Reliability guarantees:
/// - 1 sentence = 1 phrase-end event (no double triggers)
/// - Adaptive silence threshold tracks ambient noise floor
/// - Minimum phrase duration prevents noise blips from registering
/// - Cooldown after firing prevents rapid re-trigger
final class PhraseSegmenter {
    // ── Tunable constants ──

    /// Seconds of continuous silence required to end a phrase.
    /// 0.45s filters clause-level micro-pauses (0.15–0.3s) while catching
    /// real sentence boundaries. Typical sentence gap is 0.5–1.0s.
    private let pauseDuration: Double

    /// Minimum phrase length in seconds. Anything shorter is treated as
    /// a noise blip (breath, lip smack) and suppressed.
    private let minPhraseDuration: Double

    /// Cooldown after firing: ignore new phrase-ends for this long after the
    /// last fire, preventing trailing silence from starting a micro-phrase.
    private let cooldownAfterFire: Double

    // ── Adaptive silence threshold ──

    /// RMS below this = silence. Updated continuously from ambient noise floor.
    private var energyThreshold: Float

    /// Exponential moving average of RMS during confirmed silence windows.
    private var ambientNoiseFloor: Float = 0.002
    private let noiseFloorAlpha: Float = 0.05
    /// Multiplier above ambient floor to set the silence/speech boundary.
    private let thresholdMultiplier: Float = 3.0
    /// Hard floor — never drop below this even in a dead-silent room.
    private let absoluteMinThreshold: Float = 0.003
    /// Hard ceiling — never raise above this even in a noisy room.
    private let absoluteMaxThreshold: Float = 0.04

    // ── State ──

    private var silenceStartTime: Double?
    private var phraseStartTime: Double?
    private var isInPhrase = false
    private(set) var phraseCount = 0
    private(set) var totalSilenceTime: Double = 0
    private var lastTimestamp: Double = 0
    private var lastFireTime: Double = -.infinity
    private var pendingPauseMeasurement = false

    // O(1) pause stats — no growing array
    private var pauseDurationSum: Double = 0
    private var pauseCount: Int = 0
    private(set) var powerPauseCount: Int = 0

    /// Called when a phrase ends, with (phraseStartTime, phraseEndTime).
    var onPhraseEnd: ((Double, Double) -> Void)?

    init(
        pauseDuration: Double = 0.45,
        minPhraseDuration: Double = 0.4,
        cooldownAfterFire: Double = 0.6,
        energyThreshold: Float = 0.008
    ) {
        self.pauseDuration = pauseDuration
        self.minPhraseDuration = minPhraseDuration
        self.cooldownAfterFire = cooldownAfterFire
        self.energyThreshold = energyThreshold
    }

    @discardableResult
    func process(rms: Float, timestamp: Double) -> Bool {
        lastTimestamp = timestamp
        let isSilent = rms < energyThreshold

        if isSilent {
            // Track when silence started
            if silenceStartTime == nil {
                silenceStartTime = timestamp
            }

            let silStart = silenceStartTime ?? timestamp

            // Update ambient noise floor from sustained silence (> 0.1s)
            if timestamp - silStart > 0.1 {
                ambientNoiseFloor = ambientNoiseFloor * (1 - noiseFloorAlpha) + rms * noiseFloorAlpha
                let adapted = ambientNoiseFloor * thresholdMultiplier
                energyThreshold = min(max(adapted, absoluteMinThreshold), absoluteMaxThreshold)
            }

            let silenceDuration = timestamp - silStart

            if isInPhrase && silenceDuration >= pauseDuration {
                let phraseStart = phraseStartTime ?? 0
                let phraseDuration = silStart - phraseStart

                // Guard: skip if phrase too short (noise blip)
                guard phraseDuration >= minPhraseDuration else {
                    isInPhrase = false
                    return false
                }

                // Guard: skip if within cooldown window after last fire
                guard timestamp - lastFireTime >= cooldownAfterFire else {
                    isInPhrase = false
                    return false
                }

                // Commit phrase-end event
                isInPhrase = false
                phraseCount += 1
                pendingPauseMeasurement = true
                lastFireTime = timestamp

                onPhraseEnd?(phraseStart, silStart)
                return true
            }
        } else {
            // Accumulate silence time and measure pause when speech resumes
            if let silStart = silenceStartTime {
                let silDur = timestamp - silStart
                totalSilenceTime += silDur
                if pendingPauseMeasurement {
                    pauseDurationSum += silDur
                    pauseCount += 1
                    if silDur >= 2.0 { powerPauseCount += 1 }
                    pendingPauseMeasurement = false
                }
            }
            silenceStartTime = nil

            if !isInPhrase {
                isInPhrase = true
                phraseStartTime = timestamp
            }
        }

        return false
    }

    /// Pause ratio: time spent silent / total elapsed time.
    func pauseRatio(totalDuration: Double) -> Double {
        guard totalDuration > 0 else { return 0 }
        return totalSilenceTime / totalDuration
    }

    /// Average pause duration in seconds. O(1).
    var averagePauseDuration: Double {
        guard pauseCount > 0 else { return 0 }
        return pauseDurationSum / Double(pauseCount)
    }

    /// Current adaptive silence threshold (for diagnostics).
    var currentThreshold: Float { energyThreshold }

    func reset() {
        silenceStartTime = nil
        phraseStartTime = nil
        isInPhrase = false
        phraseCount = 0
        totalSilenceTime = 0
        lastTimestamp = 0
        lastFireTime = -.infinity
        pauseDurationSum = 0
        pauseCount = 0
        powerPauseCount = 0
        pendingPauseMeasurement = false
        ambientNoiseFloor = 0.002
    }
}
