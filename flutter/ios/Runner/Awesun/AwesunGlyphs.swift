import SwiftUI

struct AwesunArcBand: Shape {
    let centerDeg: Double
    let spanDeg: Double
    let radius: CGFloat
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var centerline = Path()
        centerline.addRelativeArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(centerDeg - spanDeg),
            delta: .degrees(spanDeg * 2)
        )
        return centerline.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

struct AwesunKeyboardGlyph: View {
    var body: some View {
        VStack(spacing: 2.2) {
            ForEach([5, 4], id: \.self) { count in
                HStack(spacing: 2.2) {
                    ForEach(0..<count, id: \.self) { _ in
                        Circle().frame(width: 3.4, height: 3.4)
                    }
                }
            }
            Capsule().frame(width: 16, height: 2.2)
        }
    }
}

struct AwesunWheelGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width: CGFloat = 7
        var path = Path()
        for direction in [CGFloat(-1), CGFloat(1)] {
            let end = rect.midY + 3 * direction
            path.move(to: CGPoint(x: rect.midX - width, y: end))
            path.addLine(to: CGPoint(x: rect.midX, y: end + 6 * direction))
            path.addLine(to: CGPoint(x: rect.midX + width, y: end))
        }
        return path.strokedPath(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
    }
}
