import XCTest
@testable import ToneCoach

final class SettingsPresetsTests: XCTestCase {

    // MARK: - Volume Presets

    func testVolumePresetFromExactValues() {
        XCTAssertEqual(VolumePreset.from(dbMin: -55, dbMax: -30), .normal)
        XCTAssertEqual(VolumePreset.from(dbMin: -65, dbMax: -40), .soft)
        XCTAssertEqual(VolumePreset.from(dbMin: -45, dbMax: -20), .loud)
    }

    func testVolumePresetFromCloseValues() {
        // Within tolerance of 3
        XCTAssertEqual(VolumePreset.from(dbMin: -54, dbMax: -29), .normal)
    }

    func testVolumePresetFromCustomValues() {
        // Too far from any preset
        XCTAssertNil(VolumePreset.from(dbMin: -70, dbMax: -10))
    }

    // MARK: - Speed Presets

    func testSpeedPresetFromExactValues() {
        XCTAssertEqual(SpeedPreset.from(wpmMin: 135, wpmMax: 185), .normal)
        XCTAssertEqual(SpeedPreset.from(wpmMin: 110, wpmMax: 150), .slow)
        XCTAssertEqual(SpeedPreset.from(wpmMin: 160, wpmMax: 210), .fast)
    }

    func testSpeedPresetFromCustomValues() {
        XCTAssertNil(SpeedPreset.from(wpmMin: 50, wpmMax: 300))
    }

    // MARK: - Preset Labels

    func testVolumePresetLabels() {
        XCTAssertEqual(VolumePreset.soft.label, "Soft")
        XCTAssertEqual(VolumePreset.normal.label, "Normal")
        XCTAssertEqual(VolumePreset.loud.label, "Loud")
    }

    func testSpeedPresetLabels() {
        XCTAssertEqual(SpeedPreset.slow.label, "Slow")
        XCTAssertEqual(SpeedPreset.normal.label, "Normal")
        XCTAssertEqual(SpeedPreset.fast.label, "Fast")
    }

    // MARK: - Ending Tone

    func testPhraseEndingToneRawValues() {
        XCTAssertEqual(PhraseEndingTone.down.rawValue, "down")
        XCTAssertEqual(PhraseEndingTone.up.rawValue, "up")
        XCTAssertEqual(PhraseEndingTone.unknown.rawValue, "unknown")
    }

    // MARK: - Volume Preset Values

    func testVolumePresetValues() {
        XCTAssertEqual(VolumePreset.soft.dbMin, -65)
        XCTAssertEqual(VolumePreset.soft.dbMax, -40)
        XCTAssertEqual(VolumePreset.normal.dbMin, -55)
        XCTAssertEqual(VolumePreset.normal.dbMax, -30)
        XCTAssertEqual(VolumePreset.loud.dbMin, -45)
        XCTAssertEqual(VolumePreset.loud.dbMax, -20)
    }

    // MARK: - Speed Preset Values

    func testSpeedPresetValues() {
        XCTAssertEqual(SpeedPreset.slow.wpmMin, 110)
        XCTAssertEqual(SpeedPreset.slow.wpmMax, 150)
        XCTAssertEqual(SpeedPreset.normal.wpmMin, 135)
        XCTAssertEqual(SpeedPreset.normal.wpmMax, 185)
        XCTAssertEqual(SpeedPreset.fast.wpmMin, 160)
        XCTAssertEqual(SpeedPreset.fast.wpmMax, 210)
    }
}
