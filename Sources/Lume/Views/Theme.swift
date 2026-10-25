import SwiftUI

/// "Light in the dark": deep ink, bone text, one warm luminous accent.
/// Serif for headings and numbers, tracked mono for labels.
enum Theme {
    static let ink = Color(red: 11 / 255, green: 11 / 255, blue: 16 / 255)
    static let bone = Color(red: 237 / 255, green: 232 / 255, blue: 223 / 255)
    static let boneDim = bone.opacity(0.45)
    static let amber = Color(red: 245 / 255, green: 194 / 255, blue: 107 / 255)
    static let coral = Color(red: 1, green: 122 / 255, blue: 89 / 255)
    static let hairline = Color.white.opacity(0.08)

    static let gutter: CGFloat = 56
    static let column: CGFloat = 760

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat = 10.5, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let body = Font.system(size: 13)

    /// Amber while there is headroom, coral once a resource passes 85%.
    static func tint(for fraction: Double) -> Color {
        fraction > 0.85 ? coral : amber
    }
}

extension View {
    /// The signature label: small uppercase mono with wide tracking.
    func monoLabel(_ color: Color = Theme.boneDim, size: CGFloat = 10.5) -> some View {
        font(Theme.mono(size))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }
}

/// Ink with a faint glow behind the content and a fixed field of grain.
struct Backdrop: View {
    var glow: Color = Theme.amber
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(
                colors: [glow.opacity(0.11 * intensity), glow.opacity(0.03 * intensity), .clear],
                center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 560
            )
            LinearGradient(
                colors: [Color.white.opacity(0.02), .clear, Color.black.opacity(0.3)],
                startPoint: .top, endPoint: .bottom
            )
            Grain()
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 1.2), value: intensity)
    }
}

/// Deterministic specks so the grain never shimmers when the view redraws.
struct Grain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 11) / Double(UInt64(1) << 53)
            }
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                context.fill(Path(rect), with: .color(.white.opacity(0.04 * next())))
            }
        }
        .allowsHitTesting(false)
    }
}

struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow).monoLabel(Theme.amber.opacity(0.85))
                Text(title).font(Theme.serif(38)).foregroundStyle(Theme.bone)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// A quiet outlined mono button.
struct MonoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoLabel(Theme.bone.opacity(configuration.isPressed ? 0.5 : 0.85), size: 10)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Capsule())
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small circle that fills and glows when on. Replaces system switches.
struct GlowToggle: View {
    let isOn: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(isOn ? Theme.amber : Theme.bone.opacity(0.28), lineWidth: 1)
                Circle().fill(Theme.amber)
                    .padding(3.5)
                    .scaleEffect(isOn ? 1 : 0.3)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .shadow(color: Theme.amber.opacity(isOn ? 0.75 : 0), radius: 8)
            .padding(8)
            .contentShape(Rectangle())
            .animation(.smooth(duration: 0.3), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

/// Soft opacity with a little blur and lift, used between pages.
struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 10 : 0)
            .offset(y: active ? 12 : 0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

extension SystemMonitor {
    /// Overall pressure, used for the orb's glow.
    var load: Double { max(cpu, memory.fraction) }

    var mood: String {
        switch max(cpu, memory.fraction, disk.fraction) {
        case ..<0.6: return "Everything is calm."
        case ..<0.85: return "Working, with room to spare."
        default: return "Running warm."
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
