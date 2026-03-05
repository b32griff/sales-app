#if DEBUG
import Foundation
import Combine

/// Samples AudioEngine metrics for the debug overlay.
/// Only exists in DEBUG builds. Receives data via UITick callback.
///
/// OWNERSHIP: Terminal 11 (Logging + Debug Overlay) only.
/// FIXED by Terminal 10 (QA) to compile against UITick-based AudioEngine.
@MainActor
final class DebugState: ObservableObject {

    // MARK: - Visibility

    @Published var isVisible = false

    // MARK: - Sampled metrics

    @Published private(set) var dbLabel: String = "--"
    @Published private(set) var snapshotHzLabel: String = "--"
    @Published private(set) var bufferHzLabel: String = "--"
    @Published private(set) var wpmLabel: String = "--"
    @Published private(set) var toneLabel: String = "no phrases"
    @Published private(set) var processingMsLabel: String = "n/a"

    // MARK: - Internal

    private var lastPhrases: [AudioEngine.PhraseResult] = []

    // MARK: - Lifecycle

    /// Call from LiveCoachBinder's UITick handler to feed data.
    func applyTick(_ tick: AudioEngine.UITick) {
        guard isVisible else { return }

        dbLabel = String(format: "%.1f dB", tick.db)
        snapshotHzLabel = String(format: "%.1f/s", tick.snapshotRate)
        bufferHzLabel = String(format: "%.0f/s", tick.bufferRate)

        if tick.cadenceReady {
            let source = tick.cadenceIsApproximate ? "~approx" : "ready"
            wpmLabel = String(format: "%.0f wpm (\(source))", tick.wpm)
        } else if tick.wpm > 0 {
            wpmLabel = String(format: "%.0f wpm (warming)", tick.wpm)
        } else {
            wpmLabel = "-- wpm (waiting)"
        }

        if !tick.newPhrases.isEmpty {
            lastPhrases = tick.newPhrases
        }

        if let last = lastPhrases.last {
            let arrow: String
            switch last.endingTone {
            case .down:    arrow = "dn"
            case .up:      arrow = "up"
            case .unknown: arrow = "--"
            }
            let grade: String
            switch last.grade {
            case .pass:    grade = "pass"
            case .fail:    grade = "fail"
            case .unknown: grade = "?"
            }
            toneLabel = "\(arrow) \(grade) R2=\(String(format: "%.2f", last.confidence))"
        }
    }

    func toggle() {
        isVisible.toggle()
    }

    func reset() {
        dbLabel = "--"
        snapshotHzLabel = "--"
        bufferHzLabel = "--"
        wpmLabel = "--"
        toneLabel = "no phrases"
        lastPhrases = []
    }
}
#endif
