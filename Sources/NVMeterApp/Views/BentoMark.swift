import SwiftUI

/// The NVMeter mark, rendered as a SwiftUI Shape so it scales perfectly
/// at every size with no asset pipeline. Mirrors `design/logo/mark.svg`.
///
/// Coordinates use the 64×64 master viewBox; the shape is scaled to fit
/// whatever `.frame` is applied.
struct BentoMark: View {
    enum Density {
        /// Full thickness — for popovers, app icon, anything ≥24pt.
        case regular
        /// Slimmer strokes that survive at 16pt (menu bar).
        case compact
    }

    var density: Density = .regular
    var color: Color = Theme.Brand.primary

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 64.0
            ZStack {
                BentoFrameShape()
                    .stroke(color, style: strokeStyle(width: frameStroke * scale))
                BentoMShape()
                    .stroke(color, style: strokeStyle(width: mStroke * scale))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var frameStroke: CGFloat { density == .regular ? 3 : 5 }
    private var mStroke:     CGFloat { density == .regular ? 5 : 6.4 }

    private func strokeStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

private struct BentoFrameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(14, 6))
        path.addLine(to: p(50, 6))
        path.addQuadCurve(to: p(58, 14), control: p(58, 6))
        path.addLine(to: p(58, 26))
        path.addLine(to: p(53, 26))
        path.addLine(to: p(53, 32))
        path.addLine(to: p(58, 32))
        path.addLine(to: p(58, 50))
        path.addQuadCurve(to: p(50, 58), control: p(58, 58))
        path.addLine(to: p(14, 58))
        path.addQuadCurve(to: p(6, 50), control: p(6, 58))
        path.addLine(to: p(6, 14))
        path.addQuadCurve(to: p(14, 6), control: p(6, 6))
        path.closeSubpath()
        return path
    }
}

private struct BentoMShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(18, 42))
        path.addLine(to: p(18, 22))
        path.addLine(to: p(32, 32))
        path.addLine(to: p(46, 22))
        path.addLine(to: p(46, 42))
        return path
    }
}

#Preview("Regular (popover header)") {
    BentoMark(density: .regular)
        .frame(width: 32, height: 32)
        .padding()
}

#Preview("Compact (menu bar)") {
    BentoMark(density: .compact, color: .primary)
        .frame(width: 16, height: 16)
        .padding()
}
