import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Quiet and light: glass over a pale backdrop, near-black type, graphite data.
/// System blue is reserved for the primary action and the selected tab; red appears only past 85%.
enum Theme {
    static let ink = Color(hex: 0x1C1C1E)
    static let secondary = Color(hex: 0x3C3C43, opacity: 0.78)
    static let tertiary = Color(hex: 0x3C3C43, opacity: 0.5)
    static let graphite = Color(hex: 0x3A3A3C)
    static let hairline = Color.black.opacity(0.08)
    static let track = Color.black.opacity(0.06)

    static let accent = Color(hex: 0x0A84FF)
    static let alert = Color(hex: 0xFF453A, opacity: 0.85)

    /// Muted storage tones, darkest for the largest folder; the last is "System & other".
    static let storageTones: [Color] = [
        Color(hex: 0x3A3A3C), Color(hex: 0x636366), Color(hex: 0x8A96AA), Color(hex: 0xAEAEB2),
    ]
    static let storageOther = Color(hex: 0xC7C7CC)

    static let sky = Color(hex: 0xBFD8FF)
    static let lilac = Color(hex: 0xE3D5FF)
    static let mint = Color(hex: 0xCFF3E6)
    static let peach = Color(hex: 0xFFE1CC)

    // Geometry, on an 8pt grid
    static let margin: CGFloat = 32
    static let gap: CGFloat = 24
    static let panelPadding: CGFloat = 20
    static let panelRadius: CGFloat = 24
    static let rowIcon: CGFloat = 20
    static let tileSize: CGFloat = 28
    static let tileRadius: CGFloat = 7

    // Type scale
    static let headline = Font.system(size: 34, weight: .light)
    static let number = Font.system(size: 40, weight: .light, design: .rounded).monospacedDigit()
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let digits = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 12, weight: .medium)

    /// True once the percentage a person would read is above 85.
    static func isHigh(_ fraction: Double) -> Bool { (fraction * 100).rounded() > 85 }
}

// MARK: Glass

@available(macOS 26, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Liquid Glass on macOS 26 and later; a material with a soft edge highlight before that.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint) }
                    shape.stroke(Color.white.opacity(0.75), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
            }
        }
    }

    /// Glass capsule buttons.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Scrolling confined to a panel: no bounce when it fits, no indicators, no edge fade.
    @ViewBuilder
    func quietScroll() -> some View {
        let base = scrollIndicators(.never).scrollBounceBehavior(.basedOnSize)
        if #available(macOS 26, *) {
            base.scrollEdgeEffectHidden(true, for: .all)
        } else {
            base
        }
    }
}

/// A large rounded glass panel that content sits on.
struct GlassPanel<Content: View>: View {
    var fill = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.panelPadding)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .glass(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}

/// A pale sky-to-lilac field with slow pastel light drifting across it, for the glass to refract.
/// The drift is so slow (a cycle takes over a minute) that five frames a second looks continuous;
/// it stops entirely when the window isn't frontmost or Reduce Motion is on.
struct Backdrop: View {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            base
            TimelineView(.animation(minimumInterval: 1.0 / 5, paused: activeState != .key || reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        blob(Theme.sky, 640, w * (0.18 + 0.06 * sin(t / 9)), h * (0.22 + 0.05 * cos(t / 11)))
                        blob(Theme.lilac, 600, w * (0.86 + 0.05 * cos(t / 10)), h * (0.28 + 0.07 * sin(t / 13)))
                        blob(Theme.mint, 560, w * (0.24 + 0.07 * cos(t / 12)), h * (0.86 + 0.04 * sin(t / 8)))
                        blob(Theme.peach, 580, w * (0.8 + 0.06 * sin(t / 14)), h * (0.84 + 0.05 * cos(t / 10)))
                    }
                }
            }
            .opacity(0.7)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder private var base: some View {
        if #available(macOS 15, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                colors: [
                    Color(hex: 0xEDF3FC), Color(hex: 0xF5F4FA), Color(hex: 0xF2EEFA),
                    Color(hex: 0xF0F5FB), Color(hex: 0xFAFAFC), Color(hex: 0xF5F1FA),
                    Color(hex: 0xF0F8F5), Color(hex: 0xFAF7F3), Color(hex: 0xFAF2EC),
                ]
            )
        } else {
            LinearGradient(
                colors: [Color(hex: 0xEDF3FC), Color(hex: 0xFAFAFC), Color(hex: 0xFAF2EC)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private func blob(_ color: Color, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.8), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

/// Page headline: a calm sentence in large light type with one quiet line beneath.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            trailing
        }
        .animation(.smooth, value: title)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A small neutral glass tile holding a graphite SF Symbol.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = Theme.tileSize

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(Theme.graphite)
            .frame(width: size, height: size)
            .glass(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// A real app icon, or the neutral tile when there is no app behind it.
struct AppIconView: View {
    let image: NSImage?
    var size: CGFloat = Theme.rowIcon
    var fallback: String = "gearshape"

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            IconTile(symbol: fallback, size: size)
        }
    }
}

/// A 3pt capsule bar: graphite on a faint track, red past 85% (or when `alert` says so).
struct HairBar: View {
    let fraction: Double
    var alert: Bool? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(((alert ?? Theme.isHigh(fraction)) ? Theme.alert : Theme.graphite).opacity(0.7))
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .animation(.smooth, value: fraction)
    }
}

/// A 0.5pt divider in either direction.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

extension SystemMonitor {
    enum Load: Int, Comparable {
        case smooth, busy, heavy
        static func < (a: Load, b: Load) -> Bool { a.rawValue < b.rawValue }
    }

    /// How hard the Mac is working, from the processor and memory pressure only.
    /// A full disk or a high memory figure on its own doesn't slow anything down.
    var load: Load {
        let processor: Load = cpu < 0.7 ? .smooth : cpu < 0.85 ? .busy : .heavy
        let memory: Load = pressure == .normal ? .smooth : pressure == .warning ? .busy : .heavy
        return max(processor, memory)
    }

    var mood: String {
        switch load {
        case .smooth: return "Running smoothly"
        case .busy: return "Busy"
        case .heavy: return "Under heavy load"
        }
    }

    /// Under 10% free: the one point where disk space starts to matter for speed.
    var diskNearlyFull: Bool {
        disk.total > 0 && Double(disk.available) / Double(disk.total) < 0.1
    }
}

extension Double {
    /// A 0...1 fraction as a rounded percentage, the one formatter every screen uses.
    var percent: String { "\(Int((self * 100).rounded()))%" }
}

extension Int64 {
    /// Calm, decimal sizes: "106 GB", "19.8 GB", "400 MB", "0 KB".
    var bytes: String {
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(Swift.max(self, 0)) / 1000
        var index = 0
        while value >= 999.5 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let text = value >= 99.95 || value == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(text) \(units[index])"
    }
}

extension UInt64 {
    var bytes: String { Int64(clamping: self).bytes }
}

/// Local view state held in an ObservableObject. Stands in for `@State`, whose macro
/// plugin is missing from the Command Line Tools toolchain (it ships only with Xcode).
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
