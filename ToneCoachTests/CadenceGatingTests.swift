import XCTest
@testable import ToneCoach

/// Tests for CadenceAnalyzer readiness gating.
///
/// The cadence analyzer must NOT publish WPM until BOTH gates are met:
///   1. minSecondsBeforeReady (3.0s of elapsed audio)
///   2. minWordsBeforeReady (3 detected syllable peaks)
///
/// This prevents absurd WPM numbers in the first seconds of a session.
final class CadenceGatingTests: XCTestCase {

    // MARK: - Gate boundary: time met, words not met

    func testGateNotReadyWhenTimeMetButWordsMissing() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let start = Date().timeIntervalSinceReferenceDate

        // Feed 5 seconds of near-silence (no syllable peaks).
        // RMS stays below syllableThreshold (0.02), so no peaks register.
        for i in 0..<100 {
            let t = start + Double(i) * 0.05
            analyzer.processSyllableFallback(rms: 0.001, timestamp: t)
        }

        XCTAssertFalse(analyzer.ready,
                       "Should NOT be ready: enough time but zero syllable peaks")
        XCTAssertEqual(analyzer.currentWPM, 0,
                       "WPM must be 0 when gate is not met")
    }

    // MARK: - Gate boundary: words met, time not met

    func testGateNotReadyWhenWordsMetButTimeTooShort() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let start = Date().timeIntervalSinceReferenceDate

        // Feed 2 seconds of rapid peaks — enough words but not enough time.
        // minSecondsBeforeReady = 3.0, so 2s is insufficient.
        for i in 0..<40 {
            let t = start + Double(i) * 0.05  // 40 * 0.05 = 2.0 seconds
            let rms: Float = (i % 2 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: t)
        }

        XCTAssertFalse(analyzer.ready,
                       "Should NOT be ready: enough peaks but only 2s elapsed (need 3s)")
        XCTAssertEqual(analyzer.currentWPM, 0)
    }

    // MARK: - Gate opens: both conditions met

    func testGateOpensWhenBothConditionsMet() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let start = Date().timeIntervalSinceReferenceDate

        // Feed 4 seconds of steady syllable peaks (well past both gates).
        for i in 0..<80 {
            let t = start + Double(i) * 0.05  // 80 * 0.05 = 4.0 seconds
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: t)
        }

        XCTAssertTrue(analyzer.ready,
                      "Should be ready: 4s elapsed + enough syllable peaks")
    }

    // MARK: - WPM transitions from 0 to non-zero exactly at gate

    func testWPMIsZeroBeforeGateAndNonZeroAfter() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let start = Date().timeIntervalSinceReferenceDate
        var wpmWasZeroBeforeGate = true
        var wpmBecameNonZero = false

        for i in 0..<200 {
            let t = start + Double(i) * 0.05
            let elapsed = Double(i) * 0.05
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: t)

            if elapsed < CadenceAnalyzer.minSecondsBeforeReady {
                if analyzer.currentWPM != 0 {
                    wpmWasZeroBeforeGate = false
                }
            }
            if analyzer.ready && analyzer.currentWPM > 0 {
                wpmBecameNonZero = true
            }
        }

        XCTAssertTrue(wpmWasZeroBeforeGate,
                      "WPM must be exactly 0 before the 3s gate")
        XCTAssertTrue(wpmBecameNonZero,
                      "WPM must become non-zero after gate opens with sufficient data")
    }

    // MARK: - Reset clears readiness

    func testResetClearsGate() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let start = Date().timeIntervalSinceReferenceDate
        for i in 0..<200 {
            let t = start + Double(i) * 0.05
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: t)
        }

        XCTAssertTrue(analyzer.ready, "Precondition: should be ready")

        analyzer.reset()

        XCTAssertFalse(analyzer.ready, "Reset must clear readiness")
        XCTAssertEqual(analyzer.currentWPM, 0, "Reset must zero WPM")
        XCTAssertEqual(analyzer.wordCount, 0, "Reset must zero word count")
    }

    // MARK: - Gate constants are sensible

    func testGateConstantsAreReasonable() {
        // These are critical for UX — too short = wild numbers, too long = feels broken.
        XCTAssertEqual(CadenceAnalyzer.minSecondsBeforeReady, 3.0,
                       "Gate should require 3 seconds of audio")
        XCTAssertEqual(CadenceAnalyzer.minWordsBeforeReady, 3,
                       "Gate should require 3 detected words/syllables")
    }

    // MARK: - Status returns .bad when not ready

    func testStatusIsBadBeforeGate() {
        let analyzer = CadenceAnalyzer()
        // Without any data, currentWPM = 0, which is way below any range.
        let status = analyzer.status(min: 130, max: 160)
        XCTAssertEqual(status, .bad,
                       "Status should be .bad when WPM is 0 (ungated)")
    }
}
