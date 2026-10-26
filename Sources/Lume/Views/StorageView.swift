import SwiftUI
import AppKit

/// What the lower panel lists.
enum StorageMode: String, CaseIterable {
    case folders = "Folders"
    case largeFiles = "Large Files"
    case downloads = "Downloads"
}

struct StorageView: View {
    @EnvironmentObject private var diskSpace: DiskSpace
    @ObservedObject var scanner: StorageScanner
    @ObservedObject var largeFiles: FileSweep
    @ObservedObject var downloads: FileSweep
    @ObservedObject var mode: ViewState<StorageMode>

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: "\(diskSpace.stats.used.bytes) used of \(diskSpace.stats.total.bytes)",
                       subtitle: "\(diskSpace.stats.available.bytes) available") {
                Button { Task { await rescan() } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .glassButton()
                .disabled(isScanning)
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 16) {
                    UsageBar(total: diskSpace.stats.total, segments: scanner.isScanning ? nil : segments,
                             used: diskSpace.stats.used)
                    legend
                }
            }

            GlassPanel(fill: mode.value != .folders) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        switch mode.value {
                        case .folders: Breadcrumbs(path: scanner.path) { scanner.goBack(to: $0) }
                        case .largeFiles: sectionTitle("Over 1 GB, not opened in six months")
                        case .downloads: sectionTitle("Installers and archives in Downloads, over 30 days old")
                        }
                        Spacer()
                        if scanner.isScanning && mode.value == .folders {
                            ProgressView(value: scanner.progress)
                                .progressViewStyle(.linear)
                                .tint(Theme.graphite)
                                .frame(width: 120)
                        }
                        Picker("Show", selection: $mode.value) {
                            ForEach(StorageMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)

                    switch mode.value {
                    case .folders: folderList
                    case .largeFiles:
                        SweepList(sweep: largeFiles,
                                  empty: "No files over 1 GB that you haven’t opened in six months.") { file in
                            file.date.map { "Last opened \($0.ago)" } ?? ""
                        }
                    case .downloads:
                        SweepList(sweep: downloads,
                                  empty: "No disk images, installers or archives older than 30 days in Downloads.") { file in
                            file.date.map { "Downloaded \($0.ago)" } ?? ""
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.smooth(duration: 0.5), value: scanner.folders)
        .animation(.smooth(duration: 0.35), value: scanner.path)
        .animation(.smooth(duration: 0.35), value: scanner.children)
        .task { if scanner.folders.isEmpty && !scanner.isScanning { await scanner.scan() } }
    }

    private var isScanning: Bool {
        switch mode.value {
        case .folders: return scanner.isScanning
        case .largeFiles: return largeFiles.isScanning
        case .downloads: return downloads.isScanning
        }
    }

    func rescan() async {
        switch mode.value {
        case .folders: await scanner.rescan()
        case .largeFiles: await largeFiles.scan()
        case .downloads: await downloads.scan()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(Theme.sectionTitle).foregroundStyle(Theme.ink).lineLimit(1)
    }

    @ViewBuilder private var folderList: some View {
                    let rows = scanner.visible
                    Group {
                        if rows.isEmpty && !scanner.isScanning {
                            Text(scanner.path.isEmpty ? "Nothing measured yet." : "This folder is empty.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.secondary)
                                .padding(8)
                        }
                        // Hugs its rows, and drops the smallest ones if the window is short.
                        FittingRows(items: rows, rowHeight: 36) { folder in
                            FolderRow(folder: folder, first: folder.id == rows.first?.id) { scanner.open(folder) }
                        }
                        .frame(maxHeight: CGFloat(rows.count) * 36)
                    }
                    .id(scanner.path.last?.url)
                    .transition(.opacity.combined(with: .offset(x: 12)))

                    if scanner.protectedSkipped && scanner.path.isEmpty {
                        HStack(spacing: 6) {
                            Text("Some private folders, such as Mail, can’t be measured without Full Disk Access.")
                                .foregroundStyle(Theme.tertiary)
                            Link("Open Settings", destination: URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                                .foregroundStyle(Theme.accent)
                        }
                        .font(Theme.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
    }

    /// The largest folders that are at least 3% of the disk, then "System & other" for the
    /// rest of the used space, so the segments add up exactly to what the disk reports as used.
    private var segments: [UsageSegment] {
        let used = max(diskSpace.stats.used, 0)
        let threshold = Double(diskSpace.stats.total) * 0.03
        var shown: [UsageSegment] = []
        var sum: Int64 = 0
        for folder in scanner.folders where Double(folder.size) >= threshold && shown.count < 4 {
            shown.append(UsageSegment(id: folder.url.path, name: folder.name, size: folder.size,
                                      color: Theme.storageTones[shown.count]))
            sum += folder.size
        }
        // Never negative: if the folders somehow add up to more than "used", the bar scales to their sum.
        shown.append(UsageSegment(id: "other", name: "System & other", size: max(0, used - sum), color: Theme.storageOther))
        return shown
    }

    private var legend: some View {
        let items = scanner.isScanning
            ? [UsageSegment(id: "used", name: "Used", size: diskSpace.stats.used, color: Theme.graphite.opacity(0.45))]
            : segments
        return FlowRow(spacing: 24, lineSpacing: 8) {
            ForEach(items) { segment in
                legendItem(segment.name, segment.size, Circle().fill(segment.color))
            }
            legendItem("Free", diskSpace.stats.available,
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
    /// The folder's path, so two folders with the same name never collide.
    let id: String
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

/// "Largest folders", or "Largest folders › Library › Application Support" once a folder is open.
/// Every crumb but the last goes back to that level.
private struct Breadcrumbs: View {
    let path: [FolderUsage]
    let goBack: (FolderUsage?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            crumb("Largest folders", isLast: path.isEmpty) { goBack(nil) }
            ForEach(path) { folder in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .accessibilityHidden(true)
                crumb(folder.name, isLast: folder == path.last) { goBack(folder) }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func crumb(_ title: String, isLast: Bool, action: @escaping () -> Void) -> some View {
        if isLast {
            Text(title).font(Theme.sectionTitle).foregroundStyle(Theme.ink)
        } else {
            Button(action: action) {
                Text(title).font(Theme.sectionTitle).foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .help("Back to \(title)")
        }
    }
}

private struct FolderRow: View {
    let folder: FolderUsage
    let first: Bool
    let onOpen: () -> Void
    @StateObject private var hovering = ViewState(false)

    private var canOpen: Bool { folder.isDirectory && !folder.isHiddenGroup }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: AppIcons.forFile(
                folder.isHiddenGroup ? FileManager.default.homeDirectoryForCurrentUser.path : folder.url.path))
            Text(folder.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(folder.size.bytes)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            // Hidden files are many folders, not one, so there's nothing single to show.
            // The button keeps its place, so sizes stay in one column.
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel("Show \(folder.name) in Finder")
            .opacity(folder.isHiddenGroup ? 0 : 1)
            .disabled(folder.isHiddenGroup)
            .accessibilityHidden(folder.isHiddenGroup)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
                .opacity(canOpen ? (hovering.value ? 1 : 0.5) : 0)
                .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !first { Hairline().padding(.leading, 32) }
        }
        .hoverWash()
        .onHover { hovering.value = $0 }
        .onTapGesture { if canOpen { onOpen() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityAction { if canOpen { onOpen() } }
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
