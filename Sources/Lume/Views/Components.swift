import SwiftUI

/// A luminous sphere that breathes slowly; its glow follows `load`.
struct Orb: View {
    let load: Double
    var size: CGFloat = 220

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = sin(t * .pi * 2 / 4)
            let tint = Theme.tint(for: load)
            let glow = 0.35 + 0.65 * min(max(load, 0), 1)

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [tint.opacity(0.28 * glow), tint.opacity(0.06 * glow), .clear],
                        center: .center, startRadius: size * 0.35, endRadius: size
                    ))
                    .frame(width: size * 2, height: size * 2)
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.bone.opacity(0.95), tint, tint.opacity(0.55), tint.opacity(0.15)],
                        center: UnitPoint(x: 0.4, y: 0.34), startRadius: 0, endRadius: size * 0.66
                    ))
                    .frame(width: size, height: size)
                    .shadow(color: tint.opacity(0.6 * glow), radius: size * 0.18)
                    .shadow(color: tint.opacity(0.35 * glow), radius: size * 0.09)
            }
            .scaleEffect(1 + 0.03 * breath)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// Thin concentric arcs, inner to outer, each filling clockwise from the top.
struct LoadArcs: View {
    let values: [Double]
    let diameter: CGFloat
    var spacing: CGFloat = 26

    var body: some View {
        ZStack {
            ForEach(values.indices, id: \.self) { index in
                let value = min(max(values[index], 0), 1)
                let tint = Theme.tint(for: value)
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: max(0.004, value))
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .shadow(color: tint.opacity(0.8), radius: 6)
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.8), value: value)
                }
                .frame(
                    width: diameter + CGFloat(index) * spacing * 2,
                    height: diameter + CGFloat(index) * spacing * 2
                )
            }
        }
    }
}

/// A thin glowing line for a rolling history of values in 0...1.
struct GlowLine: View {
    let values: [Double]
    var tint: Color = Theme.amber

    var body: some View {
        GeometryReader { geo in
            let path = Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            ZStack {
                path.stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .blur(radius: 6)
                path.stroke(tint, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// A one-point proportion line with a soft glow on the filled part.
struct HairlineBar: View {
    let fraction: Double
    var tint: Color = Theme.amber

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.hairline)
                Rectangle().fill(tint)
                    .frame(width: max(1, geo.size.width * min(max(fraction, 0), 1)))
                    .shadow(color: tint.opacity(0.7), radius: 4)
            }
        }
        .frame(height: 1)
        .animation(.smooth, value: fraction)
    }
}
