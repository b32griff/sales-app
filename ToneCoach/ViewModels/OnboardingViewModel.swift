import Foundation
import AVFoundation
import Speech

/// Manages onboarding flow: permission requests and voice calibration.
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case micPermission
        case speechPermission
        case calibration
        case done
    }

    @Published var currentStep: Step = .welcome
    @Published var micGranted = false
    @Published var speechGranted = false
    @Published var isCalibrating = false
    @Published var calibrationProgress: Double = 0
    @Published var calibrationDB: Double = -20

    private var calibrationEngine: AVAudioEngine?
    private var calibrationReadings: [Double] = []
    private let settings = UserSettings.shared

    func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                self?.micGranted = granted
                if granted {
                    self?.currentStep = .speechPermission
                }
            }
        }
    }

    func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.speechGranted = (status == .authorized)
                self?.currentStep = .calibration
            }
        }
    }

    /// Run a 5-second calibration to establish the user's baseline volume.
    func startCalibration() {
        guard !isCalibrating else { return }
        isCalibrating = true
        calibrationReadings.removeAll()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let samples = self.extractSamples(from: buffer)
                let rms = computeRMS(samples)
                let db = Double(rmsToDecibels(rms))

                Task { @MainActor in
                    self.calibrationReadings.append(db)
                    self.calibrationDB = db
                }
            }

            engine.prepare()
            try engine.start()
            calibrationEngine = engine

            // Stop after 5 seconds
            Task {
                for i in 1...50 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    calibrationProgress = Double(i) / 50.0
                }
                finishCalibration()
            }
        } catch {
            isCalibrating = false
        }
    }

    private func finishCalibration() {
        calibrationEngine?.inputNode.removeTap(onBus: 0)
        calibrationEngine?.stop()
        calibrationEngine = nil

        if !calibrationReadings.isEmpty {
            let avg = calibrationReadings.reduce(0, +) / Double(calibrationReadings.count)
            calibrationDB = avg
            settings.calibratedDBBaseline = avg
            // Set target range centered around their baseline
            settings.targetDBMin = avg - 7.5
            settings.targetDBMax = avg + 7.5
        }

        isCalibrating = false
        currentStep = .done
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }
}
