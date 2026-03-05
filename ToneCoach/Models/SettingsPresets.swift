import Foundation

/// Protocol for settings presets (used by the generic preset picker).
protocol SettingsPreset: Equatable {
    var label: String { get }
    var subtitle: String { get }
}

// MARK: - Volume Presets

enum VolumePreset: CaseIterable, SettingsPreset {
    case soft, normal, loud

    var label: String {
        switch self {
        case .soft:   return "Soft"
        case .normal: return "Normal"
        case .loud:   return "Loud"
        }
    }

    var subtitle: String {
        switch self {
        case .soft:   return "-65 to -40 dB"
        case .normal: return "-55 to -30 dB"
        case .loud:   return "-45 to -20 dB"
        }
    }

    var dbMin: Double {
        switch self {
        case .soft:   return -65
        case .normal: return -55
        case .loud:   return -45
        }
    }

    var dbMax: Double {
        switch self {
        case .soft:   return -40
        case .normal: return -30
        case .loud:   return -20
        }
    }

    static func from(dbMin: Double, dbMax: Double) -> VolumePreset? {
        for preset in allCases {
            if abs(preset.dbMin - dbMin) < 3 && abs(preset.dbMax - dbMax) < 3 {
                return preset
            }
        }
        return nil
    }
}

// MARK: - Speed Presets

enum SpeedPreset: CaseIterable, SettingsPreset {
    case slow, normal, fast

    var label: String {
        switch self {
        case .slow:   return "Slow"
        case .normal: return "Normal"
        case .fast:   return "Fast"
        }
    }

    var subtitle: String {
        switch self {
        case .slow:   return "110-150 wpm"
        case .normal: return "135-185 wpm"
        case .fast:   return "160-210 wpm"
        }
    }

    var wpmMin: Double {
        switch self {
        case .slow:   return 110
        case .normal: return 135
        case .fast:   return 160
        }
    }

    var wpmMax: Double {
        switch self {
        case .slow:   return 150
        case .normal: return 185
        case .fast:   return 210
        }
    }

    static func from(wpmMin: Double, wpmMax: Double) -> SpeedPreset? {
        for preset in allCases {
            if abs(preset.wpmMin - wpmMin) < 10 && abs(preset.wpmMax - wpmMax) < 10 {
                return preset
            }
        }
        return nil
    }
}
