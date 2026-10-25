import SwiftUI

struct StartupView: View {
    @ObservedObject var items: StartupItems

    var body: some View {
        let user = items.items.filter(\.isUserScope)
        let system = items.items.filter { !$0.isUserScope }

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "Startup", title: "What wakes with your Mac.") {
                Button("Login Items ↗") { items.openLoginItemsSettings() }
                    .buttonStyle(MonoButtonStyle())
            }
            Text("Pausing one of yours moves its file aside. Turn it back on any time.")
                .font(Theme.body)
                .foregroundStyle(Theme.boneDim)
                .padding(.top, 14)

            group("Yours", rows: user)
            if !system.isEmpty {
                group("System-wide", rows: system)
            }
        }
        .animation(.smooth(duration: 0.4), value: items.items)
        .onAppear { items.reload() }
    }

    @ViewBuilder
    private func group(_ title: String, rows: [StartupItem]) -> some View {
        HStack {
            Text(title).monoLabel()
            Spacer()
            Text("\(rows.count)").monoLabel(Theme.bone.opacity(0.3))
        }
        .padding(.top, 52)
        .padding(.bottom, 12)
        Hairline()

        if rows.isEmpty {
            Text("Nothing here. Nice and quiet.")
                .font(Theme.serif(17).italic())
                .foregroundStyle(Theme.boneDim)
                .padding(.vertical, 18)
        }
        ForEach(rows) { item in
            StartupRow(item: item, items: items)
            Hairline()
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    @ObservedObject var items: StartupItems
    @StateObject private var hoverState = ViewState(false)

    var body: some View {
        HStack(spacing: 16) {
            if item.isUserScope {
                GlowToggle(isOn: item.isEnabled) { items.setEnabled(item, !item.isEnabled) }
            } else {
                Circle()
                    .strokeBorder(Theme.bone.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 16, height: 16)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName.capitalized)
                    .font(Theme.serif(17, .regular))
                    .foregroundStyle(Theme.bone)
                    .lineLimit(1)
                Text(item.label)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.boneDim)
                    .lineLimit(1)
            }
            Spacer()
            Button { items.reveal(item) } label: {
                Text("Reveal ↗").monoLabel(Theme.amber, size: 9.5)
            }
            .buttonStyle(.plain)
            .opacity(hoverState.value ? 1 : 0)
            if !item.isUserScope {
                Text("System")
                    .monoLabel(size: 9)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            }
        }
        .padding(.vertical, 8)
        .opacity(item.isUserScope ? (item.isEnabled ? 1 : 0.5) : 0.55)
        .contentShape(Rectangle())
        .onHover { hoverState.value = $0 }
        .animation(.smooth(duration: 0.2), value: hoverState.value)
    }
}
