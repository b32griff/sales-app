import Foundation
import Accelerate

// MARK: - RMS & Decibel Conversion

/// Compute RMS (root mean square) of a float buffer.
func computeRMS(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var rms: Float = 0
    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
    return rms
}

/// Convert RMS to decibels (full-scale reference = 1.0).
/// Returns a value typically in range [-80, 0] for audio signals.
func rmsToDecibels(_ rms: Float) -> Float {
    guard rms > 0 else { return -80 }
    return 20 * log10(rms)
}

/// Exponential moving average for smoothing.
func ema(previous: Double, current: Double, alpha: Double) -> Double {
    return alpha * current + (1 - alpha) * previous
}

// MARK: - Linear Regression

struct LinearRegressionResult {
    let slope: Double      // units per second (e.g., Hz/s for pitch)
    let intercept: Double
    let rSquared: Double   // goodness of fit, 0...1
}

/// Compute linear regression on (x, y) pairs.
/// x values should be in seconds, y in Hz (for pitch slope analysis).
func linearRegression(x: [Double], y: [Double]) -> LinearRegressionResult? {
    let n = min(x.count, y.count)
    guard n >= 2 else { return nil }

    let sumX  = x.prefix(n).reduce(0, +)
    let sumY  = y.prefix(n).reduce(0, +)
    let sumXY = zip(x.prefix(n), y.prefix(n)).reduce(0.0) { $0 + $1.0 * $1.1 }
    let sumX2 = x.prefix(n).reduce(0.0) { $0 + $1 * $1 }
    let denom = Double(n) * sumX2 - sumX * sumX
    guard abs(denom) > 1e-10 else { return nil }

    let slope = (Double(n) * sumXY - sumX * sumY) / denom
    let intercept = (sumY - slope * sumX) / Double(n)

    // R-squared
    let ssRes = zip(x.prefix(n), y.prefix(n)).reduce(0.0) { acc, pair in
        let predicted = slope * pair.0 + intercept
        let residual = pair.1 - predicted
        return acc + residual * residual
    }
    let meanY = sumY / Double(n)
    let ssTot = y.prefix(n).reduce(0.0) { $0 + ($1 - meanY) * ($1 - meanY) }
    let rSquared = ssTot > 1e-10 ? max(0, 1 - ssRes / ssTot) : 0

    return LinearRegressionResult(slope: slope, intercept: intercept, rSquared: rSquared)
}

// MARK: - Pitch Outlier Filtering

/// Remove octave-jump outliers from pitch readings.
/// YIN occasionally halves or doubles the true frequency. This filter
/// computes the median pitch, then drops any reading that deviates by
/// more than `maxDeviationRatio` (e.g. 0.4 = 40%) from the median.
func filterPitchOutliers(
    times: [Double],
    pitches: [Double],
    maxDeviationRatio: Double = 0.4
) -> (times: [Double], pitches: [Double]) {
    guard pitches.count >= 3 else { return (times, pitches) }

    let sorted = pitches.sorted()
    let median = sorted[sorted.count / 2]
    guard median > 0 else { return (times, pitches) }

    var filteredT: [Double] = []
    var filteredP: [Double] = []
    filteredT.reserveCapacity(times.count)
    filteredP.reserveCapacity(pitches.count)

    for i in 0..<pitches.count {
        let deviation = abs(pitches[i] - median) / median
        if deviation <= maxDeviationRatio {
            filteredT.append(times[i])
            filteredP.append(pitches[i])
        }
    }

    return (filteredT, filteredP)
}

// MARK: - Pitch Slope Classification

enum ToneDirection: String {
    case downward  // Authority - good
    case upward    // Questioning - needs work
    case flat      // Neutral

    var isAuthoritative: Bool { self == .downward }
}

// MARK: - Per-Sentence Feedback

/// What the pitch did at the end of a phrase.
enum PhraseEndingTone: String, CaseIterable {
    case down
    case up
    case unknown
}

/// Per-sentence grade: did the ending tone match the desired tone?
enum PhraseGrade: Equatable {
    case pass    // tone matches desired
    case fail    // tone doesn't match desired
    case unknown // couldn't determine tone
}

struct ToneClassification {
    let direction: ToneDirection
    let confidence: Double   // 0...1 (R-squared)
    let slopeHzPerSec: Double
}

/// Reason a phrase was classified as "unknown" instead of pass/fail.
/// Each case maps to a specific gate in the classification pipeline.
enum UnknownReason: String, Sendable {
    case tooFewSamples      // fewer than minPitchPoints in every window
    case phraseTooShort     // phrase duration below minPhraseDuration
    case lowVoicedFraction  // voiced fraction below minVoicedFraction
    case lowConfidence      // R² below confidenceThreshold
    case tooFlat            // slope within flat band after hysteresis
    case tooNoisy           // outlier ratio exceeded maxOutlierRatio
    case deduplicate        // same phrase-end already classified
}

/// Classify the pitch slope at the end of a phrase.
/// - Parameters:
///   - pitchValues: pitch in Hz sampled over time
///   - timeValues: corresponding timestamps in seconds
///   - slopeThreshold: Hz/s threshold to distinguish up/down from flat (default 15)
func classifyPitchSlope(
    pitchValues: [Double],
    timeValues: [Double],
    slopeThreshold: Double = 15.0
) -> ToneClassification {
    guard let result = linearRegression(x: timeValues, y: pitchValues) else {
        return ToneClassification(direction: .flat, confidence: 0, slopeHzPerSec: 0)
    }

    let direction: ToneDirection
    if result.slope < -slopeThreshold {
        direction = .downward
    } else if result.slope > slopeThreshold {
        direction = .upward
    } else {
        direction = .flat
    }

    return ToneClassification(
        direction: direction,
        confidence: result.rSquared,
        slopeHzPerSec: result.slope
    )
}

// MARK: - Normalization

/// Normalize a dB value to 0...1 range within the given bounds.
func normalizeDB(_ db: Double, min: Double, max: Double) -> Double {
    let range = max - min
    guard range > 0 else { return 0.5 }
    // Extend range by 50% on each side for the meter
    let extMin = min - range * 0.5
    let extMax = max + range * 0.5
    return Swift.min(Swift.max((db - extMin) / (extMax - extMin), 0), 1)
}

/// Normalize WPM to 0...1 range.
func normalizeWPM(_ wpm: Double, min: Double, max: Double) -> Double {
    let range = max - min
    guard range > 0 else { return 0.5 }
    let extMin = min - range * 0.5
    let extMax = max + range * 0.5
    return Swift.min(Swift.max((wpm - extMin) / (extMax - extMin), 0), 1)
}
