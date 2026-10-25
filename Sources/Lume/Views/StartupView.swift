import SwiftUI

struct StartupView: View {
    @ObservedObject var items: StartupItems

    var body: some View {
        let user = items.items.filter(\.isUserScope)
        let system = items.items.filter { !$0.isUserScope }

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Startup", subtitle: "Background helpers that launch when you log in.") {
                Button("Login Items…") { items.openLoginItemsSettings() }
                    .glassButton()
            }

            group("Yours", note: "Turning one off moves its file aside. Turn it back on any time.", rows: user)
            if !system.isEmpty {
                group("System-wide", note: "Installed for all users. Managed in System Settings.", rows: system)
            }
        }
        .animation(.smooth(duration: 0.4), value: items.items)
        .onAppear { items.reload() }
    }

    private func group(_ title: String, note: String, rows: [StartupItem]) -> some View {
        GlassSlab(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(17, .semibold)).foregroundStyle(Theme.ink)
                    Text(note).font(Theme.label).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                if rows.isEmpty {
                    Text("Nothing here. Nice and quiet.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondary)
                        .padding(12)
                }
                ForEach(rows) { item in
                    StartupRow(item: item, items: items)
                }
            }
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    @ObservedObject var items: StartupItems

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "gearshape", tint: item.isEnabled ? Theme.accent : Theme.ink.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName.capitalized)
                    .font(Theme.rounded(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(item.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { items.reveal(item) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

            if item.isUserScope {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { items.setEnabled(item, $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
            } else {
                Text("System")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.ink.opacity(0.06)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(item.isUserScope ? (item.isEnabled ? 1 : 0.6) : 0.6)
        .hoverLift()
    }
}
