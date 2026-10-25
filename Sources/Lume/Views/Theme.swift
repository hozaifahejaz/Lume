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

/// Light and airy: pastel light behind Liquid Glass, near-black rounded type, one calm blue.
enum Theme {
    static let ink = Color(hex: 0x1C1C1E)
    static let secondary = Color(hex: 0x3C3C43, opacity: 0.64)
    static let tertiary = Color(hex: 0x3C3C43, opacity: 0.36)

    static let accent = Color(hex: 0x0A84FF)
    static let warm = Color(hex: 0xFF9F0A)
    static let hot = Color(hex: 0xFF453A)

    /// Base hues for the processor, memory and disk rings.
    static let cpuHue = accent
    static let memoryHue = Color(hex: 0x5E5CE6)
    static let diskHue = Color(hex: 0x30B0C7)

    static let sky = Color(hex: 0xBFD8FF)
    static let lilac = Color(hex: 0xE3D5FF)
    static let mint = Color(hex: 0xCFF3E6)
    static let peach = Color(hex: 0xFFE1CC)

    /// Deeper pastels for data so segments stay readable on glass.
    static let palette: [Color] = ([0x7FB2FF, 0xB59BFF, 0x6FD6B0, 0xFFB27F, 0xFF9DBE, 0xF2CF5B, 0x8AD3E6, 0xC4B8A8] as [UInt32])
        .map { Color(hex: $0) }

    static let radius: CGFloat = 28
    static let gutter: CGFloat = 40
    static let column: CGFloat = 780

    static func number(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let label = Font.system(size: 12, weight: .medium, design: .rounded)
    static let body = Font.system(size: 13, design: .rounded)

    /// Blue while there is headroom, orange past 70%, red past 90%.
    static func tint(for fraction: Double, base: Color = accent) -> Color {
        if fraction >= 0.9 { return hot }
        if fraction >= 0.7 { return warm }
        return base
    }
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
                .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
            }
        }
    }

    /// Glass capsule buttons, with the tinted variant for the primary action.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// A large rounded glass panel that content sits on.
struct GlassSlab<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// A pale sky-to-lilac field with slow pastel light drifting across it, for the glass to refract.
struct Backdrop: View {
    var body: some View {
        ZStack {
            base
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: false)) { timeline in
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
                    Color(hex: 0xEAF3FF), Color(hex: 0xF5F3FF), Color(hex: 0xF1EAFF),
                    Color(hex: 0xEDF6FF), Color(hex: 0xFBFBFF), Color(hex: 0xF5EEFF),
                    Color(hex: 0xEDFBF5), Color(hex: 0xFFF7F0), Color(hex: 0xFFF0E6),
                ]
            )
        } else {
            LinearGradient(
                colors: [Color(hex: 0xEAF3FF), Color(hex: 0xFBFBFF), Color(hex: 0xFFF0E6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private func blob(_ color: Color, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.rounded(32, .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(Theme.rounded(14)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.13)))
    }
}

/// Soft fade with a slight lift and scale, used between pages.
struct LiftFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? 0.985 : 1)
            .offset(y: active ? 10 : 0)
    }
}

extension AnyTransition {
    static var liftFade: AnyTransition {
        .modifier(active: LiftFade(active: true), identity: LiftFade(active: false))
    }
}

extension SystemMonitor {
    var load: Double { max(cpu, memory.fraction, disk.fraction) }

    var mood: String {
        switch load {
        case ..<0.7: return "All good"
        case ..<0.9: return "Busy"
        default: return "Running hot"
        }
    }
}

extension Int64 {
    var bytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
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
