import SwiftUI

/// Voice calibration step — user speaks normally for 5 seconds.
struct CalibrationView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: TCSpacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(TCColor.accent)
                .symbolEffect(.variableColor.iterative, isActive: vm.isCalibrating)

            Text("Voice Calibration")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text(vm.isCalibrating
                 ? "Speak in your normal voice..."
                 : "We'll listen for 5 seconds to calibrate your baseline volume.")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            if vm.isCalibrating {
                ProgressView(value: vm.calibrationProgress)
                    .tint(TCColor.accent)
                    .padding(.horizontal, TCSpacing.md)

                Text(String(format: "%.0f dB detected", vm.calibrationDB))
                    .font(TCFont.mono)
                    .foregroundStyle(TCColor.textTertiary)
            } else {
                Button("Start Calibration") {
                    vm.startCalibration()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
