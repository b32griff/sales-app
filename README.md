# ToneCoach - Speak With Authority

**iOS app that coaches users to speak with more authority through real-time feedback on volume, cadence, and intonation.**

---

## A) Product Spec

### Target User
Professionals (salespeople, executives, public speakers, interviewees) who want to sound more confident and authoritative when speaking. Secondary: content creators, podcast hosts.

### Jobs To Be Done
1. "Help me stop ending sentences like I'm asking a question" (down-tone coaching)
2. "Help me project my voice consistently without yelling" (volume coaching)
3. "Help me pace myself - I speak too fast when nervous" (cadence coaching)
4. "Show me I'm improving over time" (progress tracking)

### Core User Flows

**Flow 1: First Launch**
Open app -> Microphone permission -> Quick calibration (speak normally for 5s) -> See Live Coach

**Flow 2: Quick Practice**
Open app -> Start practice session -> Speak for 1-5 min with real-time cues -> End session -> View summary card -> Optionally share

**Flow 3: Progress Check**
Open app -> History tab -> See trend charts for volume/cadence/down-tone over time

**Flow 4: UGC Sharing**
Open app -> UGC mode -> Read 20s guided script -> Get result card -> Share to social

### Key Screens
1. **Onboarding** - Permission grant + 5-second voice calibration
2. **Live Coach** - Real-time meters for volume, cadence, down-tone with coaching prompts
3. **Practice** - Session management (start/stop) + post-session summary
4. **History** - Session list + trend charts
5. **Settings** - Target dB range, cadence goal (WPM), sensitivity

### What Success Means
- User can complete a practice session and see actionable feedback within 60 seconds of install
- Real-time feedback latency < 100ms for volume, < 500ms for cadence/pitch
- User retention: opens app 3+ times in first week (tracked via session count)
- Sharing: 10%+ of sessions produce a shared card

### Assumptions
- MVP is English-language only
- No backend/auth required for MVP
- Data stored locally via SwiftData
- No subscription/paywall in MVP
- Minimum iOS 17.0 (SwiftUI + SwiftData baseline)

---

## B) Technical Spec

### Architecture
**Pattern:** MVVM with service layer
- **Views/** - SwiftUI screens, pure UI
- **ViewModels/** - ObservableObject classes managing state
- **Audio/** - Audio capture and signal processing pipeline
- **Models/** - SwiftData models for persistence
- **Storage/** - Data access layer
- **DesignSystem/** - Reusable UI components, colors, typography
- **Utilities/** - Math helpers, share card generation

### Audio Pipeline

```
AVAudioEngine (mic input)
    |
    v
installTap(bufferSize: 1024, sampleRate: 44100)
    |
    +---> VolumeAnalyzer (RMS -> dB, every buffer)
    |
    +---> PitchDetector (YIN autocorrelation, every ~23ms)
    |
    +---> CadenceAnalyzer (energy-based syllable counting + SFSpeechRecognizer)
    |
    +---> PhraseSegmenter (pause detection via energy threshold)
              |
              v
        DownToneClassifier (pitch slope of last 300ms of each phrase)
```

### Feature Extraction Details

#### Decibel Measurement
- Compute RMS of each audio buffer: `rms = sqrt(mean(samples^2))`
- Convert to dB: `dB = 20 * log10(rms / reference)`, reference = 1.0 (full scale)
- Smooth with exponential moving average (alpha = 0.3) to reduce jitter
- Default target range: -25 dB to -10 dB (configurable)
- Thresholds: below range = "too quiet", above = "too loud", in range = "good"

#### Pitch Tracking (Down-tone Detection)
- **Algorithm:** YIN pitch detection (autocorrelation-based, well-suited for speech)
- Process: compute difference function, cumulative mean normalized difference, find dip below threshold (0.15)
- Extract pitch (Hz) every ~23ms (1024 samples at 44.1kHz)
- **Phrase segmentation:** detect pauses (energy below threshold for >300ms)
- **Down-tone classification:** for the last 300ms of each phrase:
  - Compute linear regression slope of pitch contour
  - Slope < -15 Hz/s = "downward" (confident authority - GOOD)
  - Slope > 15 Hz/s = "upward" (questioning - needs work)
  - In between = "flat" (neutral)
  - Confidence = R-squared of the linear fit

#### Cadence (Words Per Minute)
- **Primary approach:** On-device SFSpeechRecognizer for word count (when available)
- **Fallback:** Energy-based syllable peak detection (count peaks above dynamic threshold in energy envelope, multiply by 0.6 to approximate words)
- WPM = (word_count / elapsed_seconds) * 60
- Update every 3 seconds with rolling window
- Default target: 130-160 WPM
- Pause ratio: time_silent / total_time (target: 15-25%)

### Data Storage (SwiftData)

```swift
@Model Session {
    id: UUID
    date: Date
    durationSeconds: Double
    averageDB: Double
    dbInRangePercent: Double
    averageWPM: Double
    pauseRatio: Double
    downTonePercent: Double   // % of phrases ending with downward intonation
    upTonePercent: Double
    phraseCount: Int
    // Optional raw pitch contours stored as Data (JSON-encoded arrays)
}

UserSettings (UserDefaults-backed) {
    targetDBMin: Double = -25
    targetDBMax: Double = -10
    targetWPMMin: Double = 130
    targetWPMMax: Double = 160
    sensitivity: Double = 0.5  // 0-1 scale
    saveRecordings: Bool = false
}
```

### Testing Strategy
- **Unit tests:** MathHelpers (RMS, dB conversion, linear regression, slope classification), PitchDetector (known sinusoid input), CadenceAnalyzer thresholds
- **UI tests:** Start/stop session flow, verify summary appears
- **Manual:** Real microphone testing on device (cannot automate mic input in simulator reliably)

### 3rd Party Libraries
**None.** All native frameworks:
- AVFoundation / AVAudioEngine - audio capture
- Accelerate / vDSP - fast DSP math
- Speech - on-device speech recognition (cadence)
- SwiftData - persistence
- SwiftUI / Charts - UI and trend visualization

---

## File Tree

```
sales-app/
+-- README.md
+-- project.yml                          # XcodeGen project definition
+-- ToneCoach/
|   +-- App/
|   |   +-- ToneCoachApp.swift           # App entry point + tab navigation
|   |   +-- Info.plist                   # Privacy descriptions
|   +-- DesignSystem/
|   |   +-- Colors.swift                 # Brand colors
|   |   +-- Typography.swift             # Font styles
|   |   +-- Spacing.swift                # Layout constants
|   |   +-- Components/
|   |       +-- LiveMeter.swift          # Animated arc meter
|   |       +-- CoachingBadge.swift      # Coaching prompt badge
|   |       +-- MiniSparkline.swift      # Inline pitch sparkline
|   |       +-- MetricCard.swift         # Summary metric card
|   |       +-- SessionResultCard.swift  # Shareable result card
|   +-- Models/
|   |   +-- Session.swift                # SwiftData model
|   |   +-- CoachingPrompt.swift         # Prompt types
|   |   +-- UserSettings.swift           # UserDefaults wrapper
|   +-- Audio/
|   |   +-- AudioEngine.swift            # AVAudioEngine manager
|   |   +-- VolumeAnalyzer.swift         # RMS/dB computation
|   |   +-- PitchDetector.swift          # YIN pitch tracking
|   |   +-- CadenceAnalyzer.swift        # WPM estimation
|   |   +-- PhraseSegmenter.swift        # Pause-based segmentation
|   |   +-- DownToneClassifier.swift     # Pitch slope classification
|   +-- ViewModels/
|   |   +-- OnboardingViewModel.swift
|   |   +-- LiveCoachViewModel.swift
|   |   +-- PracticeViewModel.swift
|   |   +-- HistoryViewModel.swift
|   |   +-- SettingsViewModel.swift
|   +-- Views/
|   |   +-- Onboarding/
|   |   |   +-- OnboardingView.swift
|   |   |   +-- CalibrationView.swift
|   |   +-- LiveCoach/
|   |   |   +-- LiveCoachView.swift
|   |   |   +-- VolumeGaugeView.swift
|   |   |   +-- CadenceGaugeView.swift
|   |   |   +-- PitchContourView.swift
|   |   +-- Practice/
|   |   |   +-- PracticeView.swift
|   |   |   +-- SessionSummaryView.swift
|   |   +-- History/
|   |   |   +-- HistoryView.swift
|   |   |   +-- TrendChartView.swift
|   |   +-- Settings/
|   |   |   +-- SettingsView.swift
|   |   +-- Shared/
|   |       +-- UGCModeView.swift
|   |       +-- ShareCardView.swift
|   +-- Storage/
|   |   +-- SessionStore.swift           # SwiftData CRUD
|   +-- Utilities/
|       +-- MathHelpers.swift            # DSP math functions
|       +-- ShareCardGenerator.swift     # UIImage export
+-- ToneCoachTests/
|   +-- MathHelpersTests.swift
|   +-- PitchSlopeTests.swift
|   +-- CadenceAnalyzerTests.swift
+-- ToneCoachUITests/
    +-- SessionFlowTests.swift
```

---

## How to Run

### Prerequisites
- Xcode 15.0+ (for iOS 17 / SwiftData support)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed: `brew install xcodegen`
- Physical iPhone recommended (microphone required for real testing)

### Steps
```bash
cd sales-app
xcodegen generate        # Generates ToneCoach.xcodeproj from project.yml
open ToneCoach.xcodeproj # Open in Xcode
```
1. Select your iPhone (or simulator for UI layout testing)
2. Build and run (Cmd+R)
3. Grant microphone permission when prompted
4. Complete the 5-second calibration
5. Start coaching!

### Running Tests
```bash
# Unit tests
xcodebuild test -scheme ToneCoach -destination 'platform=iOS Simulator,name=iPhone 16'

# Or in Xcode: Cmd+U
```

---

## App Store Assets (Concepts)

### 6 Screenshot Concepts
1. **Live Volume Meter** - Arc gauge showing "In Range" with green glow, coaching prompt visible
2. **Cadence Dashboard** - WPM counter with pacing visualization, "Slow down 10%" prompt
3. **Down-Tone Detection** - Pitch sparkline showing downward slope with confidence badge
4. **Session Summary Card** - Post-practice metrics with authority score
5. **History Trends** - Line charts showing improvement over 2 weeks
6. **Share Card** - Beautiful result card as it would appear on social media

### 2 Preview Video Scripts
**Video 1: "Find Your Authority Voice" (15s)**
- Open app -> Start session -> Speak "Let me tell you about our Q4 results..."
- Show live meter responding -> coaching prompt "Great down-tone!"
- End session -> summary card with 87% authority score

**Video 2: "Track Your Progress" (15s)**
- Quick montage of 3 practice sessions
- Show history screen with upward trend lines
- Share a result card -> "Share your voice authority score"
