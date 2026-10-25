import SwiftUI
import AppKit

struct StorageView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var scanner: StorageScanner

    private let segmentCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "Storage", title: "Where your space lives.") {
                Button("Measure again") { Task { await scanner.scan() } }
                    .buttonStyle(MonoButtonStyle())
                    .disabled(scanner.isScanning)
                    .opacity(scanner.isScanning ? 0.4 : 1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 56) {
                figure(monitor.disk.used.bytes, "Used of \(monitor.disk.total.bytes)",
                       tint: monitor.disk.fraction > 0.85 ? Theme.coral : Theme.bone)
                figure(monitor.disk.available.bytes, "Available", tint: Theme.bone)
                Spacer()
            }
            .padding(.top, 48)

            segmentBar.padding(.top, 36)

            HStack {
                Text(scanner.isScanning ? "Measuring · \(Int(scanner.progress * 100))%" : "Largest folders")
                    .monoLabel()
                Spacer()
                Text("Home and Applications").monoLabel(Theme.bone.opacity(0.3), size: 9)
            }
            .padding(.top, 56)
            .padding(.bottom, 14)
            Hairline()

            if scanner.folders.isEmpty && !scanner.isScanning {
                Text("Nothing measured yet.")
                    .font(Theme.serif(17).italic())
                    .foregroundStyle(Theme.boneDim)
                    .padding(.vertical, 18)
            }

            ForEach(Array(scanner.folders.enumerated()), id: \.element.id) { index, folder in
                FolderRow(folder: folder, opacity: segmentOpacity(index))
                Hairline()
            }
        }
        .animation(.smooth(duration: 0.5), value: scanner.folders)
        .task { if scanner.folders.isEmpty && !scanner.isScanning { await scanner.scan() } }
    }

    private func figure(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(Theme.serif(56).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).monoLabel()
        }
    }

    /// The largest folders as amber segments of the whole disk, fading with rank.
    private var segmentBar: some View {
        GeometryReader { geo in
            let total = Double(max(monitor.disk.total, 1))
            let shown = Array(scanner.folders.prefix(segmentCount))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, folder in
                        Rectangle()
                            .fill(Theme.amber.opacity(segmentOpacity(index)))
                            .frame(width: max(2, geo.size.width * Double(folder.size) / total))
                    }
                }
                .clipShape(Capsule())
                .shadow(color: Theme.amber.opacity(0.35), radius: 10)
            }
        }
        .frame(height: 8)
    }

    private func segmentOpacity(_ index: Int) -> Double {
        guard index < segmentCount else { return 0.12 }
        return 1 - Double(index) * 0.75 / Double(segmentCount - 1)
    }
}

private struct FolderRow: View {
    let folder: FolderUsage
    let opacity: Double
    @StateObject private var hoverState = ViewState(false)

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.amber.opacity(opacity))
                .frame(width: 7, height: 7)
                .shadow(color: Theme.amber.opacity(opacity * 0.6), radius: 4)
            Text(folder.name)
                .font(Theme.serif(17, .regular))
                .foregroundStyle(Theme.bone)
                .lineLimit(1)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            } label: {
                Text("Reveal ↗").monoLabel(Theme.amber, size: 9.5)
            }
            .buttonStyle(.plain)
            .opacity(hoverState.value ? 1 : 0)
            Text(folder.size.bytes)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.boneDim)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hoverState.value = $0 }
        .animation(.smooth(duration: 0.2), value: hoverState.value)
    }
}
