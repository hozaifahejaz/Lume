import Foundation
import CoreServices

/// A file Lume suggests moving to the Trash.
struct SweepFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    /// Last opened (Spotlight's record) for large files; when it arrived for downloads.
    let date: Date?
    var name: String { url.lastPathComponent }
}

/// Lists files worth a second look and moves the ones a person picks to the Trash.
/// Nothing is moved except by `trashSelected()`, which only the Move to Trash button calls.
@MainActor
final class FileSweep: ObservableObject {
    enum Kind {
        /// Over 1 GB in the home folder and not opened in six months.
        case largeOld
        /// Installers and archives in Downloads that arrived more than 30 days ago.
        case oldDownloads
    }

    let kind: Kind
    @Published private(set) var files: [SweepFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanned = false
    @Published var selected: Set<URL> = []
    /// "Moved 3 items to the Trash", after a move.
    @Published private(set) var result: String?

    init(kind: Kind) { self.kind = kind }

    var selectedSize: Int64 { files.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let kind = kind
        let found = await Task.detached(priority: .userInitiated) {
            switch kind {
            case .largeOld: return Self.findLargeOld()
            case .oldDownloads: return Self.findOldDownloads()
            }
        }.value
        files = found
        selected = selected.intersection(found.map(\.url))
        isScanning = false
        scanned = true
    }

    /// Finder's own Move to Trash, so everything can be put back.
    func trashSelected() async {
        let targets = files.filter { selected.contains($0.url) }
        guard !targets.isEmpty else { return }
        let moved = await Task.detached(priority: .userInitiated) {
            targets.filter { (try? FileManager.default.trashItem(at: $0.url, resultingItemURL: nil)) != nil }
        }.value
        let movedURLs = Set(moved.map(\.url))
        files.removeAll { movedURLs.contains($0.url) }
        selected.subtract(movedURLs)
        let size = moved.reduce(0) { $0 + $1.size }
        if moved.isEmpty {
            result = "Couldn’t move to the Trash"
        } else {
            result = "Moved \(moved.count == 1 ? "1 item" : "\(moved.count) items") (\(size.bytes)) to the Trash"
        }
        if moved.count < targets.count && !moved.isEmpty { result! += "; some couldn’t be moved" }
    }

    func clearResult() { result = nil }

    // MARK: Finding

    nonisolated private static let largeThreshold: Int64 = 1_000_000_000
    nonisolated private static let sixMonths: TimeInterval = 182 * 24 * 60 * 60
    nonisolated private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

    /// Walks the home folder, skipping Library (app data that apps manage themselves),
    /// hidden folders and the insides of packages such as apps and photo libraries.
    nonisolated private static func findLargeOld() -> [SweepFile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let skip: Set<String> = ["Library", ".Trash"]
        let cutoff = Date().addingTimeInterval(-sixMonths)
        var found: [SweepFile] = []
        let tops = (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        for top in tops where !skip.contains(top.lastPathComponent) {
            guard let enumerator = fm.enumerator(
                at: top, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }
            let items: [URL] = (try? top.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                ? [top] : enumerator.compactMap { $0 as? URL }
            for url in items {
                // Space actually taken on disk, so a sparse disk image doesn't read as 64 GB it never used.
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= largeThreshold else { continue }
                // Spotlight remembers when a file was last opened; a file never opened falls back to its last change.
                let used = lastUsed(url) ?? values.contentModificationDate
                guard let used, used < cutoff else { continue }
                found.append(SweepFile(url: url, size: size, date: used))
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    nonisolated private static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Disk images, installer packages and archives sitting in Downloads for more than 30 days.
    /// These have usually been installed or unpacked already.
    nonisolated private static func findOldDownloads() -> [SweepFile] {
        let fm = FileManager.default
        let downloads = fm.homeDirectoryForCurrentUser.appending(path: "Downloads")
        let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .creationDateKey, .totalFileAllocatedSizeKey,
                                         .fileSizeKey, .isDirectoryKey]
        let kinds: Set<String> = ["dmg", "pkg", "mpkg", "zip", "xip"]
        let cutoff = Date().addingTimeInterval(-thirtyDays)
        let items = (try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: Array(keys),
                                                 options: .skipsHiddenFiles)) ?? []
        return items.compactMap { url -> SweepFile? in
            guard kinds.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let arrived = values.addedToDirectoryDate ?? values.creationDate
            guard let arrived, arrived < cutoff else { return nil }
            // A .pkg can be a folder bundle; measure it whole.
            let size = values.isDirectory == true
                ? DiskSize.of(url) : Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            return SweepFile(url: url, size: size, date: arrived)
        }
        .sorted { $0.size > $1.size }
    }
}
