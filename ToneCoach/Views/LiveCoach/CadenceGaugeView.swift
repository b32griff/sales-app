import SwiftUI

/// Standalone cadence gauge with WPM range labels.
struct CadenceGaugeView: View {
    let wpm: Double
    let minWPM: Double
    let maxWPM: Double
    let status: MeterStatus

    var body: some View {
        VStack(spacing: TCSpacing.sm) {
            LiveMeter(
                value: normalizeWPM(wpm, min: minWPM, max: maxWPM),
                label: wpm > 10 ? String(format: "%.0f", wpm) : "--",
                status: status,
                size: 160
            )

            HStack {
                Text(String(format: "%.0f wpm", minWPM))
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
                Spacer()
                Text("Target")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textSecondary)
                Spacer()
                Text(String(format: "%.0f wpm", maxWPM))
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }
            .padding(.horizontal, TCSpacing.md)
        }
    }
}
