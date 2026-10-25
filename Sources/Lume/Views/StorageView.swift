import SwiftUI
import AppKit

struct StorageView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var scanner: StorageScanner

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: "\(monitor.disk.used.bytes) used of \(monitor.disk.total.bytes)",
                       subtitle: "\(monitor.disk.available.bytes) available") {
                Button { Task { await scanner.scan() } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .glassButton()
                .disabled(scanner.isScanning)
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 16) {
                    UsageBar(total: monitor.disk.total, segments: scanner.isScanning ? nil : segments,
                             used: monitor.disk.used)
                    legend
                }
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Largest folders").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                        Spacer()
                        if scanner.isScanning {
                            ProgressView(value: scanner.progress)
                                .progressViewStyle(.linear)
                                .tint(Theme.graphite)
                                .frame(width: 120)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)

                    if scanner.folders.isEmpty && !scanner.isScanning {
                        Text("Nothing measured yet.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.secondary)
                            .padding(8)
                    }

                    // Hugs its rows, and drops the smallest ones if the window is short.
                    FittingRows(items: scanner.folders, rowHeight: 36) { folder in
                        FolderRow(folder: folder, first: folder.id == scanner.folders.first?.id)
                    }
                    .frame(maxHeight: CGFloat(scanner.folders.count) * 36)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.smooth(duration: 0.5), value: scanner.folders)
        .task { if scanner.folders.isEmpty && !scanner.isScanning { await scanner.scan() } }
    }

    /// The largest folders that are at least 3% of the disk, then "System & other" for the
    /// rest of the used space, so the segments add up exactly to what the disk reports as used.
    private var segments: [UsageSegment] {
        let used = max(monitor.disk.used, 0)
        let threshold = Double(monitor.disk.total) * 0.03
        var shown: [UsageSegment] = []
        var sum: Int64 = 0
        for folder in scanner.folders where Double(folder.size) >= threshold && shown.count < 4 {
            shown.append(UsageSegment(name: folder.name, size: folder.size,
                                      color: Theme.storageTones[shown.count]))
            sum += folder.size
        }
        // Never negative: if the folders somehow add up to more than "used", the bar scales to their sum.
        shown.append(UsageSegment(name: "System & other", size: max(0, used - sum), color: Theme.storageOther))
        return shown
    }

    private var legend: some View {
        let items = scanner.isScanning
            ? [UsageSegment(name: "Used", size: monitor.disk.used, color: Theme.graphite.opacity(0.45))]
            : segments
        return FlowRow(spacing: 24, lineSpacing: 8) {
            ForEach(items) { segment in
                legendItem(segment.name, segment.size, Circle().fill(segment.color))
            }
            legendItem("Free", monitor.disk.available,
                       Circle().fill(Theme.track).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5)))
        }
    }

    private func legendItem<Dot: View>(_ name: String, _ size: Int64, _ dot: Dot) -> some View {
        HStack(spacing: 8) {
            dot.frame(width: 8, height: 8)
            Text(name).font(Theme.body).foregroundStyle(Theme.ink).lineLimit(1)
            Text(size.bytes).font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }
}

struct UsageSegment: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let size: Int64
    let color: Color
}

/// The disk as one capsule: the filled part is exactly used / total, split into muted segments
/// with 1pt gaps; free space is the plain track. While scanning, one neutral fill.
private struct UsageBar: View {
    let total: Int64
    let segments: [UsageSegment]?
    let used: Int64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = max(used, segments?.reduce(0) { $0 + $1.size } ?? used)
            let usedWidth = width * CGFloat(min(1, Double(filled) / Double(max(total, 1))))
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track)
                if let segments {
                    let gaps = CGFloat(segments.count)
                    HStack(spacing: 1) {
                        ForEach(segments) { segment in
                            Rectangle()
                                .fill(segment.color)
                                .frame(width: max(1, max(0, usedWidth - gaps) * CGFloat(Double(segment.size) / Double(max(filled, 1)))))
                        }
                    }
                } else {
                    Rectangle().fill(Theme.graphite.opacity(0.45)).frame(width: usedWidth)
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.6), value: segments)
    }
}

private struct FolderRow: View {
    let folder: FolderUsage
    let first: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: NSWorkspace.shared.icon(forFile: folder.url.path))
            Text(folder.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text(folder.size.bytes)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !first { Hairline().padding(.leading, 32) }
        }
        .hoverWash()
    }
}

/// Lays items out left to right and wraps onto a new line when they run out of room.
private struct FlowRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
