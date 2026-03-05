import Foundation
import SwiftData
import AVFoundation

/// Manages practice session lifecycle: start, stop, save, summary.
@MainActor
final class PracticeViewModel: ObservableObject {
    enum State {
        case idle
        case recording
        case summary
    }

    @Published var state: State = .idle
    @Published var elapsedTime: String = "0:00"
    @Published var completedSession: Session?
    @Published var previousSession: Session?
    @Published var errorMessage: String?

    let audioEngine = AudioEngine()
    let binder: LiveCoachBinder
    private var timer: Timer?

    init() {
        self.binder = LiveCoachBinder(audioEngine: audioEngine)
    }

    func startSession() {
        print("[ToneCoach] Start tapped, state=\(state)")
        errorMessage = nil
        audioEngine.resetAll()
        binder.resetState()

        // Check mic permission
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            errorMessage = "Microphone denied. Enable in Settings."
            print("[ToneCoach] Mic denied")
            return
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.doStart()
                    } else {
                        self?.errorMessage = "Microphone access needed."
                    }
                }
            }
            return
        case .granted:
            doStart()
        @unknown default:
            doStart()
        }
    }

    private func doStart() {
        do {
            try audioEngine.start()
            state = .recording
            elapsedTime = "0:00"
            startTimer()
            print("[ToneCoach] Recording started")
        } catch {
            errorMessage = "Audio error: \(error.localizedDescription)"
            state = .idle
            print("[ToneCoach] Start failed: \(error)")
        }
    }

    func stopSession(context: ModelContext) {
        print("[ToneCoach] Stop tapped")
        timer?.invalidate()
        timer = nil
        binder.invalidateTimers()
        audioEngine.stop()

        // Fetch previous session before saving the new one (for delta display)
        let allSessions = SessionStore.fetchAll(in: context)
        previousSession = allSessions.first

        let session = audioEngine.buildSession()
        SessionStore.save(session, in: context)
        completedSession = session
        state = .summary
    }

    func resetToIdle() {
        state = .idle
        completedSession = nil
        errorMessage = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let secs = Int(self.audioEngine.elapsedSeconds)
                self.elapsedTime = String(format: "%d:%02d", secs / 60, secs % 60)
            }
        }
    }
}
