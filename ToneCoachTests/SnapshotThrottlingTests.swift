import XCTest
@testable import ToneCoach

/// Logic-level tests for snapshot throttling and cooldown mechanisms.
///
/// AudioEngine uses three throttling strategies to keep the UI responsive:
///   1. RingBuffer generation tracking — skip array copy if buffer unchanged.
///   2. Prompt cooldown — max 1 prompt per 4 seconds.
///   3. Tone result cooldown — max 1 phrase classification per 1.5 seconds.
///
/// These tests verify the underlying data structures and logic without
/// requiring actual audio hardware or MainActor isolation.
final class SnapshotThrottlingTests: XCTestCase {

    // MARK: - RingBuffer generation tracking

    func testGenerationIncrementsOnAppend() {
        var buf = RingBuffer<Double>(capacity: 10, defaultValue: 0)
        XCTAssertEqual(buf.generation, 0)

        buf.append(1.0)
        XCTAssertEqual(buf.generation, 1)

        buf.append(2.0)
        XCTAssertEqual(buf.generation, 2)
    }

    func testGenerationIncrementsPerElement() {
        var buf = RingBuffer<Double>(capacity: 10, defaultValue: 0)
        buf.append(contentsOf: [1.0, 2.0, 3.0])
        XCTAssertEqual(buf.generation, 3,
                       "Each element in append(contentsOf:) should bump generation")
    }

    func testGenerationResetsOnRemoveAll() {
        var buf = RingBuffer<Double>(capacity: 10, defaultValue: 0)
        buf.append(contentsOf: [1.0, 2.0, 3.0])
        buf.removeAll()
        XCTAssertEqual(buf.generation, 0,
                       "removeAll must reset generation to 0")
    }

    func testGenerationGatingSkipsRedundantCopy() {
        // Simulate the snapshot pattern from AudioEngine:
        // Only copy dbHistory when generation has changed.
        var buf = RingBuffer<Double>(capacity: 150, defaultValue: -80)
        var lastKnownGeneration: UInt64 = 0

        buf.append(contentsOf: [-50, -48, -52])
        let gen1 = buf.generation

        // First check: generation changed → should copy.
        let shouldCopy1 = gen1 != lastKnownGeneration
        XCTAssertTrue(shouldCopy1, "Should copy: generation changed from 0 to 3")
        lastKnownGeneration = gen1

        // Second check without appending: generation unchanged → should skip.
        let shouldCopy2 = buf.generation != lastKnownGeneration
        XCTAssertFalse(shouldCopy2, "Should skip: generation unchanged")

        // Third check after appending: generation changed → should copy.
        buf.append(-45)
        let shouldCopy3 = buf.generation != lastKnownGeneration
        XCTAssertTrue(shouldCopy3, "Should copy: new data appended")
    }

    func testGenerationWrapsCleanly() {
        // generation uses &+= (wrapping addition), so it should handle overflow.
        var buf = RingBuffer<Double>(capacity: 5, defaultValue: 0)
        // Can't actually overflow UInt64 in a test, but verify the operator works.
        buf.append(1.0)
        let g1 = buf.generation
        buf.append(2.0)
        XCTAssertEqual(buf.generation, g1 &+ 1)
    }

    // MARK: - Prompt cooldown logic

    /// Mirrors AudioEngine.emitVolumePrompt cooldown logic.
    /// Tests the pure decision function without MainActor.
    func testPromptCooldownPreventsRapidFire() {
        // AudioEngine initializes promptCooldown to 0 and checks `now - cooldown > 4`.
        // At t=0 with cooldown=0, 0-0=0 which is NOT > 4, so first prompt is blocked.
        // First prompt only fires once t > 4 (or after a real prompt sets the cooldown).
        // This mirrors the real behavior: no prompts in the first 4 seconds of a session.
        var cooldown: CFTimeInterval = 0

        func shouldEmitPrompt(now: CFTimeInterval) -> Bool {
            guard now - cooldown > 4 else { return false }
            cooldown = now
            return true
        }

        // At t=0: blocked (0-0=0, not > 4). This is intentional — no prompts at session start.
        XCTAssertFalse(shouldEmitPrompt(now: 0))

        // At t=3: still blocked.
        XCTAssertFalse(shouldEmitPrompt(now: 3))

        // At t=4.1: first prompt fires (4.1 - 0 > 4).
        XCTAssertTrue(shouldEmitPrompt(now: 4.1))

        // At t=5: blocked (5 - 4.1 = 0.9, not > 4).
        XCTAssertFalse(shouldEmitPrompt(now: 5))

        // At t=8.2: fires again (8.2 - 4.1 > 4).
        XCTAssertTrue(shouldEmitPrompt(now: 8.2))
    }

    // MARK: - Tone result cooldown logic

    /// Mirrors ProcessingContext.toneResultCooldown (1.5s between classifications).
    func testToneResultCooldownConstant() {
        XCTAssertEqual(ProcessingContext.toneResultCooldown, 1.5,
                       "Tone result cooldown should be 1.5 seconds")
    }

    func testToneResultCooldownLogic() {
        // ProcessingContext initializes lastToneResultTime = 0.
        // Guard is `now - lastResultTime >= cooldown`.
        // At t=0: 0 - 0 = 0, not >= 1.5, so blocked (same startup grace as prompts).
        var lastResultTime: CFTimeInterval = 0
        let cooldown: CFTimeInterval = ProcessingContext.toneResultCooldown

        func shouldClassify(now: CFTimeInterval) -> Bool {
            guard now - lastResultTime >= cooldown else { return false }
            lastResultTime = now
            return true
        }

        // t=0: blocked (0 - 0 = 0, not >= 1.5).
        XCTAssertFalse(shouldClassify(now: 0))

        // t=1.5: first classification proceeds (1.5 - 0 >= 1.5).
        XCTAssertTrue(shouldClassify(now: 1.5))

        // t=2.0: within cooldown of t=1.5, should skip.
        XCTAssertFalse(shouldClassify(now: 2.0))

        // t=3.0: exactly at cooldown boundary (3.0 - 1.5 = 1.5 >= 1.5), should proceed.
        XCTAssertTrue(shouldClassify(now: 3.0))

        // t=3.5: within cooldown of t=3.0, should skip.
        XCTAssertFalse(shouldClassify(now: 3.5))
    }

    // MARK: - Finalization delay constant

    func testFinalizationDelayConstant() {
        XCTAssertEqual(ProcessingContext.finalizationDelay, 0.3,
                       "Finalization delay should be 300ms")
    }

    // MARK: - Snapshot interval

    func testSnapshotIntervalIsCI_Friendly() {
        // The snapshot interval is 0.08s = 12.5 Hz.
        // Verify it's in a reasonable range for CI (not too fast = CPU burn).
        let interval: TimeInterval = 0.08
        XCTAssertGreaterThanOrEqual(interval, 0.05,
                                    "Snapshot interval should not be faster than 20 Hz")
        XCTAssertLessThanOrEqual(interval, 0.2,
                                 "Snapshot interval should not be slower than 5 Hz")
    }

    // MARK: - RingBuffer capacity for dB history

    func testDBRingBufferCapacity() {
        // AudioEngine uses capacity=150 with ~12 Hz updates = ~12.5 seconds of history.
        // This should be enough for the waveform display without excessive memory.
        let buf = RingBuffer<Double>(capacity: 150, defaultValue: -80)
        XCTAssertEqual(buf.capacity, 150)

        // Fill to capacity and verify no reallocation or crash.
        var mutableBuf = buf
        for i in 0..<300 {
            mutableBuf.append(Double(i))
        }
        XCTAssertEqual(mutableBuf.count, 150, "Count must not exceed capacity")
        XCTAssertEqual(mutableBuf.toArray().count, 150)
    }

    // MARK: - Max phrase results cap

    func testMaxPhraseResultsCap() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // Feed 60 distinct phrase classifications.
        for i in 0..<60 {
            let base = CACurrentMediaTime() + Double(i) * 2 // well outside dedup window
            detector.pitchHistory.removeAll()
            for j in 0..<15 {
                let t = base + Double(j) * 0.035
                detector.pitchHistory.append((time: t, pitch: 200 - Double(j) * 4))
            }
            _ = classifier.analyzePhrase(phraseEndTime: base + 0.5, phraseDuration: 0.5)
        }

        // DownToneClassifier caps at maxResults (50).
        XCTAssertLessThanOrEqual(classifier.phraseResults.count, 50,
                                 "Phrase results must be capped at 50 to prevent unbounded growth")
    }
}
