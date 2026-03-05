import Foundation

/// A coaching prompt shown to the user during a live session.
/// Language inspired by Alex Hormozi's sales tone framework.
struct CoachingPrompt: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    let severity: Severity
    let category: Category

    enum Severity: Equatable {
        case positive
        case suggestion
    }

    enum Category: Equatable {
        case volume
        case cadence
        case downTone
        case pause
        case articulation
    }

    // MARK: - Volume (Constant #1)

    static func tooQuiet() -> CoachingPrompt {
        CoachingPrompt(
            message: "Speak louder — they can't buy if they can't hear you",
            icon: "speaker.wave.3.fill",
            severity: .suggestion,
            category: .volume
        )
    }

    static func tooLoud() -> CoachingPrompt {
        CoachingPrompt(
            message: "Dial it back — controlled power",
            icon: "speaker.slash.fill",
            severity: .suggestion,
            category: .volume
        )
    }

    static func volumeGood() -> CoachingPrompt {
        CoachingPrompt(
            message: "Volume is dialed in",
            icon: "speaker.wave.2.fill",
            severity: .positive,
            category: .volume
        )
    }

    // MARK: - Speed (Constant #2)

    static func tooFast() -> CoachingPrompt {
        CoachingPrompt(
            message: "Slow down — too fast kills trust",
            icon: "tortoise.fill",
            severity: .suggestion,
            category: .cadence
        )
    }

    static func tooSlow() -> CoachingPrompt {
        CoachingPrompt(
            message: "Pick up the energy — don't lose them",
            icon: "hare.fill",
            severity: .suggestion,
            category: .cadence
        )
    }

    static func cadenceGood() -> CoachingPrompt {
        CoachingPrompt(
            message: "Perfect pace — keep it there",
            icon: "metronome.fill",
            severity: .positive,
            category: .cadence
        )
    }

    // MARK: - Articulation (Constant #3)

    static func articulateMore() -> CoachingPrompt {
        CoachingPrompt(
            message: "Enunciate — round out every word",
            icon: "text.word.spacing",
            severity: .suggestion,
            category: .articulation
        )
    }

    static func articulationGood() -> CoachingPrompt {
        CoachingPrompt(
            message: "Crystal clear articulation",
            icon: "text.word.spacing",
            severity: .positive,
            category: .articulation
        )
    }

    // MARK: - Pauses (Variable #1)

    static func needMorePauses() -> CoachingPrompt {
        CoachingPrompt(
            message: "Pause more — let your points land",
            icon: "pause.circle.fill",
            severity: .suggestion,
            category: .pause
        )
    }

    static func goodPauseUsage() -> CoachingPrompt {
        CoachingPrompt(
            message: "Great use of pauses",
            icon: "pause.circle.fill",
            severity: .positive,
            category: .pause
        )
    }

    // MARK: - Pitch Direction (Variable #2)

    static func downToneGood() -> CoachingPrompt {
        CoachingPrompt(
            message: "Strong down-tone — don't ask, tell",
            icon: "arrow.down.right.circle.fill",
            severity: .positive,
            category: .downTone
        )
    }

    static func upToneDetected() -> CoachingPrompt {
        CoachingPrompt(
            message: "End lower — statements, not questions",
            icon: "arrow.up.right.circle.fill",
            severity: .suggestion,
            category: .downTone
        )
    }
}
