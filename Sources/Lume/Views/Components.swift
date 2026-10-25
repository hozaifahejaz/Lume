import SwiftUI

/// Concentric gradient rings, outer to inner, each filling clockwise from the top.
struct RingGauge: View {
    let values: [Double]
    let hues: [Color]
    var lineWidth: CGFloat = 13
    var gap: CGFloat = 7

    var body: some View {
        ZStack {
            ForEach(values.indices, id: \.self) { index in
                let value = min(max(values[index], 0), 1)
                let tint = Theme.tint(for: value, base: hues[index % hues.count])
                ZStack {
                    Circle().stroke(Theme.ink.opacity(0.06), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: max(0.002, value))
                        .stroke(
                            AngularGradient(colors: [tint.opacity(0.45), tint], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(value, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.3), radius: 5)
                }
                .padding(CGFloat(index) * (lineWidth + gap) + lineWidth / 2)
                .animation(.smooth(duration: 0.8), value: value)
            }
        }
    }
}

/// A single small ring with its percentage in the middle.
struct MiniRing: View {
    let fraction: Double
    let label: String
    let hue: Color

    var body: some View {
        let tint = Theme.tint(for: fraction, base: hue)
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.07), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.002, min(fraction, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Theme.number(14, .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 62, height: 62)
            Text(label).font(Theme.label).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A thin line with a soft fill beneath, for a rolling history of values in 0...1.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// A slim rounded proportion bar.
struct SlimBar: View {
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                Capsule().fill(tint.gradient)
                    .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.smooth, value: fraction)
    }
}

/// Row hover: a faint white wash and a tiny lift.
struct HoverLift: ViewModifier {
    @StateObject private var hover = ViewState(false)

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(hover.value ? 0.55 : 0))
                    .shadow(color: .black.opacity(hover.value ? 0.05 : 0), radius: 8, y: 3)
            )
            .scaleEffect(hover.value ? 1.006 : 1)
            .contentShape(Rectangle())
            .onHover { hover.value = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hover.value)
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}
