import SwiftUI
import AppKit

/// Files with a checkbox each, and Move to Trash for the ones ticked. Scrolls inside its panel when long.
struct SweepList: View {
    @ObservedObject var sweep: FileSweep
    /// A quiet line after the name, such as "Last opened 8 months ago".
    let caption: (SweepFile) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sweep.files.isEmpty {
                HStack(spacing: 8) {
                    if sweep.isScanning || !sweep.scanned { ProgressView().controlSize(.small) }
                    Text(sweep.isScanning || !sweep.scanned ? "Looking…" : "Nothing found")
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sweep.files) { file in
                            row(file, first: file.id == sweep.files.first?.id).frame(height: 40)
                        }
                    }
                }
                .quietScroll()
            }
            footer
        }
        .animation(.smooth(duration: 0.35), value: sweep.files)
        .task { if !sweep.scanned { await sweep.scan() } }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Group {
                if !sweep.selected.isEmpty {
                    Text("\(sweep.selected.count) selected · \(sweep.selectedSize.bytes)")
                } else if let result = sweep.result {
                    Text(result)
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            Spacer()
            Button("Move to Trash") { Task { await sweep.trashSelected() } }
                .glassButton()
                .disabled(sweep.selected.isEmpty)
        }
        .padding(.horizontal, 8)
        .opacity(sweep.files.isEmpty && sweep.result == nil ? 0 : 1)
    }

    private func row(_ file: SweepFile, first: Bool) -> some View {
        let isOn = Binding(
            get: { sweep.selected.contains(file.url) },
            set: { on in
                sweep.clearResult()
                if on { sweep.selected.insert(file.url) } else { sweep.selected.remove(file.url) }
            }
        )
        return HStack(spacing: 12) {
            Toggle(file.name, isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            AppIconView(image: AppIcons.forFile(file.url.path))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption(file))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 16)
            Text(file.size.bytes)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel("Show \(file.name) in Finder")
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !first { Hairline().padding(.leading, 60) }
        }
        .hoverWash()
        .onTapGesture { isOn.wrappedValue.toggle() }
    }
}

extension Date {
    /// "8 months ago", "3 weeks ago".
    var ago: String { formatted(.relative(presentation: .named, unitsStyle: .wide)) }
}
