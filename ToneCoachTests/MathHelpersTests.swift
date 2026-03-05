import XCTest
@testable import ToneCoach

final class MathHelpersTests: XCTestCase {

    // MARK: - RMS Tests

    func testRMSOfSilence() {
        let silence = [Float](repeating: 0, count: 1024)
        XCTAssertEqual(computeRMS(silence), 0, accuracy: 0.0001)
    }

    func testRMSOfConstantSignal() {
        let constant = [Float](repeating: 0.5, count: 1024)
        let rms = computeRMS(constant)
        XCTAssertEqual(rms, 0.5, accuracy: 0.01)
    }

    func testRMSOfSineWave() {
        // Sine wave RMS = amplitude / sqrt(2)
        let amplitude: Float = 1.0
        let samples = (0..<1024).map { i in
            amplitude * sin(Float(i) * 2.0 * .pi / 100.0)
        }
        let rms = computeRMS(samples)
        let expected = amplitude / sqrt(2.0)
        XCTAssertEqual(rms, expected, accuracy: 0.05)
    }

    func testRMSOfEmptyBuffer() {
        XCTAssertEqual(computeRMS([]), 0)
    }

    // MARK: - Decibel Conversion Tests

    func testDecibelFullScale() {
        // RMS of 1.0 = 0 dB
        XCTAssertEqual(rmsToDecibels(1.0), 0, accuracy: 0.01)
    }

    func testDecibelHalfScale() {
        // RMS of 0.5 ≈ -6 dB
        let db = rmsToDecibels(0.5)
        XCTAssertEqual(db, -6.02, accuracy: 0.1)
    }

    func testDecibelSilence() {
        XCTAssertEqual(rmsToDecibels(0), -80)
    }

    func testDecibelVeryQuiet() {
        let db = rmsToDecibels(0.001)
        XCTAssertEqual(db, -60, accuracy: 1)
    }

    // MARK: - EMA Tests

    func testEMAFirstValue() {
        let result = ema(previous: 0, current: 100, alpha: 0.3)
        XCTAssertEqual(result, 30, accuracy: 0.01)
    }

    func testEMAConvergence() {
        var value = 0.0
        for _ in 0..<100 {
            value = ema(previous: value, current: 50, alpha: 0.3)
        }
        XCTAssertEqual(value, 50, accuracy: 0.01)
    }

    // MARK: - Linear Regression Tests

    func testLinearRegressionPerfectLine() {
        let x = [0.0, 1.0, 2.0, 3.0, 4.0]
        let y = [0.0, 2.0, 4.0, 6.0, 8.0] // y = 2x
        let result = linearRegression(x: x, y: y)!
        XCTAssertEqual(result.slope, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.intercept, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.rSquared, 1.0, accuracy: 0.001)
    }

    func testLinearRegressionNegativeSlope() {
        let x = [0.0, 0.1, 0.2, 0.3]
        let y = [200.0, 195.0, 190.0, 185.0] // slope = -50 Hz/s
        let result = linearRegression(x: x, y: y)!
        XCTAssertEqual(result.slope, -50, accuracy: 1)
        XCTAssertTrue(result.rSquared > 0.99)
    }

    func testLinearRegressionInsufficientData() {
        let result = linearRegression(x: [1.0], y: [2.0])
        XCTAssertNil(result)
    }

    func testLinearRegressionEmptyInput() {
        let result = linearRegression(x: [], y: [])
        XCTAssertNil(result)
    }

    // MARK: - Normalization Tests

    func testNormalizeDBInRange() {
        let n = normalizeDB(-17.5, min: -25, max: -10) // midpoint
        XCTAssertEqual(n, 0.5, accuracy: 0.05)
    }

    func testNormalizeDBBelowRange() {
        let n = normalizeDB(-40, min: -25, max: -10)
        XCTAssertEqual(n, 0, accuracy: 0.01)
    }

    func testNormalizeDBAboveRange() {
        let n = normalizeDB(5, min: -25, max: -10)
        XCTAssertEqual(n, 1, accuracy: 0.01)
    }

    func testNormalizeWPMMidpoint() {
        let n = normalizeWPM(145, min: 130, max: 160)
        XCTAssertEqual(n, 0.5, accuracy: 0.05)
    }
}
