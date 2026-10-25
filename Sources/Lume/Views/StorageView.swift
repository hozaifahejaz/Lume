import SwiftUI
import AppKit

struct StorageView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var scanner: StorageScanner

    private var segmentCount: Int { Theme.palette.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Storage", subtitle: "Where your space is going.") {
                Button { Task { await scanner.scan() } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .glassButton()
                .disabled(scanner.isScanning)
            }

            GlassSlab(padding: 28) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 40) {
                        figure(monitor.disk.used.bytes, "Used of \(monitor.disk.total.bytes)")
                        figure(monitor.disk.available.bytes, "Available")
                        Spacer()
                    }
                    segmentBar
                }
            }

            GlassSlab(padding: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Largest folders").font(Theme.rounded(17, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        if scanner.isScanning {
                            ProgressView(value: scanner.progress)
                                .progressViewStyle(.linear)
                                .tint(Theme.accent)
                                .frame(width: 120)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if scanner.folders.isEmpty && !scanner.isScanning {
                        Text("Nothing measured yet.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.secondary)
                            .padding(12)
                    }

                    ForEach(Array(scanner.folders.enumerated()), id: \.element.id) { index, folder in
                        FolderRow(folder: folder, color: color(index))
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: scanner.folders)
        .task { if scanner.folders.isEmpty && !scanner.isScanning { await scanner.scan() } }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.number(56))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label).font(Theme.label).foregroundStyle(Theme.secondary)
        }
    }

    /// The largest folders as pastel segments of the whole disk.
    private var segmentBar: some View {
        GeometryReader { geo in
            let total = Double(max(monitor.disk.total, 1))
            let shown = Array(scanner.folders.prefix(segmentCount))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, folder in
                        Rectangle()
                            .fill(color(index).gradient)
                            .frame(width: max(3, geo.size.width * Double(folder.size) / total))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 14)
    }

    private func color(_ index: Int) -> Color {
        index < segmentCount ? Theme.palette[index] : Theme.ink.opacity(0.15)
    }
}

private struct FolderRow: View {
    let folder: FolderUsage
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10)
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(folder.name)
                .font(Theme.rounded(15, .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer()
            Text(folder.size.bytes)
                .font(Theme.number(13, .medium))
                .foregroundStyle(Theme.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            } label: {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .hoverLift()
    }
}
