import SwiftUI
import AppKit

struct StorageView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var scanner: StorageScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Storage", subtitle: "Where your space is going.") {
                Button { Task { await scanner.scan() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(scanner.isScanning)
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(monitor.disk.used.bytes).font(Theme.number(40))
                        Text("used of \(monitor.disk.total.bytes)")
                            .font(Theme.subtitle).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(monitor.disk.available.bytes) available")
                            .font(Theme.label).foregroundStyle(.secondary)
                    }
                    UsageBar(fraction: monitor.disk.fraction, tint: Theme.tint(for: monitor.disk.fraction))
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Largest folders").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if scanner.isScanning {
                            ProgressView(value: scanner.progress)
                                .progressViewStyle(.linear)
                                .frame(width: 120)
                        }
                    }
                    .padding(.bottom, 10)

                    if scanner.folders.isEmpty && !scanner.isScanning {
                        Text("Nothing measured yet.").font(Theme.subtitle).foregroundStyle(.secondary)
                    }

                    let largest = scanner.folders.first?.size ?? 1
                    ForEach(scanner.folders) { folder in
                        FolderRow(folder: folder, fraction: Double(folder.size) / Double(max(largest, 1)))
                    }
                }
            }
        }
        .task { if scanner.folders.isEmpty && !scanner.isScanning { await scanner.scan() } }
    }
}

private struct FolderRow: View {
    let folder: FolderUsage
    let fraction: Double
    @StateObject private var hoverState = ViewState(false)
    private var hovering: Bool {
        get { hoverState.value }
        nonmutating set { hoverState.value = newValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(folder.name)
                .font(.system(size: 13))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            UsageBar(fraction: fraction)
            Text(folder.size.bytes)
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            } label: {
                Image(systemName: "arrow.up.forward.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hovering ? 0.04 : 0)))
        .onHover { hovering = $0 }
    }
}
