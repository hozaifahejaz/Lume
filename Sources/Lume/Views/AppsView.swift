import SwiftUI
import AppKit

/// Remove an app with the files it keeps in your Library, and tidy data left by apps already gone.
struct AppsView: View {
    @ObservedObject var uninstaller: Uninstaller
    @ObservedObject var leftovers: Leftovers

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: "Apps") {
                Button("Choose App…") { uninstaller.chooseApp() }
                    .glassButton()
            }

            HStack(alignment: .top, spacing: Theme.gap) {
                GlassPanel { UninstallPanel(uninstaller: uninstaller) }
                GlassPanel { LeftoversPanel(leftovers: leftovers) }
            }
        }
    }
}

private struct UninstallPanel: View {
    @ObservedObject var uninstaller: Uninstaller
    @StateObject private var targeted = ViewState(false)
    @StateObject private var confirming = ViewState(false)

    var body: some View {
        Group {
            if let app = uninstaller.app {
                detail(app)
            } else {
                dropZone
            }
        }
        // The whole panel takes a dropped app, whichever state it's in.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension == "app" }) else { return false }
            uninstaller.load(url)
            return true
        } isTargeted: { targeted.value = $0 }
        .animation(.smooth(duration: 0.3), value: uninstaller.app)
        .animation(.smooth(duration: 0.3), value: uninstaller.files)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(targeted.value ? Theme.accent : Theme.tertiary)
            Text("Drop an app here").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
            if let message = uninstaller.message {
                Text(message).font(Theme.caption).foregroundStyle(Theme.secondary).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(targeted.value ? Theme.accent.opacity(0.6) : Theme.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accent.opacity(targeted.value ? 0.05 : 0))
                )
        )
    }

    private func detail(_ app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AppIconView(image: AppIcons.forFile(app.url.path), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                    Text(summary(app)).font(Theme.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { uninstaller.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .help("Choose another app")
                .accessibilityLabel("Choose another app")
            }
            .padding(.horizontal, 8)

            if app.refusal == nil {
                Hairline().padding(.top, 4)
                if uninstaller.files.isEmpty && uninstaller.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finding its files…").font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                    .padding(8)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(uninstaller.files) { file in
                            row(file, app: app).frame(height: 40)
                        }
                    }
                }
                .quietScroll()
            } else {
                Spacer(minLength: 0)
            }

            footer(app)
        }
        .confirmationDialog("Move \(app.name) and its files to the Trash?", isPresented: $confirming.value) {
            Button("Move to Trash", role: .destructive) { Task { await uninstaller.trashSelected() } }
        } message: {
            Text("\(app.name) quits first if it’s open.")
        }
    }

    private func summary(_ app: AppInfo) -> String {
        var parts: [String] = []
        if let version = app.version { parts.append("Version \(version)") }
        if !uninstaller.files.isEmpty {
            let total = uninstaller.files.reduce(0) { $0 + $1.size }
            parts.append("\(total.bytes) with its files")
        }
        return parts.joined(separator: " · ")
    }

    private func footer(_ app: AppInfo) -> some View {
        HStack(spacing: 12) {
            Text(footnote(app))
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Spacer()
            if app.refusal == nil {
                Button("Move to Trash…") { confirming.value = true }
                    .glassButton()
                    .disabled(uninstaller.selected.isEmpty || uninstaller.isWorking)
            }
        }
        .padding(.horizontal, 8)
    }

    private func footnote(_ app: AppInfo) -> String {
        if let message = uninstaller.message { return message }
        if uninstaller.isWorking || uninstaller.files.isEmpty { return "" }
        return "\(uninstaller.selected.count) of \(uninstaller.files.count) selected · \(uninstaller.selectedSize.bytes)"
    }

    private func row(_ file: SweepFile, app: AppInfo) -> some View {
        let isOn = Binding(
            get: { uninstaller.selected.contains(file.url) },
            set: { on in
                if on { uninstaller.selected.insert(file.url) } else { uninstaller.selected.remove(file.url) }
            }
        )
        return HStack(spacing: 12) {
            Toggle(file.name, isOn: isOn).toggleStyle(.checkbox).labelsHidden()
            AppIconView(image: AppIcons.forFile(file.url.path))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.url == app.url ? app.name : file.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(uninstaller.place(of: file) ?? "Application")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 12)
            Text(file.size.bytes).font(Theme.digits).foregroundStyle(Theme.secondary)
            RevealButton(url: file.url, name: file.name)
        }
        .frame(maxHeight: .infinity)
        .hoverWash()
        .onTapGesture { isOn.wrappedValue.toggle() }
    }
}

private struct LeftoversPanel: View {
    @ObservedObject var leftovers: Leftovers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Leftovers").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                    .help("Data from apps no longer on this Mac, untouched for a month")
                Spacer()
                if leftovers.isScanning { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)

            if leftovers.items.isEmpty {
                Text(leftovers.scanned ? "Nothing found" : "Looking…")
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
        return leftovers.result ?? ""
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
