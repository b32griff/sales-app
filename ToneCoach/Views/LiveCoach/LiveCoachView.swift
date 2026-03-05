import SwiftUI

/// Live coaching view — 3 compact metric cards + coaching prompt.
/// Each card observes its own @Observable state object independently.
/// A volume update does NOT cause tone or cadence cards to redraw.
struct LiveCoachView: View {
    let volume: VolumeState
    let tone: ToneState
    let cadence: CadenceState
    let prompt: PromptState
    let settings: UserSettings

    var body: some View {
        VStack(spacing: TCSpacing.sm) {
            // Coaching prompt — compact pill, tap to dismiss
            if let p = prompt.current {
                CoachingBadge(prompt: p)
                    .id(p.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: p.id)
            }

            // Cadence coaching banner (inline pill)
            if let bannerMessage = cadence.bannerMessage {
                CadenceBannerView(message: bannerMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 1. VOLUME WAVEFORM
            VolumeCard(
                state: volume,
                targetDBMin: settings.targetDBMin,
                targetDBMax: settings.targetDBMax
            )

            // 2. TONE (per-sentence grading)
            ToneCard(state: tone)

            // 3. CADENCE
            CadenceCard(state: cadence)
        }
    }
}

// MARK: - Expanded Volume Sheet

private struct VolumeExpandedSheet: View {
    let state: VolumeState
    let targetDBMin: Double
    let targetDBMax: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: TCSpacing.md) {
                // Large graph using the same Canvas pipeline
                let history = state.dbHistory
                let smoothed = history.count >= 3 ? VolumeCard.smoothForDisplay(history) : history

                Canvas { context, size in
                    VolumeCard.drawTargetBand(in: &context, size: size,
                                              dbMin: targetDBMin, dbMax: targetDBMax)
                    guard smoothed.count >= 2 else { return }
                    let points = VolumeCard.mapToPoints(smoothed, size: size)
                    let curve = VolumeCard.catmullRomPath(points: points)

                    var fill = curve
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(
                        Gradient(colors: [TCColor.accent.opacity(0.25), TCColor.accent.opacity(0.02)]),
                        startPoint: .init(x: size.width / 2, y: 0),
                        endPoint: .init(x: size.width / 2, y: size.height)
                    ))
                    context.stroke(curve, with: .color(TCColor.accent),
                                  style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 220)
                .drawingGroup()
                .background(TCColor.surfaceAlt.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: TCRadius.md))
                .padding(.horizontal, TCSpacing.md)

                HStack(spacing: TCSpacing.xl) {
                    VStack {
                        Text(state.label).font(TCFont.title).foregroundStyle(TCColor.textPrimary)
                        Text("Current").font(TCFont.caption).foregroundStyle(TCColor.textTertiary)
                    }
                    VStack {
                        Text("\(Int(targetDBMin))–\(Int(targetDBMax))").font(TCFont.title).foregroundStyle(TCColor.accent)
                        Text("Target dB").font(TCFont.caption).foregroundStyle(TCColor.textTertiary)
                    }
                }
                .padding(.top, TCSpacing.sm)

                Spacer()
            }
            .background(TCColor.background)
            .navigationTitle("Volume Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Cadence Card (observes CadenceState only)

struct CadenceCard: View {
    let state: CadenceState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: TCSpacing.xxs) {
                Text("Cadence")
                    .font(TCFont.headline)
                    .foregroundStyle(TCColor.textPrimary)
                Text(state.rangeLabel)
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: TCSpacing.xxs) {
                Text(state.label)
                    .font(TCFont.metricSmall)
                    .foregroundStyle(cadenceColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: state.label)
                if state.label != "--" {
                    Text("wpm")
                        .font(TCFont.callout)
                        .foregroundStyle(TCColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, TCSpacing.md)
        .padding(.vertical, TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
    }

    private var cadenceColor: Color {
        switch state.status {
        case .good:    return TCColor.good
        case .warning: return TCColor.accent
        case .bad:     return TCColor.bad
        case .idle:    return TCColor.textTertiary
        }
    }
}

// MARK: - Cadence Coaching Banner

struct CadenceBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: message == "Slow down" ? "tortoise.fill" : "hare.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(TCFont.badge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TCSpacing.sm)
        .padding(.vertical, 7)
        .background(Capsule().fill(TCColor.accent))
        .frame(maxWidth: .infinity)
    }
}
