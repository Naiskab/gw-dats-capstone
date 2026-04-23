import SwiftUI

struct RideShiftLogoView: View {
    var body: some View {
        ZStack {
            PinShape()
                .fill(.white)

            RoadCutShape()
                .fill(.black)

            Image(systemName: "car.fill")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(.black)
                .offset(y: -16)
        }
    }
}

private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        let circleRect = CGRect(x: w * 0.1, y: h * 0.05, width: w * 0.8, height: h * 0.8)
        path.addEllipse(in: circleRect)

        path.move(to: CGPoint(x: w * 0.5, y: h * 0.98))
        path.addLine(to: CGPoint(x: w * 0.24, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.66))
        path.closeSubpath()

        return path
    }
}

private struct RoadCutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: w * 0.37, y: h * 0.56))
        path.addCurve(
            to: CGPoint(x: w * 0.66, y: h * 0.7),
            control1: CGPoint(x: w * 0.56, y: h * 0.55),
            control2: CGPoint(x: w * 0.68, y: h * 0.6)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.98),
            control1: CGPoint(x: w * 0.65, y: h * 0.85),
            control2: CGPoint(x: w * 0.5, y: h * 0.92)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.88),
            control1: CGPoint(x: w * 0.35, y: h * 1.02),
            control2: CGPoint(x: w * 0.3, y: h * 0.96)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.7),
            control1: CGPoint(x: w * 0.37, y: h * 0.83),
            control2: CGPoint(x: w * 0.5, y: h * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.3, y: h * 0.6),
            control1: CGPoint(x: w * 0.45, y: h * 0.64),
            control2: CGPoint(x: w * 0.35, y: h * 0.61)
        )
        path.closeSubpath()

        return path
    }
}
