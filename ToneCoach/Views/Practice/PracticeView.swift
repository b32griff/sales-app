import SwiftUI
import SwiftData

/// Main practice screen: start/stop sessions with live coaching.
struct PracticeView: View {
    @StateObject private var vm = PracticeViewModel()
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ZStack {
                TCColor.background.ignoresSafeArea()

                switch vm.state {
                case .idle, .summary:
                    idleView
                case .recording:
                    recordingView
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $vm.completedSession) { session in
                SessionSummaryView(
                    session: session,
                    previousSession: vm.previousSession
                ) {
                    vm.resetToIdle()
                } onShare: {
                    // handled inside summary view
                } onViewHistory: {
                    vm.resetToIdle()
                    selectedTab = 1
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TCRadius.xl)
                .interactiveDismissDisabled()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: TCSpacing.sm) {
            Spacer()

            VStack(spacing: TCSpacing.xs) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(TCColor.accent)
                    .padding(.bottom, TCSpacing.xxs)

                Text("Ready to Practice")
                    .font(TCFont.title)
                    .foregroundStyle(TCColor.textPrimary)

                Text("Real-time coaching on volume,\ntone, and cadence.")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
                    .multilineTextAlignment(.center)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.bad)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TCSpacing.md)
            }

            Spacer()

            Button {
                vm.startSession()
            } label: {
                Text("Start Session")
                    .font(TCFont.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TCSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: TCRadius.md)
                            .fill(TCColor.accent)
                    )
            }
            .padding(.horizontal, TCSpacing.lg)
            .padding(.bottom, TCSpacing.lg)
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 0) {
            // ── Top bar: timer · stop ──
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TCColor.bad)
                        .frame(width: 6, height: 6)
                    Text(vm.elapsedTime)
                        .font(TCFont.mono)
                        .foregroundStyle(TCColor.textSecondary)
                }

                Spacer()

                Button {
                    vm.stopSession(context: modelContext)
                } label: {
                    HStack(spacing: TCSpacing.xxs) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, TCSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TCColor.accent))
                }
            }
            .padding(.horizontal, TCSpacing.md)
            .padding(.top, TCSpacing.xs)
            .padding(.bottom, TCSpacing.xs)

            // ── Live metrics ──
            ScrollView(showsIndicators: false) {
                LiveCoachView(
                    volume: vm.binder.volume,
                    tone: vm.binder.tone,
                    cadence: vm.binder.cadence,
                    prompt: vm.binder.prompt,
                    settings: vm.binder.settings
                )
                .padding(.horizontal, TCSpacing.md)
                .padding(.bottom, TCSpacing.md)
            }
        }
    }
}
