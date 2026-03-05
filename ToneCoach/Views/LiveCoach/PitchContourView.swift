import SwiftUI

/// Displays the pitch contour of the last phrase with a slope indicator.
struct PitchContourView: View {
    let values: [Double]
    let toneDirection: String

    var body: some View {
        HStack(spacing: TCSpacing.sm) {
            if values.count >= 2 {
                MiniSparkline(values: values, color: contourColor, height: 36)

                Image(systemName: directionIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(contourColor)
            } else {
                HStack {
                    Spacer()
                    Text("Speak to see pitch contour")
                        .font(TCFont.caption)
                        .foregroundStyle(TCColor.textTertiary)
                    Spacer()
                }
                .frame(height: 36)
            }
        }
    }

    private var contourColor: Color {
        switch toneDirection {
        case "Downward": return TCColor.good
        case "Upward":   return TCColor.bad
        default:         return TCColor.accentLight
        }
    }

    private var directionIcon: String {
        switch toneDirection {
        case "Downward": return "arrow.down.right"
        case "Upward":   return "arrow.up.right"
        default:         return "arrow.right"
        }
    }
}
