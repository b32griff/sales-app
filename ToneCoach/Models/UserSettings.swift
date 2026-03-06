import Foundation
import SwiftUI

/// User-configurable coaching targets, backed by UserDefaults.
/// Volume defaults calibrated for iPhone microphone input levels.
/// Cadence: 135–185 WPM sweet spot per Hormozi.
final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    @AppStorage("targetDBMin")  var targetDBMin: Double = -55
    @AppStorage("targetDBMax")  var targetDBMax: Double = -30
    @AppStorage("targetWPMMin") var targetWPMMin: Double = 135
    @AppStorage("targetWPMMax") var targetWPMMax: Double = 185
    @AppStorage("sensitivity")  var sensitivity: Double = 0.5
    @AppStorage("saveRecordings") var saveRecordings: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("calibratedDBBaseline") var calibratedDBBaseline: Double = -45
    @AppStorage("desiredEndingTone") var desiredEndingToneRaw: String = PhraseEndingTone.down.rawValue
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true

    var desiredEndingTone: PhraseEndingTone {
        get { PhraseEndingTone(rawValue: desiredEndingToneRaw) ?? .down }
        set { desiredEndingToneRaw = newValue.rawValue }
    }

    var dbMidpoint: Double { (targetDBMin + targetDBMax) / 2.0 }
    var wpmMidpoint: Double { (targetWPMMin + targetWPMMax) / 2.0 }
}
