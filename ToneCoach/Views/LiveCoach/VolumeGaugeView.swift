import SwiftUI

/// Standalone volume gauge for detailed view (extends LiveMeter with dB labels).
struct VolumeGaugeView: View {
    let db: Double
    let minDB: Double
    let maxDB: Double
    let status: MeterStatus

    var body: some View {
        VStack(spacing: TCSpacing.sm) {
            LiveMeter(
                value: normalizeDB(db, min: minDB, max: maxDB),
                label: String(format: "%.0f", db),
                status: status,
                size: 160
            )

            // Range labels
            HStack {
                Text(String(format: "%.0f dB", minDB))
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
                Spacer()
                Text("Target")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textSecondary)
                Spacer()
                Text(String(format: "%.0f dB", maxDB))
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
            }
            .padding(.horizontal, TCSpacing.md)
        }
    }
}
