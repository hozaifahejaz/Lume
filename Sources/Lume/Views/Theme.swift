import SwiftUI

/// A deliberately small design system: one accent, two text weights, generous space.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.55, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.38)
    static let calm = Color(red: 0.36, green: 0.82, blue: 0.66)

    static let radius: CGFloat = 18
    static let gutter: CGFloat = 28

    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded).monospacedDigit()
    }

    static let label = Font.system(size: 12, weight: .medium)
    static let title = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let subtitle = Font.system(size: 13)

    /// Picks a tint that shifts from calm to warm as a resource fills up.
    static func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return calm
        case ..<0.85: return accent
        default: return warm
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(.background.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06))
            )
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.title)
                Text(subtitle).font(Theme.subtitle).foregroundStyle(.secondary)
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

struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary.opacity(0.07)))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
