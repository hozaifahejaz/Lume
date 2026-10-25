import SwiftUI

/// A thin progress ring with a large light numeral in the middle.
struct Ring: View {
    let fraction: Double
    let label: String
    let caption: String
    var size: CGFloat = 132

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.06), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.002, min(fraction, 1)))
                    .stroke(Theme.tint(for: fraction).gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: fraction)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(Theme.number(size * 0.3))
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(fraction * 100))
                    Text("%")
                        .font(.system(size: size * 0.11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            VStack(spacing: 3) {
                Text(label).font(.system(size: 13, weight: .semibold))
                Text(caption).font(Theme.label).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A soft area chart for a short rolling history of values in 0...1.
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
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))

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

/// A horizontal proportion bar used in lists.
struct UsageBar: View {
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.06))
                Capsule().fill(tint.gradient)
                    .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.smooth, value: fraction)
    }
}

struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
    }
}
