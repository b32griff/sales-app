import SwiftUI

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            TCColor.background.ignoresSafeArea()

            VStack(spacing: TCSpacing.md) {
                Spacer()

                switch vm.currentStep {
                case .welcome:
                    welcomeStep
                case .micPermission:
                    micPermissionStep
                case .speechPermission:
                    speechPermissionStep
                case .calibration:
                    CalibrationView(vm: vm)
                case .done:
                    doneStep
                }

                Spacer()
            }
            .padding(TCSpacing.md)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: TCSpacing.md) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 64))
                .foregroundStyle(TCColor.accent)

            Text("ToneCoach")
                .font(TCFont.largeTitle)
                .foregroundStyle(TCColor.textPrimary)

            Text("Speak with authority.\nReal-time coaching for your voice.")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button("Get Started") {
                vm.currentStep = .micPermission
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var micPermissionStep: some View {
        VStack(spacing: TCSpacing.md) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(TCColor.accent)

            Text("Microphone Access")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text("ToneCoach processes audio entirely on your device. Nothing is recorded or sent anywhere.")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button("Allow Microphone") {
                vm.requestMicPermission()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var speechPermissionStep: some View {
        VStack(spacing: TCSpacing.md) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(TCColor.accent)

            Text("Speech Recognition")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text("On-device speech recognition helps measure your speaking pace accurately.")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button("Allow Speech Recognition") {
                vm.requestSpeechPermission()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Skip") {
                vm.currentStep = .calibration
            }
            .font(TCFont.callout)
            .foregroundStyle(TCColor.textTertiary)
        }
    }

    private var doneStep: some View {
        VStack(spacing: TCSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(TCColor.good)

            Text("You're Ready")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text("Your voice baseline has been calibrated. Start your first practice session!")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button("Start Coaching") {
                vm.completeOnboarding()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
