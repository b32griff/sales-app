import Foundation
import Speech

/// Debounced cadence coaching output. Carried in snapshot to MainActor.
struct CadenceCoachState: Equatable {
    enum Status: Equatable {
        case inRange, tooFast, tooSlow
    }
    var status: Status = .inRange
    var message: String? = nil
    var isReady: Bool = false
}

/// Estimates speaking pace (words per minute) using two approaches:
/// 1. Primary: On-device SFSpeechRecognizer for actual word counting
/// 2. Fallback: Energy-based syllable peak detection (always running in parallel)
///
/// Readiness timeline:
///   t=0  → session start, both estimators begin accumulating
///   t=3s → fallback ready if syllable peaks detected, shows ~WPM
///   t=6s → speech recognition converges if available, shows real WPM
///   If recognition fails → stays on fallback seamlessly
///
/// Also tracks articulation clarity via speech recognition confidence.
/// Per Hormozi: 135–185 WPM is the sweet spot.
final class CadenceAnalyzer {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var currentWPM: Double = 0
    private(set) var wordCount: Int = 0
    private var sessionStartTime: Date?
    private var lastWordCount: Int = 0
    private var lastCheckTime: Date?

    // EMA smoothing for WPM — prevents jumpy display.
    private let emaAlpha: Double = 0.3
    private var emaWPM: Double = 0
    private var emaInitialized = false

    // Separate EMA for fallback so the two estimators don't pollute each other
    private var fallbackEmaWPM: Double = 0
    private var fallbackEmaInitialized = false

    // Data gates
    static let fallbackReadySeconds: Double = 3.0
    static let fallbackMinPeaks: Int = 2
    static let recognitionReadySeconds: Double = 3.0
    static let recognitionMinWords: Int = 3

    // Floor clamp: no human speaks below 40 WPM while actively talking.
    private static let wpmFloor: Double = 40.0

    /// Whether the cadence estimate has enough data to be trustworthy.
    private(set) var ready = false

    /// True when showing fallback (syllable-based) WPM rather than speech recognition.
    private(set) var isApproximate = true

    /// Readiness sub-states (for diagnostics and testing)
    private(set) var fallbackReady = false
    private(set) var recognitionReady = false

    // Coaching state machine (timestamp-based, no Timers)
    private(set) var coachState = CadenceCoachState()
    private var targetWPMMin: Double = 135
    private var targetWPMMax: Double = 185
    private var coachOutOfRangeStart: CFTimeInterval = 0
    private var coachOutOfRangeDir: CadenceCoachState.Status = .inRange
    private var coachInRangeStart: CFTimeInterval = 0
    private var coachActiveStart: CFTimeInterval = 0
    private var coachLastEndTime: CFTimeInterval = 0

    // Syllable-based fallback (always running, even when speech recognition is active)
    private var syllablePeakCount: Int = 0
    private var lastEnergy: Float = 0
    private var isRising = false
    private let syllableThreshold: Float = 0.02
    private var lastSyllableCheckTime: Double = 0
    private var lastSyllableCount: Int = 0
    private var fallbackStartTimestamp: Double = 0
    private var fallbackWPM: Double = 0

    // Articulation tracking via speech recognition confidence.
    private var confidenceSum: Float = 0
    private var confidenceCount: Int = 0
    private var lastSegmentIndex: Int = 0
    private(set) var articulationScore: Double = 0  // 0...1

    /// Whether speech recognition is available and authorized.
    private(set) var usingSpeechRecognition = false

    /// Set by ProcessingContext so speech recognition results dispatch to the correct queue.
    var processingQueue: DispatchQueue?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.supportsOnDeviceRecognition = true
    }

    /// Start speech recognition for cadence tracking.
    func startRecognition(audioEngine: AVAudioEngine) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            usingSpeechRecognition = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        recognitionRequest = request
        sessionStartTime = Date()
        lastCheckTime = Date()
        usingSpeechRecognition = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            let q = self.processingQueue ?? DispatchQueue.main
            q.async { [weak self] in
                guard let self else { return }

                if let error {
                    print("[ToneCoach] Speech recognition error: \(error.localizedDescription)")
                    self.usingSpeechRecognition = false
                    // Don't clear ready — fallback keeps running
                    return
                }

                guard let result else { return }
                let segments = result.bestTranscription.segments
                self.wordCount = segments.count
                self.updateRecognitionWPM()

                // Track articulation from segment confidence
                if segments.count > self.lastSegmentIndex {
                    for i in self.lastSegmentIndex..<segments.count {
                        let c = segments[i].confidence
                        if c > 0 {
                            self.confidenceSum += c
                            self.confidenceCount += 1
                        }
                    }
                    self.lastSegmentIndex = segments.count
                    self.updateArticulation()
                }
            }
        }

        _ = format
        print("[ToneCoach] Speech recognition started")
    }

    /// Append an audio buffer to the speech recognizer.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    // MARK: - Speech Recognition WPM

    /// Update WPM from speech recognition using EMA over rolling windows.
    private func updateRecognitionWPM() {
        guard let start = sessionStartTime else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)

        guard elapsed > 1 else { return }

        // Check if recognition has enough data
        let gated = elapsed >= Self.recognitionReadySeconds && wordCount >= Self.recognitionMinWords
        recognitionReady = gated

        // Compute rolling WPM every 2 seconds
        if let lastCheck = lastCheckTime {
            let windowElapsed = now.timeIntervalSince(lastCheck)
            if windowElapsed >= 2 {
                let recentWords = wordCount - lastWordCount
                let instantWPM = Double(recentWords) / windowElapsed * 60
                let sample = recentWords > 0 ? max(instantWPM, Self.wpmFloor) : instantWPM

                if !emaInitialized {
                    emaWPM = sample
                    emaInitialized = true
                } else {
                    emaWPM = emaAlpha * sample + (1 - emaAlpha) * emaWPM
                }

                lastWordCount = wordCount
                lastCheckTime = now
            }
        }

        // Seed before first rolling window
        if !emaInitialized && wordCount > 0 {
            let cumulative = Double(wordCount) / elapsed * 60
            emaWPM = max(cumulative, Self.wpmFloor)
            // Don't set emaInitialized — let the rolling window take over
        }

        // Select best source and update outputs
        selectBestSource()
    }

    // MARK: - Syllable-based Fallback (always running)

    /// Process energy for syllable peak detection. Called on EVERY buffer,
    /// regardless of whether speech recognition is active.
    func processSyllableFallback(rms: Float, timestamp: Double) {
        if rms > lastEnergy && rms > syllableThreshold {
            isRising = true
        } else if isRising && rms < lastEnergy {
            syllablePeakCount += 1
            isRising = false
        }
        lastEnergy = rms

        if fallbackStartTimestamp == 0 { fallbackStartTimestamp = timestamp }
        let elapsed = timestamp - fallbackStartTimestamp
        guard elapsed > 1 else { return }

        // Fallback readiness: just need time + some peaks
        let gated = elapsed >= Self.fallbackReadySeconds && syllablePeakCount >= Self.fallbackMinPeaks
        fallbackReady = gated

        // Rolling EMA every 2 seconds
        if lastSyllableCheckTime > 0 {
            let windowElapsed = timestamp - lastSyllableCheckTime
            if windowElapsed >= 2 {
                let recentPeaks = syllablePeakCount - lastSyllableCount
                // ~0.6 words per syllable peak is a reasonable approximation
                let instantWPM = Double(recentPeaks) * 0.6 / windowElapsed * 60
                let sample = recentPeaks > 0 ? max(instantWPM, Self.wpmFloor) : instantWPM

                if !fallbackEmaInitialized {
                    fallbackEmaWPM = sample
                    fallbackEmaInitialized = true
                } else {
                    fallbackEmaWPM = emaAlpha * sample + (1 - emaAlpha) * fallbackEmaWPM
                }

                fallbackWPM = gated ? fallbackEmaWPM : 0
                lastSyllableCount = syllablePeakCount
                lastSyllableCheckTime = timestamp
            }
        } else {
            lastSyllableCheckTime = timestamp
            lastSyllableCount = syllablePeakCount
        }

        // Seed before first rolling window
        if !fallbackEmaInitialized && syllablePeakCount > 0 {
            let cumulative = Double(syllablePeakCount) * 0.6 / elapsed * 60
            fallbackWPM = gated ? max(cumulative, Self.wpmFloor) : 0
        }

        // Select best source and update outputs
        selectBestSource()
    }

    // MARK: - Source Selection

    /// Choose between recognition and fallback WPM, update public outputs.
    private func selectBestSource() {
        if recognitionReady && emaWPM > 0 {
            // Speech recognition has converged — use it
            currentWPM = emaWPM
            isApproximate = false
            ready = true
        } else if fallbackReady && fallbackWPM > 0 {
            // Fallback has data — show approximate WPM
            currentWPM = fallbackWPM
            isApproximate = true
            ready = true
        } else {
            // Neither source ready yet
            currentWPM = 0
            isApproximate = true
            ready = false
        }
    }

    /// Update articulation score from running average. O(1).
    private func updateArticulation() {
        guard confidenceCount > 0 else { return }
        articulationScore = Double(confidenceSum / Float(confidenceCount))
    }

    /// Status relative to target WPM range.
    func status(min: Double, max: Double) -> MeterStatus {
        if currentWPM < min * 0.85 { return .bad }
        if currentWPM > max * 1.15 { return .bad }
        if currentWPM < min || currentWPM > max { return .warning }
        return .good
    }

    /// Articulation status — based on speech recognition confidence.
    func articulationStatus() -> MeterStatus {
        if !usingSpeechRecognition || confidenceCount == 0 { return .idle }
        if articulationScore >= 0.7 { return .good }
        if articulationScore >= 0.4 { return .warning }
        return .bad
    }

    // MARK: - Coaching Target Range

    func setTargetRange(min: Double, max: Double) {
        targetWPMMin = min
        targetWPMMax = max
    }

    // MARK: - Coaching State Machine

    /// Tick coaching at buffer rate. Reads current WPM/ready and advances
    /// the timestamp-based debounce/cooldown state machine.
    func tickCoaching(timestamp: CFTimeInterval) {
        evaluateCoaching(wpm: currentWPM, isReady: ready, timestamp: timestamp)
    }

    /// Evaluate coaching rules. Public for testing with controlled inputs.
    ///
    /// State machine:
    /// - tooFast triggers after WPM > max for 1.0s
    /// - tooSlow triggers after WPM < min for 1.5s (user must be speaking)
    /// - Once triggered, holds for 3.0s then auto-resets
    /// - Early clear: if inRange for 2.0s during hold, reset immediately
    /// - Cooldown: 3.0s after reset before re-triggering
    func evaluateCoaching(wpm: Double, isReady: Bool, timestamp: CFTimeInterval) {
        guard isReady, wpm > 10 else {
            if coachState.status != .inRange || coachState.isReady {
                coachState = CadenceCoachState()
            }
            coachOutOfRangeStart = 0
            coachOutOfRangeDir = .inRange
            coachInRangeStart = 0
            return
        }

        let rawStatus: CadenceCoachState.Status
        if wpm > targetWPMMax {
            rawStatus = .tooFast
        } else if wpm < targetWPMMin {
            rawStatus = .tooSlow
        } else {
            rawStatus = .inRange
        }

        // ── Currently showing coaching ──
        if coachState.status != .inRange {
            // Auto-reset after 3s hold
            if timestamp - coachActiveStart >= 3.0 {
                resetCoaching(timestamp: timestamp)
                return
            }
            // Early clear: inRange for 2s
            if rawStatus == .inRange {
                if coachInRangeStart == 0 { coachInRangeStart = timestamp }
                if timestamp - coachInRangeStart >= 2.0 {
                    resetCoaching(timestamp: timestamp)
                    return
                }
            } else {
                coachInRangeStart = 0
            }
            return
        }

        // ── Currently inRange ──
        if rawStatus == .inRange {
            coachOutOfRangeStart = 0
            coachOutOfRangeDir = .inRange
            coachState.isReady = true
            return
        }

        // Cooldown: 3s after last coaching ended
        if coachLastEndTime > 0, timestamp - coachLastEndTime < 3.0 {
            coachState.isReady = true
            return
        }

        // Debounce: track direction
        if rawStatus != coachOutOfRangeDir {
            coachOutOfRangeStart = timestamp
            coachOutOfRangeDir = rawStatus
        }

        let threshold: TimeInterval = rawStatus == .tooFast ? 1.0 : 1.5
        if timestamp - coachOutOfRangeStart >= threshold {
            let message = rawStatus == .tooFast ? "Slow down" : "Pick up the pace"
            coachState = CadenceCoachState(status: rawStatus, message: message, isReady: true)
            coachActiveStart = timestamp
            coachOutOfRangeStart = 0
            coachOutOfRangeDir = .inRange
            coachInRangeStart = 0
        } else {
            coachState.isReady = true
        }
    }

    private func resetCoaching(timestamp: CFTimeInterval) {
        coachState = CadenceCoachState(status: .inRange, message: nil, isReady: true)
        coachLastEndTime = timestamp
        coachOutOfRangeStart = 0
        coachOutOfRangeDir = .inRange
        coachInRangeStart = 0
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    func reset() {
        stop()
        currentWPM = 0
        wordCount = 0
        syllablePeakCount = 0
        lastEnergy = 0
        isRising = false
        sessionStartTime = nil
        lastCheckTime = nil
        lastWordCount = 0
        confidenceSum = 0
        confidenceCount = 0
        lastSegmentIndex = 0
        articulationScore = 0
        emaWPM = 0
        emaInitialized = false
        fallbackEmaWPM = 0
        fallbackEmaInitialized = false
        fallbackWPM = 0
        fallbackReady = false
        recognitionReady = false
        isApproximate = true
        ready = false
        coachState = CadenceCoachState()
        coachOutOfRangeStart = 0
        coachOutOfRangeDir = .inRange
        coachInRangeStart = 0
        coachActiveStart = 0
        coachLastEndTime = 0
        lastSyllableCheckTime = 0
        lastSyllableCount = 0
        fallbackStartTimestamp = 0
    }

    func markSessionStart() {
        sessionStartTime = Date()
        lastCheckTime = Date()
    }
}
