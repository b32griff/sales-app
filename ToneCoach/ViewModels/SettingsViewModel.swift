import Foundation

/// ViewModel for settings — presets + fine-grained sliders.
@MainActor
final class SettingsViewModel: ObservableObject {
    let settings = UserSettings.shared

    var targetDBMin: Double {
        get { settings.targetDBMin }
        set { settings.targetDBMin = newValue; objectWillChange.send() }
    }

    var targetDBMax: Double {
        get { settings.targetDBMax }
        set { settings.targetDBMax = newValue; objectWillChange.send() }
    }

    var targetWPMMin: Double {
        get { settings.targetWPMMin }
        set { settings.targetWPMMin = newValue; objectWillChange.send() }
    }

    var targetWPMMax: Double {
        get { settings.targetWPMMax }
        set { settings.targetWPMMax = newValue; objectWillChange.send() }
    }

    var sensitivity: Double {
        get { settings.sensitivity }
        set { settings.sensitivity = newValue; objectWillChange.send() }
    }

    var desiredEndingTone: PhraseEndingTone {
        get { settings.desiredEndingTone }
        set { settings.desiredEndingTone = newValue; objectWillChange.send() }
    }

    // MARK: - Presets

    var volumePreset: VolumePreset? {
        VolumePreset.from(dbMin: settings.targetDBMin, dbMax: settings.targetDBMax)
    }

    var speedPreset: SpeedPreset? {
        SpeedPreset.from(wpmMin: settings.targetWPMMin, wpmMax: settings.targetWPMMax)
    }

    func applyVolumePreset(_ preset: VolumePreset) {
        settings.targetDBMin = preset.dbMin
        settings.targetDBMax = preset.dbMax
        objectWillChange.send()
    }

    func applySpeedPreset(_ preset: SpeedPreset) {
        settings.targetWPMMin = preset.wpmMin
        settings.targetWPMMax = preset.wpmMax
        objectWillChange.send()
    }

    func resetToDefaults() {
        settings.targetDBMin = -55
        settings.targetDBMax = -30
        settings.targetWPMMin = 135
        settings.targetWPMMax = 185
        settings.sensitivity = 0.5
        settings.desiredEndingTone = .down
        objectWillChange.send()
    }
}
