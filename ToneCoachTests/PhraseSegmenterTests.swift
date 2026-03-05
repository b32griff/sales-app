import XCTest
@testable import ToneCoach

final class PhraseSegmenterTests: XCTestCase {

    // MARK: - Helpers

    /// Simulate a "sentence" followed by silence.
    /// - speechDuration: how long the speech lasts (seconds)
    /// - silenceDuration: how long the silence lasts (seconds)
    /// - bufferInterval: time between process() calls (~buffer size / sample rate)
    /// - speechRMS: energy during speech
    /// - silenceRMS: energy during silence
    private func simulateSentence(
        _ seg: PhraseSegmenter,
        startTime: Double,
        speechDuration: Double = 1.5,
        silenceDuration: Double = 0.6,
        bufferInterval: Double = 0.046,  // 2048 / 44100
        speechRMS: Float = 0.06,
        silenceRMS: Float = 0.001
    ) -> Double {
        var t = startTime

        // Speech phase
        let speechEnd = startTime + speechDuration
        while t < speechEnd {
            seg.process(rms: speechRMS, timestamp: t)
            t += bufferInterval
        }

        // Silence phase
        let silenceEnd = t + silenceDuration
        while t < silenceEnd {
            seg.process(rms: silenceRMS, timestamp: t)
            t += bufferInterval
        }

        return t
    }

    // MARK: - Core: 10 sentences = 10 events

    func testTenSentencesProduceTenEvents() {
        let seg = PhraseSegmenter()
        var firedTimestamps: [(start: Double, end: Double)] = []
        seg.onPhraseEnd = { start, end in
            firedTimestamps.append((start, end))
        }

        var t = 0.0
        for _ in 0..<10 {
            t = simulateSentence(seg, startTime: t, speechDuration: 1.5, silenceDuration: 0.8)
        }

        XCTAssertEqual(firedTimestamps.count, 10,
                        "10 sentences should produce exactly 10 phrase-end events, got \(firedTimestamps.count)")
        XCTAssertEqual(seg.phraseCount, 10)
    }

    // MARK: - No double triggers

    func testNoDoubleTriggerFromTrailingSilence() {
        let seg = PhraseSegmenter()
        var fireCount = 0
        seg.onPhraseEnd = { _, _ in fireCount += 1 }

        var t = 0.0
        let interval = 0.046

        // Speech for 2 seconds
        while t < 2.0 {
            seg.process(rms: 0.08, timestamp: t)
            t += interval
        }

        // Long silence (3 seconds) — should fire exactly once
        while t < 5.0 {
            seg.process(rms: 0.001, timestamp: t)
            t += interval
        }

        XCTAssertEqual(fireCount, 1, "Long silence after speech should fire exactly once")
    }

    // MARK: - Minimum phrase duration

    func testShortNoiseBlipSuppressed() {
        let seg = PhraseSegmenter()
        var fireCount = 0
        seg.onPhraseEnd = { _, _ in fireCount += 1 }

        var t = 0.0
        let interval = 0.046

        // Initial silence
        while t < 1.0 {
            seg.process(rms: 0.001, timestamp: t)
            t += interval
        }

        // Very short noise blip (0.1s — below minPhraseDuration of 0.4s)
        while t < 1.1 {
            seg.process(rms: 0.08, timestamp: t)
            t += interval
        }

        // Silence again
        while t < 2.5 {
            seg.process(rms: 0.001, timestamp: t)
            t += interval
        }

        XCTAssertEqual(fireCount, 0,
                        "A 0.1s noise blip should NOT produce a phrase-end event")
    }

    // MARK: - Cooldown prevents rapid re-fire

    func testCooldownPreventsRapidRefire() {
        // Cooldown = 1.5s, so we can clearly test within vs. outside the window
        let seg = PhraseSegmenter(
            pauseDuration: 0.2,
            minPhraseDuration: 0.1,
            cooldownAfterFire: 1.5
        )
        var fireCount = 0
        seg.onPhraseEnd = { _, _ in fireCount += 1 }

        var t = 0.0
        let interval = 0.046

        // Sentence 1: speech 0–0.5, silence 0.5–1.0
        while t < 0.5 { seg.process(rms: 0.08, timestamp: t); t += interval }
        while t < 1.0 { seg.process(rms: 0.001, timestamp: t); t += interval }

        XCTAssertEqual(fireCount, 1, "First sentence should fire")

        // Rapid noise + silence at t=1.0–1.6 (within 1.5s cooldown from ~t=0.7)
        while t < 1.2 { seg.process(rms: 0.08, timestamp: t); t += interval }
        while t < 1.6 { seg.process(rms: 0.001, timestamp: t); t += interval }

        XCTAssertEqual(fireCount, 1, "Noise within cooldown should NOT fire again")

        // Real sentence well after cooldown (starts at t=3.0)
        while t < 3.0 { seg.process(rms: 0.001, timestamp: t); t += interval }
        while t < 4.0 { seg.process(rms: 0.08, timestamp: t); t += interval }
        while t < 5.0 { seg.process(rms: 0.001, timestamp: t); t += interval }

        XCTAssertEqual(fireCount, 2, "Sentence after cooldown should fire")
    }

    // MARK: - Adaptive threshold

    func testThresholdAdaptsToProlongedSilence() {
        let seg = PhraseSegmenter(energyThreshold: 0.008)
        let initial = seg.currentThreshold

        var t = 0.0
        let interval = 0.046

        // Feed very quiet silence (e.g., a quiet room)
        while t < 3.0 {
            seg.process(rms: 0.0005, timestamp: t)
            t += interval
        }

        let adapted = seg.currentThreshold
        XCTAssertLessThan(adapted, initial,
                          "Threshold should drop in a quiet environment (was \(initial), now \(adapted))")
        XCTAssertGreaterThanOrEqual(adapted, 0.003,
                                    "Threshold should never drop below absolute minimum")
    }

    func testThresholdRisesInNoisyEnvironment() {
        let seg = PhraseSegmenter(energyThreshold: 0.008)

        var t = 0.0
        let interval = 0.046

        // Phase 1: establish a low ambient floor with quiet silence
        while t < 3.0 {
            seg.process(rms: 0.0005, timestamp: t)
            t += interval
        }

        let lowThreshold = seg.currentThreshold

        // Phase 2: raise ambient noise (still below the current threshold)
        // Feed RMS just below the current threshold so it stays "silent"
        // and the EMA floor rises, dragging the threshold up.
        let noisyRMS: Float = min(lowThreshold - 0.0005, 0.01)
        while t < 10.0 {
            seg.process(rms: noisyRMS, timestamp: t)
            t += interval
        }

        let adapted = seg.currentThreshold
        XCTAssertGreaterThan(adapted, lowThreshold,
                             "Threshold should rise when ambient floor is elevated (was \(lowThreshold), now \(adapted))")
        XCTAssertLessThanOrEqual(adapted, 0.04,
                                 "Threshold should never exceed absolute maximum")
    }

    // MARK: - Clause-level pauses don't split

    func testClausePauseDoesNotSplit() {
        let seg = PhraseSegmenter()  // pauseDuration = 0.45
        var fireCount = 0
        seg.onPhraseEnd = { _, _ in fireCount += 1 }

        var t = 0.0
        let interval = 0.046

        // First clause
        while t < 1.0 { seg.process(rms: 0.06, timestamp: t); t += interval }

        // Comma pause (0.3s — below 0.45 threshold)
        while t < 1.3 { seg.process(rms: 0.001, timestamp: t); t += interval }

        // Second clause
        while t < 2.5 { seg.process(rms: 0.06, timestamp: t); t += interval }

        // Sentence-ending silence
        while t < 3.5 { seg.process(rms: 0.001, timestamp: t); t += interval }

        XCTAssertEqual(fireCount, 1,
                        "A 0.3s mid-sentence pause should NOT split the phrase")
    }

    // MARK: - Callback delivers clean timestamps

    func testCallbackTimestampsAreValid() {
        let seg = PhraseSegmenter()
        var captured: (start: Double, end: Double)?
        seg.onPhraseEnd = { start, end in
            captured = (start, end)
        }

        var t = 0.5  // start after some initial silence
        let interval = 0.046

        // Silence to stabilize
        while t < 1.0 { seg.process(rms: 0.001, timestamp: t); t += interval }

        let expectedStart = t  // speech starts here (approximately)
        // Speech
        while t < 2.5 { seg.process(rms: 0.06, timestamp: t); t += interval }

        let expectedEnd = t  // silence starts here (approximately)
        // Silence
        while t < 3.5 { seg.process(rms: 0.001, timestamp: t); t += interval }

        guard let result = captured else {
            XCTFail("onPhraseEnd should have fired")
            return
        }

        XCTAssertGreaterThan(result.start, 0, "Phrase start should be positive")
        XCTAssertGreaterThan(result.end, result.start, "Phrase end should be after start")
        XCTAssertEqual(result.start, expectedStart, accuracy: interval * 2,
                       "Phrase start should match speech onset")
        XCTAssertEqual(result.end, expectedEnd, accuracy: interval * 2,
                       "Phrase end should match silence onset")
    }

    // MARK: - Reset clears all state

    func testResetClearsState() {
        let seg = PhraseSegmenter()
        seg.onPhraseEnd = { _, _ in }

        var t = 0.0
        t = simulateSentence(seg, startTime: t)
        // Flush silence accounting by resuming speech
        seg.process(rms: 0.08, timestamp: t)

        XCTAssertEqual(seg.phraseCount, 1)
        XCTAssertGreaterThan(seg.totalSilenceTime, 0)

        seg.reset()

        XCTAssertEqual(seg.phraseCount, 0)
        XCTAssertEqual(seg.totalSilenceTime, 0)
        XCTAssertEqual(seg.powerPauseCount, 0)
    }
}
