import Foundation
import Observation
import SwiftUI

// MARK: - Per-card @Observable state
// Each object is independently tracked by SwiftUI — only the card
// that reads a given state object redraws when it changes.
// A volume dB update will NOT cause the tone or cadence card to redraw.

@Observable
final class VolumeState {
    var label: String = "-- dB"
    var status: MeterStatus = .idle
    var dbHistory: [Double] = []
    /// Mirrors RingBuffer.generation — increments only when dbHistory actually changes.
    /// Used by VolumeCard debug overlay and to gate unnecessary redraws.
    var generation: UInt64 = 0
    #if DEBUG
    var debugSnapshotRate: Double = 0
    var debugBufferRate: Double = 0
    #endif
}

@Observable
final class ToneState {
    var phraseResults: [AudioEngine.PhraseResult] = []
    var passRate: Int = 0
    var phrasesAnalyzed: Int = 0
    var status: MeterStatus = .idle
    var desiredTone: PhraseEndingTone = .down
}

@Observable
final class CadenceState {
    var label: String = "--"
    var isApproximate: Bool = false
    var status: MeterStatus = .idle
    var rangeLabel: String = ""
    var bannerMessage: String?
}

@Observable
final class PromptState {
    var current: CoachingPrompt?
}

// MARK: - Binder (wires AudioEngine UITick → per-card state)

/// Receives AudioEngine's single UITick callback and writes into 4 isolated
/// @Observable state objects with equality gates. Each card view observes
/// only its own state, so a volume update never redraws the tone card.
///
/// Zero Combine subscriptions — one callback, one synchronous pass.
@MainActor
final class LiveCoachBinder {
    let volume = VolumeState()
    let tone = ToneState()
    let cadence = CadenceState()
    let prompt = PromptState()
    let settings: UserSettings

    // Cadence meter hysteresis — status only changes if new status persists for 1.0s
    private var confirmedCadenceStatus: MeterStatus = .idle
    private var pendingMeterStatus: MeterStatus = .idle
    private var cadenceMeterTimer: Timer?
    static let cadenceHysteresisInterval: TimeInterval = 1.0

    // Track phrase count to detect new phrases without array comparison
    private var lastPhraseCount: Int = 0

    private static let maxPhraseResults = 10

    init(audioEngine: AudioEngine, settings: UserSettings = .shared) {
        self.settings = settings
        cadence.rangeLabel = "\(Int(settings.targetWPMMin))–\(Int(settings.targetWPMMax)) wpm"
        tone.desiredTone = settings.desiredEndingTone

        // Single callback — replaces 5 Combine subscriptions
        audioEngine.onUITick = { [weak self] tick in
            self?.applyTick(tick)
        }
    }

    // MARK: - Apply UITick (equality-gated writes)

    /// Called once per snapshot tick (~12 Hz). All @Observable writes happen here
    /// in a single synchronous pass. Equality gates prevent unnecessary SwiftUI redraws.
    private func applyTick(_ tick: AudioEngine.UITick) {
        // ── Volume (writes only to VolumeState) ──
        let dbLabel = String(format: "%.0f dB", tick.db)
        if volume.label != dbLabel { volume.label = dbLabel }

        let volStatus = Self.volumeStatus(
            db: tick.db, min: settings.targetDBMin, max: settings.targetDBMax
        )
        if volume.status != volStatus { volume.status = volStatus }

        if let history = tick.dbHistory {
            volume.dbHistory = history
            volume.generation = tick.dbGeneration
        }

        #if DEBUG
        if volume.debugSnapshotRate != tick.snapshotRate { volume.debugSnapshotRate = tick.snapshotRate }
        if volume.debugBufferRate != tick.bufferRate { volume.debugBufferRate = tick.bufferRate }
        #endif

        // ── Cadence (writes only to CadenceState) ──
        let cadenceLabel: String
        if tick.cadenceReady && tick.wpm > 10 {
            if tick.cadenceIsApproximate {
                cadenceLabel = "~" + String(format: "%.0f", tick.wpm)
            } else {
                cadenceLabel = String(format: "%.0f", tick.wpm)
            }
        } else {
            cadenceLabel = "--"
        }
        if cadence.label != cadenceLabel { cadence.label = cadenceLabel }
        if cadence.isApproximate != tick.cadenceIsApproximate {
            cadence.isApproximate = tick.cadenceIsApproximate
        }

        let rawCadenceStatus = tick.cadenceReady ? Self.cadenceStatus(
            wpm: tick.wpm, min: settings.targetWPMMin, max: settings.targetWPMMax
        ) : .idle
        applyCadenceHysteresis(rawCadenceStatus)
        applyCadenceCoaching(tick.cadenceCoachState)

        // ── Tone (writes only to ToneState, only when new phrases arrive) ──
        if !tick.newPhrases.isEmpty {
            for phrase in tick.newPhrases {
                tone.phraseResults.append(phrase)
                if tone.phraseResults.count > Self.maxPhraseResults {
                    tone.phraseResults.removeFirst()
                }
            }

            let results = tone.phraseResults
            tone.phrasesAnalyzed = results.count

            let graded = results.filter { $0.grade != .unknown }
            if !graded.isEmpty {
                let passCount = graded.filter { $0.grade == .pass }.count
                let newPassRate = Int(Double(passCount) / Double(graded.count) * 100)
                if tone.passRate != newPassRate { tone.passRate = newPassRate }
                let newToneStatus: MeterStatus = newPassRate >= 70 ? .good :
                                                  newPassRate >= 40 ? .warning : .bad
                if tone.status != newToneStatus { tone.status = newToneStatus }
            } else {
                if tone.passRate != 0 { tone.passRate = 0 }
                if tone.status != .idle { tone.status = .idle }
            }
        }

        // ── Prompt (writes only to PromptState) ──
        // Suppress cadence-category prompts when the cadence banner is visible
        let newPrompt: CoachingPrompt?
        if tick.latestPrompt?.category == .cadence, cadence.bannerMessage != nil {
            newPrompt = nil  // banner already covers this
        } else {
            newPrompt = tick.latestPrompt
        }
        if prompt.current != newPrompt {
            prompt.current = newPrompt
        }
    }

    /// Reset all card state. Call at session start to clear stale data
    /// and refresh settings-dependent display values (range label, desired tone).
    func resetState() {
        volume.label = "-- dB"
        volume.status = .idle
        volume.dbHistory = []
        volume.generation = 0
        #if DEBUG
        volume.debugSnapshotRate = 0
        volume.debugBufferRate = 0
        #endif

        tone.phraseResults = []
        tone.passRate = 0
        tone.phrasesAnalyzed = 0
        tone.status = .idle
        tone.desiredTone = settings.desiredEndingTone

        cadence.label = "--"
        cadence.isApproximate = false
        cadence.status = .idle
        cadence.bannerMessage = nil
        cadence.rangeLabel = "\(Int(settings.targetWPMMin))–\(Int(settings.targetWPMMax)) wpm"

        prompt.current = nil
        lastPhraseCount = 0
    }

    // MARK: - Pure status computation

    private static func volumeStatus(db: Double, min: Double, max: Double) -> MeterStatus {
        let range = max - min
        if db < min - range * 0.3 || db > max + range * 0.3 { return .bad }
        if db < min || db > max { return .warning }
        return .good
    }

    private static func cadenceStatus(wpm: Double, min: Double, max: Double) -> MeterStatus {
        guard wpm > 10 else { return .idle }
        if wpm < min * 0.85 { return .bad }
        if wpm > max * 1.15 { return .bad }
        if wpm < min || wpm > max { return .warning }
        return .good
    }

    // MARK: - Cadence Meter Hysteresis

    private func applyCadenceHysteresis(_ rawStatus: MeterStatus) {
        if rawStatus == .good || rawStatus == .idle {
            cadenceMeterTimer?.invalidate()
            cadenceMeterTimer = nil
            confirmedCadenceStatus = rawStatus
            if cadence.status != rawStatus { cadence.status = rawStatus }
            pendingMeterStatus = rawStatus
            return
        }

        if rawStatus != pendingMeterStatus {
            pendingMeterStatus = rawStatus
            cadenceMeterTimer?.invalidate()
            cadenceMeterTimer = Timer.scheduledTimer(withTimeInterval: Self.cadenceHysteresisInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.confirmedCadenceStatus = self.pendingMeterStatus
                    if self.cadence.status != self.pendingMeterStatus {
                        self.cadence.status = self.pendingMeterStatus
                    }
                }
            }
        }
    }

    // MARK: - Cadence Coaching Banner (driven by CadenceCoachState from analyzer)
    //
    // Animation contract: ONE driver only.
    //   - Binder mutates bannerMessage inside withAnimation (drives insert/remove).
    //   - View declares .transition only — no .animation(value:).
    //
    // Debounce/cooldown handled in CadenceAnalyzer's timestamp-based state machine.
    // Binder just reads the computed coaching state and applies UI transitions.

    private func applyCadenceCoaching(_ state: CadenceCoachState) {
        let newMessage = state.message
        guard newMessage != cadence.bannerMessage else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            cadence.bannerMessage = newMessage
        }

        if newMessage != nil {
            HapticEngine.shared.coachingNudge()
            // Suppress duplicate cadence prompt from CoachingBadge
            if prompt.current?.category == .cadence {
                prompt.current = nil
            }
        }
    }

    /// Invalidate all pending timers. Call between sessions to prevent
    /// stale banners from a previous session leaking into the next one.
    func invalidateTimers() {
        cadenceMeterTimer?.invalidate()
        cadenceMeterTimer = nil
        cadence.bannerMessage = nil
        confirmedCadenceStatus = .idle
        pendingMeterStatus = .idle
    }
}
