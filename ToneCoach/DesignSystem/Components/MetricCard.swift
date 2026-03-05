import SwiftUI

/// Card showing a single metric with label and status.
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let status: MeterStatus
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: TCSpacing.xs) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(status.color)
                Text(title)
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textSecondary)
                Spacer()
            }

            Text(value)
                .font(TCFont.title)
                .foregroundStyle(TCColor.textPrimary)

            Text(subtitle)
                .font(TCFont.caption)
                .foregroundStyle(status.color)
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
    }
}
