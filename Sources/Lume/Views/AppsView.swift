import SwiftUI
import AppKit

/// Tidy data left by apps already gone.
struct AppsView: View {
    @ObservedObject var leftovers: Leftovers

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: "Apps",
                       subtitle: "Data in your Library from apps that are no longer on this Mac.")
            GlassPanel { LeftoversPanel(leftovers: leftovers) }
        }
    }
}

private struct LeftoversPanel: View {
    @ObservedObject var leftovers: Leftovers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Left behind by deleted apps").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                Spacer()
                if leftovers.isScanning { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)

            if leftovers.items.isEmpty {
                Text(leftovers.scanned ? "Nothing left behind by apps you’ve deleted." : "Looking…")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    .padding(8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(leftovers.items) { item in
                            row(item, first: item.id == leftovers.items.first?.id).frame(height: 40)
                        }
                    }
                }
                .quietScroll()
            }

            HStack(spacing: 12) {
                Text(footnote)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Move to Trash") { Task { await leftovers.trashSelected() } }
                    .glassButton()
                    .disabled(leftovers.selected.isEmpty)
            }
            .padding(.horizontal, 8)
            .opacity(leftovers.items.isEmpty && leftovers.result == nil ? 0 : 1)
        }
        .animation(.smooth(duration: 0.35), value: leftovers.items)
        .task { if !leftovers.scanned { await leftovers.scan() } }
    }

    private var footnote: String {
        if !leftovers.selected.isEmpty {
            return "\(leftovers.selected.count) selected · \(leftovers.selectedSize.bytes)"
        }
        if let result = leftovers.result { return result }
        return "Only data no app on this Mac uses, untouched for a month."
    }

    private func row(_ item: Leftover, first: Bool) -> some View {
        let isOn = Binding(
            get: { leftovers.selected.contains(item.id) },
            set: { on in
                leftovers.clearResult()
                if on { leftovers.selected.insert(item.id) } else { leftovers.selected.remove(item.id) }
            }
        )
        return HStack(spacing: 12) {
            Toggle(item.id, isOn: isOn).toggleStyle(.checkbox).labelsHidden()
            IconTile(symbol: "app.dashed", size: Theme.rowIcon)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.id)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.places.joined(separator: ", "))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 12)
            Text(item.size.bytes).font(Theme.digits).foregroundStyle(Theme.secondary)
            RevealButton(url: item.urls[0], name: item.id, others: Array(item.urls.dropFirst()))
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !first { Hairline().padding(.leading, 60) }
        }
        .hoverWash()
        .onTapGesture { isOn.wrappedValue.toggle() }
    }
}

/// The small magnifier that selects items in Finder.
struct RevealButton: View {
    let url: URL
    let name: String
    var others: [URL] = []

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url] + others)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .accessibilityLabel("Show \(name) in Finder")
    }
}
