#if DEBUG
import SwiftUI

/// Floating text-only debug overlay. Extremely cheap — monospaced Text views
/// updated at 2 Hz by DebugState. No Combine subscriptions, no Canvas.
///
/// OWNERSHIP: Terminal 11 (Logging + Debug Overlay) only.
/// INTEGRATION: Terminal 8 (Practice Flow) places this in PracticeView.
/// See insertion snippet at bottom of file.
struct DebugOverlayView: View {
    @ObservedObject var state: DebugState

    var body: some View {
        if state.isVisible {
            VStack(alignment: .leading, spacing: 2) {
                row("dB",   state.dbLabel)
                row("snap", state.snapshotHzLabel)
                row("buf",  state.bufferHzLabel)
                row("wpm",  state.wpmLabel)
                row("tone", state.toneLabel)
                row("proc", state.processingMsLabel)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(6)
            .background(.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.gray)
                .frame(width: 36, alignment: .trailing)
            Text(value)
                .foregroundStyle(.green)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// INSERTION SNIPPET FOR TERMINAL 8 (PracticeView / PracticeViewModel)
// ═══════════════════════════════════════════════════════════════════
//
// ── Step 1: Add to PracticeViewModel ──
//
//   #if DEBUG
//   let debugState = DebugState()
//   #endif
//
// ── Step 2: In PracticeViewModel.doStart(), after `try audioEngine.start()`: ──
//
//   #if DEBUG
//   debugState.bind(to: audioEngine)
//   #endif
//
// ── Step 3: In PracticeViewModel.stopSession(), after `audioEngine.stop()`: ──
//
//   #if DEBUG
//   debugState.unbind()
//   #endif
//
// ── Step 4: In PracticeView recordingView, wrap in ZStack and add overlay: ──
//
//   // Inside recordingView body, after the existing VStack:
//   #if DEBUG
//   VStack {
//       HStack { Spacer(); DebugOverlayView(state: vm.debugState).padding(8) }
//       Spacer()
//   }
//   #endif
//
// ── Step 5: Triple-tap toggle on the elapsed time HStack: ──
//
//   // Add to the HStack containing the timer in recordingView:
//   #if DEBUG
//   .onTapGesture(count: 3) { vm.debugState.toggle() }
//   #endif
//
// That's it. 5 insertions, all gated behind #if DEBUG.
// ═══════════════════════════════════════════════════════════════════
#endif
