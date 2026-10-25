import Foundation

/// A folder whose contents are safe to remove; macOS and apps rebuild them on demand.
struct JunkCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let url: URL

    static var all: [JunkCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            JunkCategory(id: "caches", name: "App caches", detail: "Temporary data apps rebuild when needed",
                         symbol: "shippingbox", url: home.appending(path: "Library/Caches")),
            JunkCategory(id: "logs", name: "Logs", detail: "Diagnostic logs from apps and the system",
                         symbol: "doc.text", url: home.appending(path: "Library/Logs")),
            JunkCategory(id: "xcode", name: "Xcode build data", detail: "DerivedData, regenerated on next build",
                         symbol: "hammer", url: home.appending(path: "Library/Developer/Xcode/DerivedData")),
            JunkCategory(id: "trash", name: "Trash", detail: "Files you already deleted",
                         symbol: "trash", url: home.appending(path: ".Trash")),
        ]
    }
}

enum DiskSize {
    /// Total allocated size of everything under `url`. Unreadable items are skipped.
    static func of(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

@MainActor
final class Cleaner: ObservableObject {
    enum Phase: Equatable { case idle, scanning, ready, cleaning, done(freed: Int64) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var unreadable: Set<String> = []
    @Published var selected: Set<String> = ["caches", "logs", "xcode"]

    let categories = JunkCategory.all

    var selectedTotal: Int64 {
        selected.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    func scan() async {
        phase = .scanning
        sizes = [:]
        unreadable = []
        await withTaskGroup(of: (String, Int64?).self) { group in
            for category in categories {
                group.addTask {
                    let url = category.url
                    guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else {
                        return (category.id, nil)
                    }
                    return (category.id, DiskSize.of(url))
                }
            }
            for await (id, size) in group {
                if let size { sizes[id] = size } else { unreadable.insert(id); sizes[id] = 0 }
            }
        }
        phase = .ready
    }

    func clean() async {
        let targets = categories.filter { selected.contains($0.id) && !unreadable.contains($0.id) }
        let before = selectedTotal
        phase = .cleaning
        await Task.detached(priority: .userInitiated) {
            for category in targets {
                Self.emptyContents(of: category.url)
            }
        }.value
        await scan()
        let after = selectedTotal
        phase = .done(freed: max(0, before - after))
    }

    /// Removes the children of a folder, leaving the folder itself in place.
    /// Items that are in use or protected are skipped silently.
    nonisolated private static func emptyContents(of url: URL) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else { return }
        for child in children {
            try? fm.removeItem(at: child)
        }
    }
}
