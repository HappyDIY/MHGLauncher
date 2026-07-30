import SwiftUI

struct DownloadSpeedPlotCanvas: View {
    let vector: SpeedPlotVector
    let count: Int

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let layout = SpeedPlotLayout(vector: vector, count: count, size: size)
            drawGrid(layout, context: &context)
            guard layout.points.count > 1 else { return }
            let line = Self.curvePath(layout.points)
            var area = line
            area.addLine(to: CGPoint(x: layout.plotRect.maxX, y: layout.plotRect.maxY))
            area.addLine(to: CGPoint(x: layout.plotRect.minX, y: layout.plotRect.maxY))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [
                        .accentColor.opacity(0.18),
                        .accentColor.opacity(0.02)
                    ]),
                    startPoint: CGPoint(x: 0, y: layout.plotRect.minY),
                    endPoint: CGPoint(x: 0, y: layout.plotRect.maxY)
                )
            )
            context.stroke(line, with: .color(.accentColor), lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("下载速度趋势图")
    }

    private func drawGrid(
        _ layout: SpeedPlotLayout,
        context: inout GraphicsContext
    ) {
        for step in 0...2 {
            let ratio = CGFloat(step) / 2
            let y = layout.plotRect.maxY - layout.plotRect.height * ratio
            var grid = Path()
            grid.move(to: CGPoint(x: layout.plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: layout.plotRect.maxX, y: y))
            context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)

            let value = layout.maximumMegabytes * Double(ratio)
            let label = context.resolve(
                Text(String(format: "%.0f MB/s", value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )
            context.draw(
                label,
                at: CGPoint(x: layout.plotRect.minX - 4, y: y),
                anchor: .trailing
            )
        }
    }

    static func curvePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let previous = index > 0 ? points[index - 1] : start
            let following = index + 2 < points.count ? points[index + 2] : end
            let control1 = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: end.x - (following.x - start.x) / 6,
                y: end.y - (following.y - start.y) / 6
            )
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }
}

struct SpeedPlotLayout {
    let plotRect: CGRect
    let points: [CGPoint]
    let maximumMegabytes: Double

    init(vector: SpeedPlotVector, count: Int, size: CGSize) {
        let resolvedPlotRect = CGRect(
            x: 54,
            y: 6,
            width: max(size.width - 58, 1),
            height: max(size.height - 12, 1)
        )
        plotRect = resolvedPlotRect
        let validCount = min(max(count, 0), SpeedPlotVector.capacity)
        let maximumBytes = (0..<validCount).reduce(0) {
            max($0, vector.speeds[$1])
        }
        let resolvedMaximum = Self.axisMaximum(maximumBytes / 1_048_576)
        maximumMegabytes = resolvedMaximum
        guard validCount > 0 else {
            points = []
            return
        }
        let firstTime = vector.times[0]
        let lastTime = vector.times[validCount - 1]
        let duration = max(lastTime - firstTime, 1)
        points = (0..<validCount).map { index in
            let xRatio = (vector.times[index] - firstTime) / duration
            let megabytes = vector.speeds[index] / 1_048_576
            let yRatio = min(max(megabytes / resolvedMaximum, 0), 1)
            return CGPoint(
                x: resolvedPlotRect.minX + resolvedPlotRect.width * xRatio,
                y: resolvedPlotRect.maxY - resolvedPlotRect.height * yRatio
            )
        }
    }

    static func axisMaximum(_ value: Double) -> Double {
        guard value > 1 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return ceil(value / magnitude) * magnitude
    }
}
