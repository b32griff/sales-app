import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var date: Date
    var durationSeconds: Double
    var averageDB: Double
    var dbInRangePercent: Double
    var averageWPM: Double
    var pauseRatio: Double
    var downTonePercent: Double
    var upTonePercent: Double
    var phraseCount: Int
    var articulationScore: Double
    var averagePauseSec: Double
    var powerPauseCount: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Double = 0,
        averageDB: Double = 0,
        dbInRangePercent: Double = 0,
        averageWPM: Double = 0,
        pauseRatio: Double = 0,
        downTonePercent: Double = 0,
        upTonePercent: Double = 0,
        phraseCount: Int = 0,
        articulationScore: Double = 0,
        averagePauseSec: Double = 0,
        powerPauseCount: Int = 0
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.averageDB = averageDB
        self.dbInRangePercent = dbInRangePercent
        self.averageWPM = averageWPM
        self.pauseRatio = pauseRatio
        self.downTonePercent = downTonePercent
        self.upTonePercent = upTonePercent
        self.phraseCount = phraseCount
        self.articulationScore = articulationScore
        self.averagePauseSec = averagePauseSec
        self.powerPauseCount = powerPauseCount
    }

    // MARK: - Computed metrics (not persisted)

    /// Weighted authority score (0–100) across all coaching dimensions.
    var authorityScore: Int {
        let settings = UserSettings.shared

        let toneScore = downTonePercent
        let volumeScore = dbInRangePercent

        let wpmRange = settings.targetWPMMax - settings.targetWPMMin
        let wpmMid = settings.wpmMidpoint
        let wpmDeviation = abs(averageWPM - wpmMid) / max(wpmRange / 2, 1)
        let speedScore = max(0, (1.0 - wpmDeviation)) * 100

        let pauseRatioPct = pauseRatio * 100
        let pauseScore: Double = (pauseRatioPct >= 15 && pauseRatioPct <= 25) ? 100 :
                                  (pauseRatioPct >= 10 && pauseRatioPct <= 35) ? 60 : 30

        return Int(toneScore * 0.35 + volumeScore * 0.30 + speedScore * 0.20 + pauseScore * 0.15)
    }

    /// One-line coaching takeaway based on the weakest dimension.
    var topTakeaway: String {
        let settings = UserSettings.shared

        let wpmRange = settings.targetWPMMax - settings.targetWPMMin
        let wpmMid = settings.wpmMidpoint
        let wpmDeviation = abs(averageWPM - wpmMid) / max(wpmRange / 2, 1)
        let speedScore = max(0, (1.0 - wpmDeviation)) * 100

        let pauseRatioPct = pauseRatio * 100
        let pauseScore: Double = (pauseRatioPct >= 15 && pauseRatioPct <= 25) ? 100 :
                                  (pauseRatioPct >= 10 && pauseRatioPct <= 35) ? 60 : 30

        let dimensions: [(String, Double)] = [
            ("tone", downTonePercent),
            ("volume", dbInRangePercent),
            ("speed", speedScore),
            ("pauses", pauseScore),
        ]

        guard let weakest = dimensions.min(by: { $0.1 < $1.1 }) else {
            return "Keep practicing to build consistency."
        }

        switch weakest.0 {
        case "tone":   return "Focus on ending phrases with a downward tone."
        case "volume": return "Work on keeping your volume steady and projected."
        case "speed":  return "Aim for a controlled, even speaking pace."
        case "pauses": return "Use deliberate pauses to let key points land."
        default:       return "Keep practicing to build consistency."
        }
    }
}
