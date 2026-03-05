import SwiftUI

/// Arc-style gauge meter for real-time feedback (volume, cadence, etc.)
struct LiveMeter: View {
    let value: Double      // 0...1 normalized
    let label: String
    let status: MeterStatus
    let size: CGFloat

    init(value: Double, label: String, status: MeterStatus, size: CGFloat = 140) {
        self.value = min(max(value, 0), 1)
        self.label = label
        self.status = status
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background arc
            ArcShape(startAngle: .degrees(135), endAngle: .degrees(405))
                .stroke(TCColor.surfaceAlt, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: size, height: size)

            // Value arc
            ArcShape(
                startAngle: .degrees(135),
                endAngle: .degrees(135 + 270 * value)
            )
            .stroke(
                status.color,
                style: StrokeStyle(lineWidth: 10, lineCap: .round)
            )
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.15), value: value)

            // Center label
            VStack(spacing: TCSpacing.xxs) {
                Text(label)
                    .font(TCFont.metricSmall)
                    .foregroundStyle(TCColor.textPrimary)
                Text(status.text)
                    .font(TCFont.caption)
                    .foregroundStyle(status.color)
            }
        }
    }
}

enum MeterStatus: Equatable {
    case good, warning, bad, idle

    var color: Color {
        switch self {
        case .good:    return TCColor.good
        case .warning: return TCColor.accent
        case .bad:     return TCColor.bad
        case .idle:    return TCColor.textTertiary
        }
    }

    var text: String {
        switch self {
        case .good:    return "In Range"
        case .warning: return "Adjust"
        case .bad:     return "Out of Range"
        case .idle:    return "Ready"
        }
    }
}

/// Arc shape from startAngle to endAngle (clockwise).
struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle.degrees, endAngle.degrees) }
        set {
            startAngle = .degrees(newValue.first)
            endAngle = .degrees(newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
        }
    }
}
