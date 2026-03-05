import Foundation
import Accelerate

/// Analyzes audio buffers to produce smoothed decibel readings.
/// Uses O(1) running stats instead of unbounded arrays.
final class VolumeAnalyzer {
    private var smoothedDB: Double = -80
    private let smoothingAlpha: Double = 0.3

    // Running stats — O(1) memory regardless of session length
    private var totalDB: Double = 0
    private var readingCount: Int = 0
    private var inRangeCount: Int = 0
    private var rangeMin: Double = -80
    private var rangeMax: Double = 0

    /// Process a buffer of audio samples and return the current dB level.
    func process(samples: [Float]) -> Double {
        let rms = computeRMS(samples)
        let db = Double(rmsToDecibels(rms))
        smoothedDB = ema(previous: smoothedDB, current: db, alpha: smoothingAlpha)
        totalDB += smoothedDB
        readingCount += 1
        if smoothedDB >= rangeMin && smoothedDB <= rangeMax {
            inRangeCount += 1
        }
        return smoothedDB
    }

    /// Set the target range for in-range tracking. Call before start.
    func setTargetRange(min: Double, max: Double) {
        rangeMin = min
        rangeMax = max
    }

    /// Average dB across all readings in this session.
    var averageDB: Double {
        guard readingCount > 0 else { return -80 }
        return totalDB / Double(readingCount)
    }

    /// Classify current level relative to target range.
    func status(current: Double, min: Double, max: Double) -> MeterStatus {
        let range = max - min
        if current < min - range * 0.3 || current > max + range * 0.3 { return .bad }
        if current < min || current > max { return .warning }
        return .good
    }

    /// Percentage of time the dB was within the target range. O(1).
    func inRangePercent(min: Double, max: Double) -> Double {
        guard readingCount > 0 else { return 0 }
        return Double(inRangeCount) / Double(readingCount) * 100
    }

    func reset() {
        smoothedDB = -80
        totalDB = 0
        readingCount = 0
        inRangeCount = 0
    }
}
