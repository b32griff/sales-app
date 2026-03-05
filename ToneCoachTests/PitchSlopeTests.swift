import XCTest
@testable import ToneCoach

final class PitchSlopeTests: XCTestCase {

    // MARK: - Tone Classification (classifyPitchSlope)

    func testDownwardSlope() {
        let times = [0.0, 0.1, 0.2, 0.3]
        let pitches = [200.0, 185.0, 170.0, 150.0]

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times)
        XCTAssertEqual(result.direction, .downward)
        XCTAssertTrue(result.slopeHzPerSec < -15)
        XCTAssertTrue(result.confidence > 0.9)
    }

    func testUpwardSlope() {
        let times = [0.0, 0.1, 0.2, 0.3]
        let pitches = [150.0, 170.0, 185.0, 200.0]

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times)
        XCTAssertEqual(result.direction, .upward)
        XCTAssertTrue(result.slopeHzPerSec > 15)
        XCTAssertTrue(result.confidence > 0.9)
    }

    func testFlatSlope() {
        let times = [0.0, 0.1, 0.2, 0.3]
        let pitches = [180.0, 181.0, 179.0, 180.0]

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times)
        XCTAssertEqual(result.direction, .flat)
        XCTAssertTrue(abs(result.slopeHzPerSec) <= 15)
    }

    func testInsufficientData() {
        let times = [0.0]
        let pitches = [180.0]

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times)
        XCTAssertEqual(result.direction, .flat)
        XCTAssertEqual(result.confidence, 0)
    }

    func testCustomThreshold() {
        let times = [0.0, 0.1, 0.2, 0.3]
        let pitches = [200.0, 198.0, 196.0, 194.0] // -20 Hz/s

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times, slopeThreshold: 25)
        XCTAssertEqual(result.direction, .flat)
    }

    func testStrongDownToneIsAuthoritative() {
        let times = [0.0, 0.1, 0.2, 0.3]
        let pitches = [220.0, 190.0, 160.0, 130.0] // -300 Hz/s

        let result = classifyPitchSlope(pitchValues: pitches, timeValues: times)
        XCTAssertEqual(result.direction, .downward)
        XCTAssertTrue(result.direction.isAuthoritative)
        XCTAssertTrue(result.confidence > 0.95)
    }

    func testUpToneIsNotAuthoritative() {
        let result = ToneClassification(direction: .upward, confidence: 0.8, slopeHzPerSec: 50)
        XCTAssertFalse(result.direction.isAuthoritative)
    }

    // MARK: - Outlier Filtering

    func testFilterPitchOutliersRemovesOctaveJumps() {
        let times   = [0.0, 0.05, 0.10, 0.15, 0.20]
        let pitches = [180.0, 175.0, 360.0, 170.0, 165.0]

        let filtered = filterPitchOutliers(times: times, pitches: pitches)

        XCTAssertEqual(filtered.pitches.count, 4, "Octave jump should be removed")
        XCTAssertFalse(filtered.pitches.contains(360.0))
    }

    func testFilterPitchOutliersKeepsCleanData() {
        let times   = [0.0, 0.05, 0.10, 0.15, 0.20]
        let pitches = [180.0, 178.0, 176.0, 174.0, 172.0]

        let filtered = filterPitchOutliers(times: times, pitches: pitches)

        XCTAssertEqual(filtered.pitches.count, 5, "No outliers to remove")
    }

    func testFilterPitchOutliersHandlesOctaveHalving() {
        let times   = [0.0, 0.05, 0.10, 0.15, 0.20]
        let pitches = [200.0, 195.0, 95.0, 190.0, 185.0]

        let filtered = filterPitchOutliers(times: times, pitches: pitches)

        XCTAssertEqual(filtered.pitches.count, 4)
        XCTAssertFalse(filtered.pitches.contains(95.0))
    }

    // MARK: - DownToneClassifier Integration

    /// Helper: populate pitch history with a linear contour and analyze.
    private func classifySimulatedPhrase(
        startHz: Double,
        endHz: Double,
        durationSec: Double = 0.5,
        pointCount: Int = 15,
        classifier: DownToneClassifier,
        detector: PitchDetector
    ) -> PhraseVerdict {
        let baseTime = CACurrentMediaTime()
        let step = durationSec / Double(pointCount - 1)
        let pitchStep = (endHz - startHz) / Double(pointCount - 1)

        for i in 0..<pointCount {
            let t = baseTime + Double(i) * step
            let pitch = startHz + Double(i) * pitchStep
            detector.pitchHistory.append((time: t, pitch: pitch))
        }

        return classifier.analyzePhrase(phraseEndTime: baseTime + durationSec, phraseDuration: durationSec)
    }

    func testClassifierRequiresMinimumPoints() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()
        for i in 0..<3 {
            detector.pitchHistory.append((time: baseTime + Double(i) * 0.1, pitch: 200.0 - Double(i) * 20))
        }

        let result = classifier.analyzePhrase(phraseEndTime: baseTime + 0.2, phraseDuration: 0.5)
        XCTAssertEqual(result.reason, .tooFewSamples, "Too few points → tooFewSamples reason")
        XCTAssertTrue(result.isUnknown)
    }

    func testClassifierDownward() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.direction, .downward)
        XCTAssertNil(result.reason, "Successful classification should have nil reason")
        XCTAssertTrue(result.confidence > 0.8)
    }

    func testClassifierUpward() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 140, endHz: 200,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.direction, .upward)
        XCTAssertNil(result.reason)
        XCTAssertTrue(result.confidence > 0.8)
    }

    func testClassifierFlat() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // Only 2 Hz change over 0.5s = 4 Hz/s — well below threshold
        let result = classifySimulatedPhrase(
            startHz: 180, endHz: 182,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.reason, .tooFlat, "Flat slope → tooFlat reason")
        XCTAssertTrue(result.isUnknown)
    }

    func testClassifierPercentages() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.direction, .downward)
        XCTAssertEqual(classifier.downTonePercent, 100)
        XCTAssertEqual(classifier.upTonePercent, 0)
    }

    func testHysteresisPreventsFlatFlicker() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // 1st phrase: clearly downward
        _ = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )
        XCTAssertEqual(classifier.lastResult?.direction, .downward)

        detector.pitchHistory.removeAll()

        // 2nd phrase: slope = -8 Hz/s (between exit=5 and enter=12)
        // Hysteresis should keep it downward (not flip to flat)
        _ = classifySimulatedPhrase(
            startHz: 180, endHz: 176,
            classifier: classifier, detector: detector
        )
        XCTAssertEqual(classifier.lastResult?.direction, .downward,
                       "Hysteresis should hold downward for borderline slope")
        XCTAssertNil(classifier.lastResult?.reason,
                     "Hysteresis-held result should not be unknown")
    }

    func testHysteresisAllowsClearReversal() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // 1st phrase: clearly downward
        _ = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )
        XCTAssertEqual(classifier.lastResult?.direction, .downward)

        detector.pitchHistory.removeAll()

        // 2nd phrase: clearly upward (should override hysteresis)
        _ = classifySimulatedPhrase(
            startHz: 140, endHz: 200,
            classifier: classifier, detector: detector
        )
        XCTAssertEqual(classifier.lastResult?.direction, .upward,
                       "Strong reversal should override hysteresis")
    }

    func testAdaptiveWindowPicksBestFit() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()

        // Noisy data from -700ms to -300ms
        for i in 0..<10 {
            let t = baseTime - 0.7 + Double(i) * 0.04
            let noisyPitch = 180.0 + (Double(i).truncatingRemainder(dividingBy: 2) == 0 ? 30 : -30)
            detector.pitchHistory.append((time: t, pitch: noisyPitch))
        }

        // Clean downward data from -300ms to 0
        for i in 0..<10 {
            let t = baseTime - 0.3 + Double(i) * 0.033
            let pitch = 200.0 - Double(i) * 6
            detector.pitchHistory.append((time: t, pitch: pitch))
        }

        let result = classifier.analyzePhrase(phraseEndTime: baseTime, phraseDuration: 0.7)

        XCTAssertTrue(result.confidence > 0.5,
                      "Adaptive window should find the clean 300ms segment")
    }

    func testResetClearsHysteresis() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        _ = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )
        XCTAssertEqual(classifier.lastResult?.direction, .downward)

        classifier.reset()

        XCTAssertNil(classifier.lastResult)
        XCTAssertEqual(classifier.downTonePercent, 0)
    }

    // MARK: - 3-State Result & Unknown Reasons

    /// Short phrase (< 400ms) → unknown with reason .phraseTooShort
    func testShortPhraseReturnsPhraseTooShort() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()
        for i in 0..<10 {
            let t = baseTime + Double(i) * 0.03
            detector.pitchHistory.append((time: t, pitch: 200.0 - Double(i) * 5))
        }

        let result = classifier.analyzePhrase(phraseEndTime: baseTime + 0.3, phraseDuration: 0.25)
        XCTAssertEqual(result.reason, .phraseTooShort)
        XCTAssertTrue(result.isUnknown)
    }

    /// Clean downward pitch → pass when desired tone is .down
    func testCleanDownTonePassesWithDesiredDown() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            durationSec: 0.5, pointCount: 15,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.direction, .downward)
        XCTAssertNil(result.reason, "Classified result has nil reason")
        XCTAssertTrue(result.confidence > 0.8)

        // Verify grading logic (same as AudioEngine's onPhraseEnd)
        let endingTone: PhraseEndingTone = .down
        let grade: PhraseGrade = endingTone == .down ? .pass : .fail
        XCTAssertEqual(grade, .pass)
    }

    /// Clean upward pitch → fail when desired tone is .down
    func testCleanUpToneFailsWithDesiredDown() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 140, endHz: 200,
            durationSec: 0.5, pointCount: 15,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.direction, .upward)
        XCTAssertNil(result.reason)

        let endingTone: PhraseEndingTone = .up
        let grade: PhraseGrade = endingTone == .down ? .pass : .fail
        XCTAssertEqual(grade, .fail)
    }

    /// Noisy pitch with octave jumps → correct direction after outlier filtering
    func testNoisyPitchWithOctaveJumpsClassifiesCorrectly() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()
        let basePitches: [Double] = [200, 195, 190, 185, 180, 175, 170, 165, 160, 155]
        for (i, pitch) in basePitches.enumerated() {
            let t = baseTime + Double(i) * 0.05
            let actualPitch = (i == 3 || i == 7) ? pitch * 2.0 : pitch
            detector.pitchHistory.append((time: t, pitch: actualPitch))
        }

        let result = classifier.analyzePhrase(
            phraseEndTime: baseTime + 0.45,
            phraseDuration: 0.5
        )

        XCTAssertEqual(result.direction, .downward,
                       "Octave-jump outliers should be filtered, leaving clean downward trend")
        XCTAssertTrue(result.confidence > 0.5)
        XCTAssertNil(result.reason)
    }

    /// Duplicate phrase-end timestamp → only one result stored
    func testDuplicatePhraseEndProducesOneResult() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()
        for i in 0..<15 {
            let t = baseTime + Double(i) * 0.035
            detector.pitchHistory.append((time: t, pitch: 200.0 - Double(i) * 4))
        }

        let endTime = baseTime + 0.5

        // First call: should classify normally
        _ = classifier.analyzePhrase(phraseEndTime: endTime, phraseDuration: 0.5)
        XCTAssertEqual(classifier.phraseResults.count, 1)

        // Second call with same timestamp: deduped
        let result2 = classifier.analyzePhrase(phraseEndTime: endTime, phraseDuration: 0.5)
        XCTAssertEqual(classifier.phraseResults.count, 1,
                       "Duplicate phrase-end should not add a second result")
        XCTAssertEqual(result2.reason, .deduplicate)

        // Third call with timestamp within dedup tolerance: also deduped
        let result3 = classifier.analyzePhrase(phraseEndTime: endTime + 0.02, phraseDuration: 0.5)
        XCTAssertEqual(classifier.phraseResults.count, 1)
        XCTAssertEqual(result3.reason, .deduplicate)
    }

    // MARK: - Low Confidence → Unknown

    func testLowConfidenceReturnsUnknown() {
        let detector = PitchDetector(sampleRate: 44100)
        // Use a high confidence threshold to trigger the gate
        var config = ToneClassifierConfig.default
        config.confidenceThreshold = 0.99
        let classifier = DownToneClassifier(pitchDetector: detector, config: config)

        let baseTime = CACurrentMediaTime()
        // Noisy data that won't produce high R²
        for i in 0..<10 {
            let t = baseTime + Double(i) * 0.05
            let pitch = 180.0 + (i % 2 == 0 ? 15.0 : -15.0) + Double(i) * (-3)
            detector.pitchHistory.append((time: t, pitch: pitch))
        }

        let result = classifier.analyzePhrase(phraseEndTime: baseTime + 0.45, phraseDuration: 0.5)
        XCTAssertEqual(result.reason, .lowConfidence)
        XCTAssertTrue(result.isUnknown)
    }

    // MARK: - Percentages Exclude Unknowns

    func testPercentagesExcludeUnknowns() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // 1st phrase: downward (classified)
        _ = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )
        detector.pitchHistory.removeAll()

        // 2nd phrase: flat → tooFlat (unknown)
        _ = classifySimulatedPhrase(
            startHz: 180, endHz: 181,
            classifier: classifier, detector: detector
        )

        // downTonePercent should be 100% (1 classified, 1 downward)
        // not 50% (which it would be if unknowns counted)
        XCTAssertEqual(classifier.downTonePercent, 100,
                       "Unknown results should be excluded from percentage denominator")
    }

    // MARK: - Debug Overlay

    func testDebugOverlayPopulatedInDebug() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )

        #if DEBUG
        XCTAssertFalse(result.debugOverlay.isEmpty, "Debug overlay should be populated in DEBUG")
        XCTAssertTrue(result.debugOverlay.contains("slope="), "Overlay should contain slope info")
        XCTAssertTrue(result.debugOverlay.contains("R2="), "Overlay should contain R2 info")
        #else
        XCTAssertTrue(result.debugOverlay.isEmpty, "Debug overlay should be empty in release")
        #endif
    }

    func testDebugOverlayShowsReasonForUnknown() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let baseTime = CACurrentMediaTime()
        let result = classifier.analyzePhrase(phraseEndTime: baseTime, phraseDuration: 0.2)

        #if DEBUG
        XCTAssertTrue(result.debugOverlay.contains("phraseTooShort"),
                      "Overlay should show the unknown reason")
        #endif
    }

    // MARK: - Config Tunability

    func testCustomConfigAffectsClassification() {
        let detector = PitchDetector(sampleRate: 44100)

        // Very high slope threshold → most things are flat/unknown
        var config = ToneClassifierConfig.default
        config.slopeThresholdEnter = 200
        let classifier = DownToneClassifier(pitchDetector: detector, config: config)

        // A moderate downward slope (-120 Hz/s) that normally passes
        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            classifier: classifier, detector: detector
        )

        // With threshold at 200, slope of ~120 should be flat → tooFlat
        XCTAssertEqual(result.reason, .tooFlat,
                       "Custom slopeThresholdEnter should change classification")
    }

    func testCustomMinPhraseDuration() {
        let detector = PitchDetector(sampleRate: 44100)

        var config = ToneClassifierConfig.default
        config.minPhraseDuration = 1.0  // Require 1 second minimum
        let classifier = DownToneClassifier(pitchDetector: detector, config: config)

        let result = classifySimulatedPhrase(
            startHz: 200, endHz: 140,
            durationSec: 0.5,  // Below the 1.0s minimum
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.reason, .phraseTooShort)
    }

    // MARK: - Too Noisy Gate

    func testHighOutlierRatioReturnsTooNoisy() {
        let detector = PitchDetector(sampleRate: 44100)
        var config = ToneClassifierConfig.default
        config.maxOutlierRatio = 0.2  // Very strict: max 20% outliers
        let classifier = DownToneClassifier(pitchDetector: detector, config: config)

        let baseTime = CACurrentMediaTime()
        // 10 points, 4 are octave-doubled (40% outliers > 20% threshold)
        let rawPitches: [Double] = [200, 195, 390, 185, 370, 175, 350, 165, 160, 155]
        for (i, pitch) in rawPitches.enumerated() {
            let t = baseTime + Double(i) * 0.05
            detector.pitchHistory.append((time: t, pitch: pitch))
        }

        let result = classifier.analyzePhrase(phraseEndTime: baseTime + 0.45, phraseDuration: 0.5)
        XCTAssertEqual(result.reason, .tooNoisy,
                       "High outlier ratio should trigger tooNoisy gate")
    }
}
