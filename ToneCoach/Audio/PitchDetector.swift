import Foundation
import Accelerate

/// YIN-based pitch detector for speech fundamental frequency estimation.
///
/// The YIN algorithm uses autocorrelation to estimate pitch. It's well-suited
/// for monophonic speech signals and runs efficiently on audio buffers.
///
/// Key parameters:
/// - threshold: 0.15 (lower = stricter, fewer false positives)
/// - Expected range for speech: 80-400 Hz (male ~85-180, female ~165-255)
final class PitchDetector {
    private var sampleRate: Double
    private let threshold: Float
    private let minFrequency: Double = 75   // Hz — allow deep voices
    private let maxFrequency: Double = 500  // Hz — allow higher female voices

    /// Recent pitch readings (Hz) with timestamps, used for phrase-end analysis.
    internal var pitchHistory: [(time: Double, pitch: Double)] = []

    init(sampleRate: Double = 44100, threshold: Float = 0.15) {
        self.sampleRate = sampleRate
        self.threshold = threshold
    }

    /// Update sample rate to match actual device hardware.
    func updateSampleRate(_ rate: Double) {
        sampleRate = rate
    }

    // Reusable scratch buffer for vDSP — avoids allocation per pitch frame
    private var diffScratch: [Float] = []

    /// Detect pitch from an audio buffer. Returns frequency in Hz, or nil if unvoiced.
    func detectPitch(samples: [Float], timestamp: Double) -> Double? {
        let bufferSize = samples.count
        let minLag = Int(sampleRate / maxFrequency) // ~110 at 44100Hz
        let maxLag = Int(sampleRate / minFrequency) // ~551 at 44100Hz

        guard bufferSize > maxLag * 2 else { return nil }

        // Step 1: Compute the difference function using vDSP (SIMD-accelerated)
        // d(tau) = sum((x[j] - x[j+tau])^2) for j in 0..<(N-tau)
        // Rewritten: vDSP_vsub to get diff, then vDSP_svesq for sum-of-squares
        var diff = [Float](repeating: 0, count: maxLag)
        if diffScratch.count < bufferSize { diffScratch = [Float](repeating: 0, count: bufferSize) }

        samples.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for tau in minLag..<maxLag {
                let count = vDSP_Length(bufferSize - tau)
                // diffScratch = samples[0..] - samples[tau..]
                vDSP_vsub(base + tau, 1, base, 1, &diffScratch, 1, count)
                // diff[tau] = sum(diffScratch^2)
                var sum: Float = 0
                vDSP_svesq(diffScratch, 1, &sum, count)
                diff[tau] = sum
            }
        }

        // Step 2: Cumulative mean normalized difference function (CMND)
        var cmnd = [Float](repeating: 1, count: maxLag)
        var runningSum: Float = 0
        for tau in minLag..<maxLag {
            runningSum += diff[tau]
            if runningSum > 0 {
                cmnd[tau] = diff[tau] * Float(tau - minLag + 1) / runningSum
            }
        }

        // Step 3: Find the first dip below threshold
        var bestTau = -1
        for tau in minLag..<(maxLag - 1) {
            if cmnd[tau] < threshold {
                // Find the local minimum
                if cmnd[tau] < cmnd[tau + 1] {
                    bestTau = tau
                    break
                }
            }
        }

        guard bestTau > 0 else { return nil }

        // Step 4: Parabolic interpolation for sub-sample accuracy
        let interpolatedTau: Double
        if bestTau > minLag && bestTau < maxLag - 1 {
            let s0 = Double(cmnd[bestTau - 1])
            let s1 = Double(cmnd[bestTau])
            let s2 = Double(cmnd[bestTau + 1])
            let shift = (s0 - s2) / (2 * (s0 - 2 * s1 + s2))
            interpolatedTau = Double(bestTau) + (shift.isFinite ? shift : 0)
        } else {
            interpolatedTau = Double(bestTau)
        }

        let frequency = sampleRate / interpolatedTau

        // Validate range
        guard frequency >= minFrequency && frequency <= maxFrequency else { return nil }

        pitchHistory.append((time: timestamp, pitch: frequency))

        // Keep only last 10 seconds of history — O(log n) binary search
        // since pitchHistory is chronologically sorted.
        let cutoff = timestamp - 10.0
        if let first = pitchHistory.first, first.time < cutoff {
            var lo = 0, hi = pitchHistory.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if pitchHistory[mid].time < cutoff { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { pitchHistory.removeFirst(lo) }
        }

        return frequency
    }

    /// Get pitch values for the last N milliseconds.
    /// Uses binary search on the sorted history for O(log n) lookup.
    func recentPitch(lastMs: Double, before: Double? = nil) -> [(time: Double, pitch: Double)] {
        let endTime = before ?? (pitchHistory.last?.time ?? 0)
        let startTime = endTime - lastMs / 1000.0

        // Binary search for startTime
        var lo = 0, hi = pitchHistory.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pitchHistory[mid].time < startTime { lo = mid + 1 } else { hi = mid }
        }
        let startIdx = lo

        // Binary search for endTime
        lo = startIdx; hi = pitchHistory.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pitchHistory[mid].time <= endTime { lo = mid + 1 } else { hi = mid }
        }
        let endIdx = lo

        guard startIdx < endIdx else { return [] }
        return Array(pitchHistory[startIdx..<endIdx])
    }

    func reset() {
        pitchHistory.removeAll()
    }
}
