import SwiftUI
import SwiftData

/// UGC Mode: A guided 20-second demo script that produces a shareable result card.
struct UGCModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PracticeViewModel()

    enum Phase {
        case intro
        case recording
        case result
    }

    @State private var phase: Phase = .intro
    @State private var countdown = 20
    @State private var timer: Timer?

    private let demoScript = """
    "Our team delivered a 15% increase in revenue this quarter. \
    We focused on three key areas: customer retention, product innovation, \
    and operational efficiency. The results speak for themselves."
    """

    var body: some View {
        ZStack {
            TCColor.background.ignoresSafeArea()

            VStack(spacing: TCSpacing.md) {
                switch phase {
                case .intro:
                    introView
                case .recording:
                    recordingView
                case .result:
                    if let session = vm.completedSession {
                        resultView(session)
                    }
                }
            }
            .padding(TCSpacing.md)
        }
        .navigationTitle("Quick Demo")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var introView: some View {
        VStack(spacing: TCSpacing.md) {
            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(TCColor.accent)

            Text("20-Second Challenge")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text("Read the script below with confidence.\nWe'll score your authority.")
                .font(TCFont.body)
                .foregroundStyle(TCColor.textSecondary)
                .multilineTextAlignment(.center)

            Text(demoScript)
                .font(TCFont.body)
                .foregroundStyle(TCColor.textPrimary)
                .padding(TCSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: TCRadius.md)
                        .fill(TCColor.surfaceAlt)
                )

            Spacer()

            Button("Start Recording") {
                startRecording()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var recordingView: some View {
        VStack(spacing: TCSpacing.md) {
            Text("\(countdown)")
                .font(TCFont.metric)
                .foregroundStyle(TCColor.accent)

            Text(demoScript)
                .font(TCFont.body)
                .foregroundStyle(TCColor.textPrimary)
                .padding(TCSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: TCRadius.md)
                        .fill(TCColor.surfaceAlt)
                )

            LiveCoachView(
                    volume: vm.binder.volume,
                    tone: vm.binder.tone,
                    cadence: vm.binder.cadence,
                    prompt: vm.binder.prompt,
                    settings: vm.binder.settings
                )

            Spacer()
        }
    }

    private func resultView(_ session: Session) -> some View {
        VStack(spacing: TCSpacing.md) {
            Text("Your Result")
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            SessionResultCard(session: session, showBranding: true)

            HStack(spacing: TCSpacing.md) {
                Button("Share") {
                    shareResult(session)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Done") {
                    dismiss()
                }
                .font(TCFont.callout)
                .foregroundStyle(TCColor.textSecondary)
            }
        }
    }

    private func startRecording() {
        vm.startSession()
        phase = .recording
        countdown = 20

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 {
                    t.invalidate()
                    vm.stopSession(context: modelContext)
                    phase = .result
                }
            }
        }
    }

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    private func shareResult(_ session: Session) {
        let renderer = ImageRenderer(content:
            SessionResultCard(session: session, showBranding: true)
                .padding(TCSpacing.md)
                .background(TCColor.background)
                .frame(width: 360)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(controller, animated: true)
            }
        }
    }
}
