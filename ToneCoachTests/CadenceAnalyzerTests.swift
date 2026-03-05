import XCTest
@testable import ToneCoach

final class CadenceAnalyzerTests: XCTestCase {

    func testInitialState() {
        let analyzer = CadenceAnalyzer()
        XCTAssertEqual(analyzer.currentWPM, 0)
        XCTAssertEqual(analyzer.wordCount, 0)
        XCTAssertFalse(analyzer.ready)
    }

    func testDataGatePreventsEarlyWPM() {
        // WPM should stay 0 until minSecondsBeforeReady AND minWordsBeforeReady are met
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let startTime = Date().timeIntervalSinceReferenceDate

        // Feed only 1 second of syllable data (below 3s gate)
        for i in 0..<20 {
            let time = startTime + Double(i) * 0.05
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: time)
        }

        XCTAssertEqual(analyzer.currentWPM, 0, "WPM should be 0 before data gate is met")
        XCTAssertFalse(analyzer.ready, "Should not be ready before 3 seconds")
    }

    func testSyllableFallbackConvergesAfterGate() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let startTime = Date().timeIntervalSinceReferenceDate

        // Simulate 10 seconds of steady syllable peaks (~3 peaks/sec ≈ 108 wpm)
        for i in 0..<200 {
            let time = startTime + Double(i) * 0.05
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: time)
        }

        XCTAssertTrue(analyzer.ready, "Should be ready after 10 seconds of data")
        XCTAssertTrue(analyzer.currentWPM > 0, "Expected non-zero WPM from syllable detection")
        XCTAssertTrue(analyzer.currentWPM >= 40, "WPM should not drop below floor of 40")
    }

    func testEMAStabilityOverTime() {
        // Simulate 20 seconds of steady syllables; WPM should converge and not jump wildly
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let startTime = Date().timeIntervalSinceReferenceDate
        var samples: [Double] = []

        for i in 0..<400 {
            let time = startTime + Double(i) * 0.05  // 50ms intervals = 20s total
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: time)

            // Sample WPM every second (every 20 iterations)
            if i > 0 && i % 20 == 0 && analyzer.ready {
                samples.append(analyzer.currentWPM)
            }
        }

        // After convergence (last 5 samples), WPM should be stable
        // Variance of last 5 samples should be low
        guard samples.count >= 5 else {
            XCTFail("Expected at least 5 WPM samples, got \(samples.count)")
            return
        }

        let tail = Array(samples.suffix(5))
        let mean = tail.reduce(0, +) / Double(tail.count)
        let variance = tail.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(tail.count)

        // Variance < 100 means WPM fluctuates by less than ±10 across samples
        XCTAssertLessThan(variance, 100, "WPM should be stable after convergence. Samples: \(tail)")
    }

    func testWPMFloorWhileActivelySpeaking() {
        // Even with very few syllable peaks, WPM should not drop below 40
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let startTime = Date().timeIntervalSinceReferenceDate

        // Very sparse peaks over 6 seconds — but still some speech
        for i in 0..<120 {
            let time = startTime + Double(i) * 0.05
            // Only 1 peak every 10 samples (very slow)
            let rms: Float = (i % 10 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: time)
        }

        if analyzer.ready && analyzer.currentWPM > 0 {
            XCTAssertGreaterThanOrEqual(analyzer.currentWPM, 40,
                "WPM floor should prevent values below 40 while speaking")
        }
    }

    func testStatusInRange() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let status = analyzer.status(min: 130, max: 160)
        // With currentWPM = 0, should be out of range
        XCTAssertEqual(status, .bad)
    }

    func testResetClearsState() {
        let analyzer = CadenceAnalyzer()
        analyzer.markSessionStart()

        let startTime = Date().timeIntervalSinceReferenceDate
        // Feed enough data to get ready
        for i in 0..<200 {
            let time = startTime + Double(i) * 0.05
            let rms: Float = (i % 3 == 0) ? 0.05 : 0.005
            analyzer.processSyllableFallback(rms: rms, timestamp: time)
        }

        analyzer.reset()
        XCTAssertEqual(analyzer.currentWPM, 0)
        XCTAssertEqual(analyzer.wordCount, 0)
        XCTAssertFalse(analyzer.ready)
    }

    // MARK: - Coaching State Machine Tests

    func testCoachingTooFastDebounce() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // WPM above max — debounce should prevent immediate trigger
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "Should debounce, not trigger yet")

        // 0.9s — still within 1.0s debounce
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0.9)
        XCTAssertEqual(analyzer.coachState.status, .inRange)

        // 1.1s — debounce threshold passed
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)
        XCTAssertEqual(analyzer.coachState.message, "Slow down")
        XCTAssertTrue(analyzer.coachState.isReady)
    }

    func testCoachingTooSlowAsymmetricDebounce() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // WPM below min
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 0)
        XCTAssertEqual(analyzer.coachState.status, .inRange)

        // 1.1s — would pass tooFast debounce (1.0s) but NOT tooSlow (1.5s)
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "tooSlow needs 1.5s debounce")

        // 1.6s — passes tooSlow debounce
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 1.6)
        XCTAssertEqual(analyzer.coachState.status, .tooSlow)
        XCTAssertEqual(analyzer.coachState.message, "Pick up the pace")
    }

    func testCoachingAutoResetAfter3Seconds() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // Trigger tooFast
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)

        // 2.0s into hold — still showing
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 3.0)
        XCTAssertEqual(analyzer.coachState.status, .tooFast, "Should hold for 3s")

        // 3.1s after trigger — auto-reset
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 4.2)
        XCTAssertEqual(analyzer.coachState.status, .inRange)
        XCTAssertNil(analyzer.coachState.message)
    }

    func testCoachingEarlyClearOnInRange() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // Trigger tooFast at t=1.1
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)

        // Return to range at t=1.5 — hold persists
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 1.5)
        XCTAssertEqual(analyzer.coachState.status, .tooFast, "Should hold during early inRange")

        // 1.9s of inRange — not enough (need 2.0s)
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 3.4)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)

        // 2.1s of inRange — early clear
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 3.6)
        XCTAssertEqual(analyzer.coachState.status, .inRange)
    }

    func testCoachingCooldownPreventsRetrigger() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // Trigger and auto-reset
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)

        // Auto-reset at 3s
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 4.2)
        XCTAssertEqual(analyzer.coachState.status, .inRange)

        // Still fast, but within 3s cooldown — should NOT re-trigger
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 5.0)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "Cooldown should prevent re-trigger")

        // After cooldown (3s) + debounce (1.0s) — re-trigger
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 7.3)  // cooldown expires, debounce starts
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 8.4)  // 1.1s debounce
        XCTAssertEqual(analyzer.coachState.status, .tooFast, "Should re-trigger after cooldown + debounce")
    }

    func testCoachingNotReadyProducesNoCoaching() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // High WPM but not ready — no coaching
        analyzer.evaluateCoaching(wpm: 200, isReady: false, timestamp: 5.0)
        XCTAssertEqual(analyzer.coachState.status, .inRange)
        XCTAssertFalse(analyzer.coachState.isReady)
        XCTAssertNil(analyzer.coachState.message)
    }

    func testCoachingDirectionChangeResetsDebounce() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // Start tooFast debounce
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)

        // At 0.8s switch to tooSlow — debounce resets
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 0.8)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "Direction change resets debounce")

        // 1.0s of tooSlow (0.8 + 1.0 = 1.8) — not enough for tooSlow (1.5s from 0.8)
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 1.8)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "1.0s < 1.5s threshold for tooSlow")

        // 1.5s of tooSlow — triggers
        analyzer.evaluateCoaching(wpm: 100, isReady: true, timestamp: 2.4)
        XCTAssertEqual(analyzer.coachState.status, .tooSlow)
        XCTAssertEqual(analyzer.coachState.message, "Pick up the pace")
    }

    func testCoachingInRangeBounceDoesNotClearEarly() {
        let analyzer = CadenceAnalyzer()
        analyzer.setTargetRange(min: 135, max: 185)

        // Trigger tooFast
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 0)
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 1.1)
        XCTAssertEqual(analyzer.coachState.status, .tooFast)

        // Return to range at t=2.0
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 2.0)

        // Bounce back out at t=2.5 — resets inRange counter
        analyzer.evaluateCoaching(wpm: 200, isReady: true, timestamp: 2.5)

        // Return to range at t=3.0
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 3.0)

        // 1.0s of inRange (since t=3.0) — not enough
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 3.9)
        XCTAssertEqual(analyzer.coachState.status, .tooFast, "Bounce should reset inRange counter")

        // Auto-reset at 3s from trigger (t=1.1 + 3.0 = t=4.1)
        analyzer.evaluateCoaching(wpm: 160, isReady: true, timestamp: 4.2)
        XCTAssertEqual(analyzer.coachState.status, .inRange, "Auto-reset after 3s hold")
    }
}
