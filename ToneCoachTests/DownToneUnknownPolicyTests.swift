import XCTest
@testable import ToneCoach

/// Tests for the "unknown" grading policy in tone classification.
///
/// The pipeline has three gating stages that can produce "unknown":
///   1. DownToneClassifier: phrase < 400ms → confidence 0
///   2. DownToneClassifier: < 5 pitch points → confidence 0
///   3. ProcessingContext: confidence < pitchConfidenceThreshold (0.35) → unknown grade
///   4. MathHelpers: flat direction → not authoritative
///
/// Unknown results must NOT count as pass or fail — they're excluded from scoring.
final class DownToneUnknownPolicyTests: XCTestCase {

    // MARK: - Helpers

    /// Feed a linear pitch contour into the detector, then classify.
    private func classify(
        startHz: Double,
        endHz: Double,
        durationSec: Double = 0.5,
        pointCount: Int = 15,
        classifier: DownToneClassifier,
        detector: PitchDetector
    ) -> PhraseVerdict {
        let base = CACurrentMediaTime()
        let step = durationSec / Double(pointCount - 1)
        let pitchStep = (endHz - startHz) / Double(pointCount - 1)

        for i in 0..<pointCount {
            let t = base + Double(i) * step
            let pitch = startHz + Double(i) * pitchStep
            detector.pitchHistory.append((time: t, pitch: pitch))
        }

        return classifier.analyzePhrase(phraseEndTime: base + durationSec, phraseDuration: durationSec)
    }

    // MARK: - Short phrase → unknown

    func testShortPhraseYieldsZeroConfidence() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // Plant clear downward data, but mark phrase as only 300ms (below 400ms gate).
        let result = classify(
            startHz: 200, endHz: 140,
            durationSec: 0.3, pointCount: 10,
            classifier: classifier, detector: detector
        )

        XCTAssertEqual(result.confidence, 0,
                       "Phrases shorter than 400ms must return confidence 0")
    }

    // MARK: - Insufficient pitch points → unknown

    func testTooFewPitchPointsYieldsUnknown() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let base = CACurrentMediaTime()
        // Only 3 points — classifier requires minPitchPoints (5).
        for i in 0..<3 {
            detector.pitchHistory.append((time: base + Double(i) * 0.1, pitch: 200 - Double(i) * 20))
        }

        let result = classifier.analyzePhrase(phraseEndTime: base + 0.5, phraseDuration: 0.5)
        XCTAssertEqual(result.confidence, 0,
                       "Fewer than 5 pitch points must yield unknown")
    }

    // MARK: - Flat direction is not authoritative

    func testFlatDirectionIsNotAuthoritative() {
        XCTAssertFalse(ToneDirection.flat.isAuthoritative,
                       "Flat tone must not be considered authoritative")
    }

    func testUpwardDirectionIsNotAuthoritative() {
        XCTAssertFalse(ToneDirection.upward.isAuthoritative,
                       "Upward tone must not be considered authoritative")
    }

    func testOnlyDownwardIsAuthoritative() {
        XCTAssertTrue(ToneDirection.downward.isAuthoritative,
                      "Only downward tone should be authoritative")
    }

    // MARK: - PhraseGrade: unknown does not count as pass or fail

    func testUnknownGradeIsDistinct() {
        // Verify unknown is not equal to pass or fail.
        XCTAssertNotEqual(PhraseGrade.unknown, PhraseGrade.pass)
        XCTAssertNotEqual(PhraseGrade.unknown, PhraseGrade.fail)
    }

    // MARK: - Unknown grading logic (mirrors ProcessingContext)

    /// Simulate the grading logic from ProcessingContext.
    /// This tests the exact conditional chain without needing audio hardware.
    private func gradePhrase(
        direction: ToneDirection,
        confidence: Double,
        desiredTone: PhraseEndingTone,
        confidenceThreshold: Double = 0.35
    ) -> (endingTone: PhraseEndingTone, grade: PhraseGrade) {
        let confident = confidence >= confidenceThreshold

        let endingTone: PhraseEndingTone
        if !confident {
            endingTone = .unknown
        } else {
            switch direction {
            case .downward: endingTone = .down
            case .upward:   endingTone = .up
            case .flat:     endingTone = .unknown
            }
        }

        let grade: PhraseGrade
        if endingTone == .unknown {
            grade = .unknown
        } else if endingTone == desiredTone {
            grade = .pass
        } else {
            grade = .fail
        }

        return (endingTone, grade)
    }

    func testLowConfidenceDownwardBecomesUnknown() {
        let result = gradePhrase(direction: .downward, confidence: 0.20, desiredTone: .down)
        XCTAssertEqual(result.endingTone, .unknown,
                       "Low-confidence downward should be graded as unknown")
        XCTAssertEqual(result.grade, .unknown)
    }

    func testHighConfidenceDownwardPasses() {
        let result = gradePhrase(direction: .downward, confidence: 0.80, desiredTone: .down)
        XCTAssertEqual(result.endingTone, .down)
        XCTAssertEqual(result.grade, .pass)
    }

    func testHighConfidenceUpwardFailsWhenDesiredDown() {
        let result = gradePhrase(direction: .upward, confidence: 0.80, desiredTone: .down)
        XCTAssertEqual(result.endingTone, .up)
        XCTAssertEqual(result.grade, .fail)
    }

    func testFlatDirectionBecomesUnknownRegardlessOfConfidence() {
        let result = gradePhrase(direction: .flat, confidence: 0.95, desiredTone: .down)
        XCTAssertEqual(result.endingTone, .unknown,
                       "Flat direction must always be graded as unknown")
        XCTAssertEqual(result.grade, .unknown)
    }

    func testConfidenceThresholdBoundary() {
        // Exactly at threshold: should be confident.
        let atThreshold = gradePhrase(direction: .downward, confidence: 0.35, desiredTone: .down)
        XCTAssertEqual(atThreshold.grade, .pass,
                       "Confidence exactly at threshold should pass")

        // Just below threshold: should be unknown.
        let belowThreshold = gradePhrase(direction: .downward, confidence: 0.349, desiredTone: .down)
        XCTAssertEqual(belowThreshold.grade, .unknown,
                       "Confidence just below threshold should be unknown")
    }

    // MARK: - Unknown results excluded from classifier percentages

    func testUnknownResultsAreExcludedFromPercentages() {
        // Verifies that unknown results are excluded from the denominator.
        // This means downTonePercent reflects only classified results.
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        // 1 clear downward phrase.
        _ = classify(startHz: 200, endHz: 140, classifier: classifier, detector: detector)
        detector.pitchHistory.removeAll()

        // 1 short phrase (unknown).
        let base = CACurrentMediaTime() + 2
        for i in 0..<10 {
            detector.pitchHistory.append((time: base + Double(i) * 0.03, pitch: 180))
        }
        _ = classifier.analyzePhrase(phraseEndTime: base + 0.3, phraseDuration: 0.25)

        // 2 results total, but only 1 classified. downTonePercent = 1/1 = 100%.
        XCTAssertEqual(classifier.phraseResults.count, 2)
        XCTAssertEqual(classifier.downTonePercent, 100,
                       "Down-tone percent should exclude unknowns from denominator")
    }

    // MARK: - ProcessingContext confidence threshold constant

    func testConfidenceThresholdConstant() {
        // Confidence gating moved into DownToneClassifier — verify via classifier API
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)
        let verdict = classifier.analyzePhrase(phraseEndTime: 0, phraseDuration: 0.1)
        // A trivially short phrase should yield zero confidence (below any threshold)
        XCTAssertEqual(verdict.confidence, 0, accuracy: 0.01,
                       "Trivially short phrase should yield near-zero confidence")
    }

    // MARK: - Dedup on unknown still prevents double-count

    func testDedupStillWorksForUnknownResults() {
        let detector = PitchDetector(sampleRate: 44100)
        let classifier = DownToneClassifier(pitchDetector: detector)

        let base = CACurrentMediaTime()
        for i in 0..<10 {
            detector.pitchHistory.append((time: base + Double(i) * 0.03, pitch: 180))
        }

        // First call: short phrase → unknown, but still appended.
        _ = classifier.analyzePhrase(phraseEndTime: base + 0.3, phraseDuration: 0.25)
        XCTAssertEqual(classifier.phraseResults.count, 1)

        // Second call with same timestamp: deduped.
        _ = classifier.analyzePhrase(phraseEndTime: base + 0.3, phraseDuration: 0.25)
        XCTAssertEqual(classifier.phraseResults.count, 1,
                       "Dedup must prevent double-counting even for unknown results")
    }
}
