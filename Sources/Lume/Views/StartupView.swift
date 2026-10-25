import SwiftUI

struct StartupView: View {
    @ObservedObject var items: StartupItems

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Startup", subtitle: "Background helpers that launch when you log in.") {
                Button("Login Items…") { items.openLoginItemsSettings() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }

            let user = items.items.filter(\.isUserScope)
            let system = items.items.filter { !$0.isUserScope }

            group(title: "Yours", subtitle: "Pausing moves the file aside. Turn it back on any time.", rows: user)
            if !system.isEmpty {
                group(title: "System-wide", subtitle: "Installed for all users. Managed in System Settings.", rows: system)
            }
        }
        .onAppear { items.reload() }
    }

    @ViewBuilder
    private func group(title: String, subtitle: String, rows: [StartupItem]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(Theme.label).foregroundStyle(.secondary).padding(.bottom, 10)

                if rows.isEmpty {
                    Text("Nothing here. Nice and quiet.")
                        .font(Theme.subtitle).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 48) }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "gearshape", tint: item.isEnabled ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName.capitalized).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.label).font(Theme.label).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { items.reveal(item) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show in Finder")

            if item.isUserScope {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { items.setEnabled(item, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
        .padding(.vertical, 10)
        .opacity(item.isEnabled ? 1 : 0.6)
    }
}
