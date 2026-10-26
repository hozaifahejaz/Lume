import SwiftUI

struct StartupView: View {
    @ObservedObject var items: StartupItems

    var body: some View {
        let user = items.items.filter(\.isUserScope)
        let system = items.items.filter { !$0.isUserScope }
        let enabled = items.items.filter(\.isEnabled).count

        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: "\(enabled) of \(items.items.count) helpers open at login") {
                Button { items.openLoginItemsSettings() } label: {
                    Label("Login Items", systemImage: "gearshape")
                }
                .glassButton()
            }

            GlassPanel(fill: false) {
                // The panel hugs its rows; only if they outgrow the window does the list scroll.
                let list = VStack(alignment: .leading, spacing: 0) {
                    section("Yours", rows: user)
                    if !system.isEmpty {
                        section("For all users", rows: system)
                            .padding(.top, 16)
                    }
                }
                ViewThatFits(in: .vertical) {
                    list
                    ScrollView { list }.quietScroll()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.smooth(duration: 0.4), value: items.items)
        .onAppear { items.reload() }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [StartupItem]) -> some View {
        Text(title)
            .font(Theme.sectionTitle)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .frame(height: 24)

        if rows.isEmpty {
            Text("None")
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .padding(8)
        }
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            if index > 0 { Hairline().padding(.leading, 48) }
            StartupRow(item: item, items: items)
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    @ObservedObject var items: StartupItems

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: AppIcons.forPath(item.program), size: Theme.tileSize)
                .saturation(item.isEnabled ? 1 : 0)
                .opacity(item.isEnabled ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(item.isEnabled ? Theme.ink : Theme.secondary)
                    .lineLimit(1)
                if let app = item.reenabledBy {
                    Text("Turned back on by \(app)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                } else {
                    Text(item.label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 16)
            Button { items.reveal(item) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel("Show \(item.displayName) in Finder")

            if item.isUserScope {
                Toggle(item.displayName, isOn: Binding(
                    get: { item.isEnabled },
                    set: { items.setEnabled(item, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.graphite)
                .disabled(items.busy.contains(item.url))
                .accessibilityLabel(item.displayName)
            } else {
                // /Library/LaunchAgents holds third-party helpers installed for every account.
                Text("All users")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(height: 52)
        .hoverWash()
    }
}
