import SwiftUI

/// A small inline sparkline for pitch contour visualization.
/// Uses Canvas for GPU-accelerated rendering — no SwiftUI Path recomputation per tick.
struct MiniSparkline: View {
    let values: [Double]
    let color: Color
    let height: CGFloat

    init(values: [Double], color: Color = TCColor.accent, height: CGFloat = 40) {
        self.values = values
        self.color = color
        self.height = height
    }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2,
                  let minVal = values.min(),
                  let maxVal = values.max(),
                  maxVal > minVal else { return }

            let range = maxVal - minVal
            var path = Path()
            for (i, val) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((val - minVal) / range))
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color),
                          style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}
