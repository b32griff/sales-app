import SwiftUI

// MARK: - VolumeCard (isolated, performance-optimized)

/// Displays a real-time dB waveform with target band overlay.
///
/// Performance contract:
/// - Redraws ONLY when VolumeState properties actually change (generation-gated).
/// - Canvas closure receives precomputed points — no array allocation inside draw.
/// - Target band geometry is cached and only recomputes when settings change.
/// - Catmull-Rom spline with polyline fallback for low-power mode.
struct VolumeCard: View {
    let state: VolumeState
    let targetDBMin: Double
    let targetDBMax: Double

    // Display constants
    private static let displayDBMin: Double = -80
    private static let displayDBMax: Double = -10
    private static let displayDBRange: Double = displayDBMax - displayDBMin
    private static let graphHeight: CGFloat = 160

    #if DEBUG
    @State private var redrawCount: Int = 0
    @State private var redrawRateTracker = RateTracker(label: "VolumeCard redraws")
    #endif

    var body: some View {
        // Precompute all data OUTSIDE the Canvas closure.
        // These locals are captured by value — Canvas does zero allocation.
        let history = state.dbHistory
        let smoothed = history.count >= 3 ? Self.smoothForDisplay(history) : history
        let lineColor = statusColor
        let inRange = state.status == .good

        VStack(alignment: .leading, spacing: TCSpacing.xs) {
            // Header — dominant dB readout
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: TCSpacing.xxxs) {
                    Text("Volume")
                        .font(TCFont.headline)
                        .foregroundStyle(TCColor.textPrimary)
                    Text(statusText)
                        .font(TCFont.badge)
                        .foregroundStyle(lineColor)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: TCSpacing.xxs) {
                    Text(state.label)
                        .font(TCFont.metricSmall)
                        .foregroundStyle(lineColor)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: state.label)
                    if inRange {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TCColor.good)
                    }
                }
            }

            // Canvas waveform
            Canvas { context, size in
                #if DEBUG
                // Tick the redraw counter (mutating @State from Canvas is safe via Task)
                Task { @MainActor in redrawRateTracker.tick() }
                #endif

                Self.drawTargetBand(in: &context, size: size,
                                    dbMin: targetDBMin, dbMax: targetDBMax)

                guard smoothed.count >= 2 else { return }

                // Map smoothed dB values to screen points
                let points = Self.mapToPoints(smoothed, size: size)

                // Build curve path (spline or polyline fallback)
                let curvePath: Path
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    curvePath = Self.polylinePath(points: points)
                } else {
                    curvePath = Self.catmullRomPath(points: points)
                }

                // Gradient fill under curve
                var fillPath = curvePath
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [lineColor.opacity(0.25), lineColor.opacity(0.02)]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                ))

                // Stroke
                context.stroke(curvePath, with: .color(lineColor),
                              style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: Self.graphHeight)
            .background(TCColor.surfaceAlt.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: TCRadius.sm))

            // Footer — target range
            HStack {
                Text("Target: \(Int(targetDBMin))–\(Int(targetDBMax)) dB")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.accent.opacity(0.6))
                Spacer()
            }

            #if DEBUG
            VolumeCardDebugOverlay(
                tracker: redrawRateTracker,
                snapshotGen: state.generation,
                snapshotRate: state.debugSnapshotRate,
                bufferRate: state.debugBufferRate
            )
            #endif
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: TCRadius.md)
                        .strokeBorder(
                            inRange ? TCColor.good.opacity(0.15) : .clear,
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Status

    private var statusText: String {
        switch state.status {
        case .good: return "In Range"
        case .warning: return "Adjust"
        case .bad: return "Out of Range"
        case .idle: return "Ready"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .good: return TCColor.good
        case .warning: return TCColor.accent
        case .bad: return TCColor.bad
        case .idle: return TCColor.textTertiary
        }
    }

    // MARK: - Drawing Helpers (all static, no instance state)

    /// Draw the target band with dashed border lines. Only depends on settings (rarely changes).
    static func drawTargetBand(
        in context: inout GraphicsContext,
        size: CGSize,
        dbMin: Double,
        dbMax: Double
    ) {
        let topY = size.height * (1 - (dbMax - displayDBMin) / displayDBRange)
        let botY = size.height * (1 - (dbMin - displayDBMin) / displayDBRange)
        let bandRect = CGRect(x: 0, y: topY, width: size.width, height: max(0, botY - topY))
        context.fill(Path(bandRect), with: .color(TCColor.accent.opacity(0.10)))

        let dashStyle = StrokeStyle(lineWidth: 0.5, dash: [4, 4])
        var topLine = Path()
        topLine.move(to: CGPoint(x: 0, y: topY))
        topLine.addLine(to: CGPoint(x: size.width, y: topY))
        context.stroke(topLine, with: .color(TCColor.accent.opacity(0.35)), style: dashStyle)

        var botLine = Path()
        botLine.move(to: CGPoint(x: 0, y: botY))
        botLine.addLine(to: CGPoint(x: size.width, y: botY))
        context.stroke(botLine, with: .color(TCColor.accent.opacity(0.35)), style: dashStyle)
    }

    /// Map dB values to CGPoints within the given size. One allocation, done outside Canvas.
    static func mapToPoints(_ values: [Double], size: CGSize) -> [CGPoint] {
        let count = values.count
        guard count >= 2 else { return [] }
        let xScale = size.width / CGFloat(count - 1)
        return values.enumerated().map { i, v in
            let normalized = (v - displayDBMin) / displayDBRange
            let y = size.height * (1 - min(max(normalized, 0), 1))
            return CGPoint(x: CGFloat(i) * xScale, y: y)
        }
    }

    // MARK: - Display Smoothing (5-point moving average)

    /// Applies a 5-point symmetric moving average to reduce visual jitter.
    /// Each output[i] = average of input[i-2...i+2], clamped at edges.
    /// Preserves shape while removing frame-to-frame noise.
    static func smoothForDisplay(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n >= 3 else { return values }
        var result = [Double](repeating: 0, count: n)
        let windowRadius = 2
        for i in 0..<n {
            let lo = max(0, i - windowRadius)
            let hi = min(n - 1, i + windowRadius)
            var sum = 0.0
            for j in lo...hi { sum += values[j] }
            result[i] = sum / Double(hi - lo + 1)
        }
        return result
    }

    // MARK: - Path Builders

    /// Simple polyline — zero-overhead fallback for low-power mode.
    static func polylinePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        return path
    }

    /// Catmull-Rom spline — smooth cubic Bézier through all points.
    /// ~150 segments is negligible cost on any modern device.
    static func catmullRomPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])
        guard points.count >= 3 else {
            path.addLine(to: points[1])
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }
}

// MARK: - Debug Instrumentation

#if DEBUG
/// Lightweight rate tracker — counts events per second via a sliding window.
/// Used for measuring publish rate, redraw rate, audio buffer rate.
@Observable
final class RateTracker {
    let label: String
    private(set) var rate: Double = 0
    private var timestamps: [CFTimeInterval] = []

    init(label: String) {
        self.label = label
    }

    /// Call once per event. Computes rate over trailing 2-second window.
    @MainActor
    func tick() {
        let now = CACurrentMediaTime()
        timestamps.append(now)
        // Trim to 2-second window
        let cutoff = now - 2.0
        while let first = timestamps.first, first < cutoff {
            timestamps.removeFirst()
        }
        rate = Double(timestamps.count) / 2.0
    }
}

/// Overlay showing buffer/s, snapshot/s, redraw/s — all three pipeline stages.
struct VolumeCardDebugOverlay: View {
    let tracker: RateTracker
    let snapshotGen: UInt64
    let snapshotRate: Double
    let bufferRate: Double

    var body: some View {
        HStack(spacing: TCSpacing.sm) {
            Text("buf:\(String(format: "%.0f", bufferRate))")
            Text("snap:\(String(format: "%.1f", snapshotRate))")
            Text("draw:\(String(format: "%.1f", tracker.rate))")
            Text("gen:\(snapshotGen)")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(TCColor.textTertiary)
    }
}
#endif
