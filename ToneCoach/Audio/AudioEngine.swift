import Foundation
import AVFoundation
import Combine
import os

/// Central audio engine.
///
/// Thread safety model:
/// - ProcessingContext (analyzers, accumulators, ring buffer) → processingQueue ONLY
/// - @Published state → MainActor ONLY (enforced by @MainActor)
/// - start/stop/reset → MainActor
///
/// Pipeline architecture (single-hop):
/// DispatchSourceTimer fires on processingQueue → builds snapshot (zero dispatch needed,
/// already on queue) → single Task { @MainActor } hop → emitTick → onUITick callback.
/// ONE context switch per tick instead of two.
@MainActor
final class AudioEngine: ObservableObject {
    private var engine: AVAudioEngine?
    private let bufferSize: AVAudioFrameCount = 2048

    // ── Background processing — all analysis in ProcessingContext ──
    private let processing = ProcessingContext()

    // Settings (UserDefaults-backed, thread-safe reads)
    private let settings: UserSettings

    // UI snapshot source (fires on processing queue, not main RunLoop)
    private var snapshotSource: DispatchSourceTimer?
    private let snapshotInterval: TimeInterval = 0.08  // ~12 Hz

    // ── Published state (MainActor, LOW-FREQUENCY ONLY) ──
    @Published var isRunning = false
    @Published var lastError: String?

    // ── UITick callback (replaces high-frequency @Published) ──
    /// Set by LiveCoachBinder. Called once per snapshot tick on MainActor.
    var onUITick: ((UITick) -> Void)?

    /// Single struct emitted per snapshot tick. All UI-relevant data in one shot.
    struct UITick {
        let db: Double
        let wpm: Double
        let cadenceReady: Bool
        let cadenceIsApproximate: Bool
        let cadenceCoachState: CadenceCoachState
        let dbHistory: [Double]?  // nil if unchanged since last tick
        let dbGeneration: UInt64
        let newPhrases: [PhraseResult]
        let latestPrompt: CoachingPrompt?
        #if DEBUG
        let snapshotRate: Double
        let bufferRate: Double
        #endif
    }

    struct PhraseResult: Identifiable {
        let id = UUID()
        let endingTone: PhraseEndingTone
        let grade: PhraseGrade
        let confidence: Double
        let unknownReason: UnknownReason?
        let debugOverlay: String
    }

    private static let maxPhraseResults = 10

    // Prompt cooldown (MainActor only — checked in emitTick)
    private var promptCooldown: CFTimeInterval = 0

    // Cached on MainActor so elapsedSeconds doesn't need queue.sync
    private var sessionStartTime: Date?

    // ── os_signpost for Instruments profiling ──
    nonisolated static let signpostLog = OSLog(subsystem: "com.tonecoach.audio", category: .pointsOfInterest)

    #if DEBUG
    /// Snapshot publishes per second (MainActor, measured over 2s window).
    private var snapshotTimestamps: [CFTimeInterval] = []
    private var debugSnapshotRate: Double = 0

    // Periodic log (every 5s)
    private var lastDebugLogTime: CFTimeInterval = 0
    private var tickCount: Int = 0
    #endif

    init(settings: UserSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Start / Stop

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw NSError(domain: "ToneCoach", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone not available"])
        }

        let ctx = processing
        let desiredTone = settings.desiredEndingTone
        let dbMin = settings.targetDBMin
        let dbMax = settings.targetDBMax
        let wpmMin = settings.targetWPMMin
        let wpmMax = settings.targetWPMMax

        // Reset processing state on its queue before starting
        let now = Date()
        sessionStartTime = now
        ctx.queue.sync {
            ctx.reset()
            ctx.pitchDetector.updateSampleRate(format.sampleRate)
            ctx.volumeAnalyzer.setTargetRange(min: dbMin, max: dbMax)
            ctx.cadenceAnalyzer.setTargetRange(min: wpmMin, max: wpmMax)
            ctx.startTime = now
            ctx.desiredEndingTone = desiredTone
        }

        ctx.queue.sync {
            ctx.cadenceAnalyzer.markSessionStart()
            ctx.cadenceAnalyzer.startRecognition(audioEngine: engine)
        }

        // Audio tap → processingQueue (never main thread)
        let signpostLog = Self.signpostLog
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [ctx] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            let timestamp = CACurrentMediaTime()

            ctx.queue.async {
                os_signpost(.begin, log: signpostLog, name: "processBuffer")
                ctx.processBuffer(samples: samples, timestamp: timestamp)
                os_signpost(.end, log: signpostLog, name: "processBuffer")
            }

            // Feed speech recognizer (Apple's API is thread-safe for append)
            ctx.cadenceAnalyzer.appendBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        isRunning = true
        lastError = nil

        // ── Snapshot timer on processing queue (single-hop architecture) ──
        // Timer fires ON the processing queue → builds snapshot directly (no dispatch)
        // → single Task { @MainActor } hop to emit UITick.
        let source = DispatchSource.makeTimerSource(queue: ctx.queue)
        source.schedule(deadline: .now() + snapshotInterval,
                        repeating: snapshotInterval,
                        leeway: .milliseconds(5))
        source.setEventHandler { [weak self, ctx, signpostLog] in
            os_signpost(.begin, log: signpostLog, name: "snapshot")

            // Already on processing queue — read state directly, zero dispatch
            let gen = ctx.dbRingBuffer.generation
            let lastGen = ctx.lastSentDBGeneration
            let history: [Double]?
            if gen != lastGen {
                history = ctx.dbRingBuffer.toArray()
                ctx.lastSentDBGeneration = gen
            } else {
                history = nil
            }

            let snapshot = InternalSnapshot(
                db: ctx.latestDB,
                wpm: ctx.cadenceAnalyzer.currentWPM,
                cadenceReady: ctx.cadenceAnalyzer.ready,
                cadenceIsApproximate: ctx.cadenceAnalyzer.isApproximate,
                cadenceCoachState: ctx.cadenceAnalyzer.coachState,
                dbGeneration: gen,
                dbHistory: history,
                pendingPhrases: ctx.drainPendingPhrases(),
                timestamp: CACurrentMediaTime(),
                bufferRate: ctx.debugBufferRate
            )

            os_signpost(.end, log: signpostLog, name: "snapshot")

            // Single hop to MainActor (the ONLY context switch per tick)
            Task { @MainActor [weak self] in
                self?.emitTick(from: snapshot)
            }
        }
        source.resume()
        snapshotSource = source

        #if DEBUG
        lastDebugLogTime = CACurrentMediaTime()
        tickCount = 0
        #endif

        print("[ToneCoach] Audio engine started. Format: \(format.sampleRate)Hz, \(format.channelCount)ch")
    }

    func stop() {
        snapshotSource?.cancel()
        snapshotSource = nil

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false

        // Stop cadence recognizer on processingQueue, then take final snapshot.
        // queue.sync is OK here — one-time call, not the hot path.
        let ctx = processing
        ctx.queue.sync { ctx.cadenceAnalyzer.stop() }
        let snapshot = ctx.queue.sync {
            let gen = ctx.dbRingBuffer.generation
            let history: [Double]?
            if gen != ctx.lastSentDBGeneration {
                history = ctx.dbRingBuffer.toArray()
                ctx.lastSentDBGeneration = gen
            } else {
                history = nil
            }
            return InternalSnapshot(
                db: ctx.latestDB,
                wpm: ctx.cadenceAnalyzer.currentWPM,
                cadenceReady: ctx.cadenceAnalyzer.ready,
                cadenceIsApproximate: ctx.cadenceAnalyzer.isApproximate,
                cadenceCoachState: ctx.cadenceAnalyzer.coachState,
                dbGeneration: gen,
                dbHistory: history,
                pendingPhrases: ctx.drainPendingPhrases(),
                timestamp: CACurrentMediaTime(),
                bufferRate: ctx.debugBufferRate
            )
        }
        emitTick(from: snapshot)
    }

    var elapsedSeconds: Double {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func buildSession() -> Session {
        let ctx = processing
        return ctx.queue.sync {
            let duration: Double
            if let start = ctx.startTime {
                duration = Date().timeIntervalSince(start)
            } else {
                duration = 0
            }
            return Session(
                durationSeconds: duration,
                averageDB: ctx.volumeAnalyzer.averageDB,
                dbInRangePercent: ctx.volumeAnalyzer.inRangePercent(
                    min: settings.targetDBMin, max: settings.targetDBMax
                ),
                averageWPM: ctx.cadenceAnalyzer.currentWPM,
                pauseRatio: ctx.phraseSegmenter.pauseRatio(totalDuration: duration),
                downTonePercent: ctx.downToneClassifier.downTonePercent,
                upTonePercent: ctx.downToneClassifier.upTonePercent,
                phraseCount: ctx.phraseSegmenter.phraseCount,
                articulationScore: ctx.cadenceAnalyzer.articulationScore * 100,
                averagePauseSec: ctx.phraseSegmenter.averagePauseDuration,
                powerPauseCount: ctx.phraseSegmenter.powerPauseCount
            )
        }
    }

    func resetAll() {
        snapshotSource?.cancel()
        snapshotSource = nil

        let ctx = processing
        ctx.queue.sync {
            ctx.reset()
            ctx.cadenceAnalyzer.reset()
        }

        lastError = nil
        promptCooldown = 0
        sessionStartTime = nil

        #if DEBUG
        snapshotTimestamps.removeAll()
        debugSnapshotRate = 0
        lastDebugLogTime = 0
        tickCount = 0
        #endif
    }

    // MARK: - Emit UITick (MainActor only, single entry point)

    /// Convert internal snapshot to UITick and emit via callback. Called on MainActor only.
    private func emitTick(from snapshot: InternalSnapshot) {
        os_signpost(.begin, log: Self.signpostLog, name: "emitTick")

        // Compute prompt (MainActor, using snapshot values)
        let prompt = computePrompt(from: snapshot)

        #if DEBUG
        // Measure snapshot rate
        let now = CACurrentMediaTime()
        snapshotTimestamps.append(now)
        let cutoff = now - 2.0
        while let first = snapshotTimestamps.first, first < cutoff {
            snapshotTimestamps.removeFirst()
        }
        debugSnapshotRate = Double(snapshotTimestamps.count) / 2.0

        tickCount += 1
        if now - lastDebugLogTime >= 5.0 {
            let elapsed = now - lastDebugLogTime
            let tickHz = Double(tickCount) / elapsed
            print("[ToneCoach] UITick: \(String(format: "%.1f", tickHz)) Hz | buffers: \(String(format: "%.0f", snapshot.bufferRate))/s | cadenceReady: \(snapshot.cadenceReady) | wpm: \(String(format: "%.0f", snapshot.wpm)) | dbGen: \(snapshot.dbGeneration) | histIncluded: \(snapshot.dbHistory != nil)")
            tickCount = 0
            lastDebugLogTime = now
        }

        let tick = UITick(
            db: snapshot.db,
            wpm: snapshot.wpm,
            cadenceReady: snapshot.cadenceReady,
            cadenceIsApproximate: snapshot.cadenceIsApproximate,
            cadenceCoachState: snapshot.cadenceCoachState,
            dbHistory: snapshot.dbHistory,
            dbGeneration: snapshot.dbGeneration,
            newPhrases: snapshot.pendingPhrases,
            latestPrompt: prompt,
            snapshotRate: debugSnapshotRate,
            bufferRate: snapshot.bufferRate
        )
        #else
        let tick = UITick(
            db: snapshot.db,
            wpm: snapshot.wpm,
            cadenceReady: snapshot.cadenceReady,
            cadenceIsApproximate: snapshot.cadenceIsApproximate,
            cadenceCoachState: snapshot.cadenceCoachState,
            dbHistory: snapshot.dbHistory,
            dbGeneration: snapshot.dbGeneration,
            newPhrases: snapshot.pendingPhrases,
            latestPrompt: prompt
        )
        #endif

        onUITick?(tick)

        os_signpost(.end, log: Self.signpostLog, name: "emitTick")
    }

    // MARK: - Prompt computation (MainActor)

    private func computePrompt(from snapshot: InternalSnapshot) -> CoachingPrompt? {
        let now = snapshot.timestamp
        guard now - promptCooldown > 4 else { return nil }

        // Volume prompts
        let db = snapshot.db
        let dbMin = settings.targetDBMin
        let dbMax = settings.targetDBMax
        if db < dbMin {
            promptCooldown = now
            return .tooQuiet()
        } else if db > dbMax {
            promptCooldown = now
            return .tooLoud()
        }

        // Cadence prompts
        let wpm = snapshot.wpm
        let wpmMin = settings.targetWPMMin
        let wpmMax = settings.targetWPMMax
        if wpm > 10 {
            if wpm > wpmMax * 1.15 {
                promptCooldown = now
                return .tooFast()
            } else if wpm < wpmMin * 0.85 {
                promptCooldown = now
                return .tooSlow()
            }
        }

        // Tone prompts
        if let lastPhrase = snapshot.pendingPhrases.last {
            switch lastPhrase.grade {
            case .pass:
                promptCooldown = now
                return .downToneGood()
            case .fail:
                promptCooldown = now
                return .upToneDetected()
            case .unknown:
                break
            }
        }

        return nil
    }
}

// MARK: - InternalSnapshot (value type for safe transfer between queues)

private struct InternalSnapshot {
    let db: Double
    let wpm: Double
    let cadenceReady: Bool
    let cadenceIsApproximate: Bool
    let cadenceCoachState: CadenceCoachState
    let dbGeneration: UInt64
    let dbHistory: [Double]?  // nil if unchanged since last snapshot
    let pendingPhrases: [AudioEngine.PhraseResult]
    let timestamp: CFTimeInterval
    let bufferRate: Double
}

// MARK: - ProcessingContext (background queue only, NOT actor-isolated)

/// Holds all audio analysis state. Accessed exclusively on its serial queue.
/// Snapshot timer also fires on this queue — zero dispatch needed for reads.
final class ProcessingContext: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.tonecoach.audio", qos: .userInteractive)

    // Analyzers
    let volumeAnalyzer = VolumeAnalyzer()
    let pitchDetector = PitchDetector()
    let cadenceAnalyzer = CadenceAnalyzer()
    let phraseSegmenter = PhraseSegmenter()
    let downToneClassifier: DownToneClassifier

    // Pitch accumulation — YIN needs at least 2x maxLag samples
    var pitchAccumulator: [Float] = {
        var a = [Float]()
        a.reserveCapacity(3200)
        return a
    }()
    let pitchBufferTarget = 3200

    // dB ring buffer
    var dbRingBuffer = RingBuffer<Double>(capacity: 150, defaultValue: -80)

    // Latest processed dB value
    var latestDB: Double = -80

    // Timing
    var startTime: Date?

    // Desired tone for grading (set from settings before start)
    var desiredEndingTone: PhraseEndingTone = .down

    // Phrase results pending delivery to MainActor
    private var pendingPhrases: [AudioEngine.PhraseResult] = []

    // Generation tracking for dbHistory gating (processing queue only)
    var lastSentDBGeneration: UInt64 = 0

    // Finalization delay: wait this long after phrase-end before classifying.
    // Allows trailing pitch data to settle (YIN processes in chunks).
    static let finalizationDelay: TimeInterval = 0.3

    // Tone cooldown — prevents double-triggering when PhraseSegmenter fires
    // rapid phrase-end events in quick succession.
    private var lastToneResultTime: CFTimeInterval = 0
    static let toneResultCooldown: CFTimeInterval = 1.5

    // Buffer rate tracking — always available (zero cost, single Double).
    // Only updated in DEBUG builds to avoid timestamp array overhead in release.
    var debugBufferRate: Double = 0
    #if DEBUG
    private var bufferTimestamps: [CFTimeInterval] = []
    #endif

    init() {
        self.downToneClassifier = DownToneClassifier(pitchDetector: pitchDetector)

        // Give CadenceAnalyzer a reference to our queue for thread-safe callbacks
        cadenceAnalyzer.processingQueue = queue

        // Wire phrase segmenter → tone classifier (runs on queue).
        // Uses a finalization delay so trailing pitch data can settle before classifying.
        // All gating (confidence, voiced fraction, etc.) is inside the classifier.
        phraseSegmenter.onPhraseEnd = { [weak self] phraseStart, endTime in
            guard let self else { return }

            // Cooldown: skip if last tone result was too recent
            let now = CACurrentMediaTime()
            guard now - self.lastToneResultTime >= Self.toneResultCooldown else { return }

            let phraseDuration = endTime - phraseStart

            // Schedule classification after finalization delay
            self.queue.asyncAfter(deadline: .now() + Self.finalizationDelay) { [weak self] in
                guard let self else { return }

                // Re-check cooldown after delay (another phrase may have fired)
                let postDelayNow = CACurrentMediaTime()
                guard postDelayNow - self.lastToneResultTime >= Self.toneResultCooldown else { return }
                self.lastToneResultTime = postDelayNow

                let verdict = self.downToneClassifier.analyzePhrase(
                    phraseEndTime: endTime,
                    phraseDuration: phraseDuration
                )

                // Deduplicates never reach the UI
                if verdict.reason == .deduplicate { return }

                // Map verdict → PhraseResult for UI consumption
                let endingTone: PhraseEndingTone
                if verdict.isUnknown {
                    endingTone = .unknown
                } else {
                    switch verdict.direction {
                    case .downward: endingTone = .down
                    case .upward:   endingTone = .up
                    case .flat:     endingTone = .unknown
                    }
                }

                let grade: PhraseGrade
                if endingTone == .unknown {
                    grade = .unknown
                } else if endingTone == self.desiredEndingTone {
                    grade = .pass
                } else {
                    grade = .fail
                }

                self.pendingPhrases.append(AudioEngine.PhraseResult(
                    endingTone: endingTone,
                    grade: grade,
                    confidence: verdict.confidence,
                    unknownReason: verdict.reason,
                    debugOverlay: verdict.debugOverlay
                ))
            }
        }
    }

    /// Drain pending phrase results (called on processing queue, result sent to MainActor).
    func drainPendingPhrases() -> [AudioEngine.PhraseResult] {
        let results = pendingPhrases
        pendingPhrases.removeAll()
        return results
    }

    /// Process a single audio buffer. Called ONLY on queue.
    func processBuffer(samples: [Float], timestamp: CFTimeInterval) {
        #if DEBUG
        do {
            let now = CACurrentMediaTime()
            bufferTimestamps.append(now)
            let cutoff = now - 2.0
            while let first = bufferTimestamps.first, first < cutoff {
                bufferTimestamps.removeFirst()
            }
            debugBufferRate = Double(bufferTimestamps.count) / 2.0
        }
        #endif

        // 1. Volume
        let db = volumeAnalyzer.process(samples: samples)
        dbRingBuffer.append(db)
        latestDB = db

        // 2. Phrase segmentation
        let rms = computeRMS(samples)
        phraseSegmenter.process(rms: rms, timestamp: timestamp)

        // 3. Cadence — always run syllable fallback (parallel to speech recognition)
        cadenceAnalyzer.processSyllableFallback(rms: rms, timestamp: timestamp)

        // 4. Pitch detection — accumulate for YIN
        pitchAccumulator.append(contentsOf: samples)
        if pitchAccumulator.count >= pitchBufferTarget {
            _ = pitchDetector.detectPitch(samples: pitchAccumulator, timestamp: timestamp)
            pitchAccumulator.removeAll(keepingCapacity: true)
        }

        // 5. Cadence coaching — tick state machine at buffer rate
        cadenceAnalyzer.tickCoaching(timestamp: timestamp)
    }

    func reset() {
        volumeAnalyzer.reset()
        pitchDetector.reset()
        phraseSegmenter.reset()
        downToneClassifier.reset()
        pitchAccumulator.removeAll()
        dbRingBuffer.removeAll()
        latestDB = -80
        startTime = nil
        pendingPhrases.removeAll()
        lastToneResultTime = 0
        lastSentDBGeneration = 0
        debugBufferRate = 0
        #if DEBUG
        bufferTimestamps.removeAll()
        #endif
    }
}
