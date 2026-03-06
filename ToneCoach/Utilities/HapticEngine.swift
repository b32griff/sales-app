import UIKit

/// Centralized haptic feedback manager.
///
/// All haptic events flow through this singleton so they can be:
/// - Globally toggled via `UserSettings.hapticsEnabled`
/// - Pre-warmed for low-latency response
/// - Consistent in intensity across the app
///
/// Haptic palette (matches iOS HIG conventions):
/// - **success**: phrase graded as pass → notification success (gentle double-tap)
/// - **fail**: phrase graded as fail → light impact (single tap)
/// - **warning**: coaching prompt / cadence banner → medium impact
/// - **sessionStart**: recording begins → rigid impact (confident thud)
/// - **sessionStop**: recording ends → soft impact (subtle close)
/// - **selection**: UI selection change → selection generator
final class HapticEngine {
    static let shared = HapticEngine()

    private let notificationGen = UINotificationFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen = UISelectionFeedbackGenerator()

    private init() {}

    /// Call before a burst of haptics (e.g. session start) to reduce latency.
    func prepare() {
        notificationGen.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
    }

    // MARK: - Semantic Events

    /// Phrase graded as pass — gentle success tap.
    func phrasePass() {
        guard UserSettings.shared.hapticsEnabled else { return }
        notificationGen.notificationOccurred(.success)
    }

    /// Phrase graded as fail — single light tap.
    func phraseFail() {
        guard UserSettings.shared.hapticsEnabled else { return }
        lightImpact.impactOccurred()
    }

    /// Coaching prompt or cadence banner appeared — medium nudge.
    func coachingNudge() {
        guard UserSettings.shared.hapticsEnabled else { return }
        mediumImpact.impactOccurred()
    }

    /// Session recording started — confident thud.
    func sessionStart() {
        guard UserSettings.shared.hapticsEnabled else { return }
        rigidImpact.impactOccurred()
    }

    /// Session recording stopped — subtle close.
    func sessionStop() {
        guard UserSettings.shared.hapticsEnabled else { return }
        softImpact.impactOccurred()
    }

    /// Generic selection feedback (tab switches, picker changes).
    func selection() {
        guard UserSettings.shared.hapticsEnabled else { return }
        selectionGen.selectionChanged()
    }
}
