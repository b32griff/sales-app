import SwiftUI
import Charts

/// A simple line chart showing a metric trend over time.
struct TrendChartView: View {
    let title: String
    let data: [(Date, Double)]
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: TCSpacing.xs) {
            HStack {
                Text(title)
                    .font(TCFont.callout)
                    .foregroundStyle(TCColor.textPrimary)
                Spacer()
                if let last = data.last {
                    Text(String(format: "%.0f %@", last.1, unit))
                        .font(TCFont.mono)
                        .foregroundStyle(color)
                }
            }

            if data.count >= 2 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.0),
                            y: .value(title, point.1)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.0),
                            y: .value(title, point.1)
                        )
                        .foregroundStyle(color.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0f", v))
                                    .font(.system(size: 10))
                                    .foregroundStyle(TCColor.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 80)
            } else if data.count == 1 {
                // Single session — show the point so the chart isn't blank
                Chart {
                    PointMark(
                        x: .value("Date", data[0].0),
                        y: .value(title, data[0].1)
                    )
                    .foregroundStyle(color)
                    .symbolSize(60)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    Text("One more session to see trends")
                        .font(TCFont.caption)
                        .foregroundStyle(TCColor.textTertiary)
                }
            } else {
                // No data at all
                Text("Complete a session to start tracking")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
        .padding(.horizontal, TCSpacing.md)
    }
}
