import Foundation
import AppKit

/// A folder whose contents are safe to remove; macOS and apps rebuild them on demand.
struct JunkCategory: Identifiable, Hashable {
    enum Group { case general, developer }

    let id: String
    let name: String
    let detail: String
    let symbol: String
    let url: URL
    var group: Group = .general
    var onByDefault = true
    /// Only items left untouched this long are removed; anything newer may still be in use.
    var minAge: TimeInterval? = nil
    /// A general row that isn't shown at all when its folder doesn't exist, instead of "Not found".
    var hiddenWhenMissing = false

    static var all: [JunkCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developer = home.appending(path: "Library/Developer")
        let day: TimeInterval = 24 * 60 * 60
        return [
            JunkCategory(id: "caches", name: "App caches", detail: "Data apps rebuild when they need it",
                         symbol: "shippingbox", url: home.appending(path: "Library/Caches")),
            JunkCategory(id: "temp", name: "Temporary files", detail: "Left by apps, untouched for three days",
                         symbol: "clock.arrow.circlepath", url: URL(fileURLWithPath: NSTemporaryDirectory()),
                         minAge: 3 * day),
            JunkCategory(id: "logs", name: "Logs", detail: "Diagnostic and crash reports",
                         symbol: "doc.text", url: home.appending(path: "Library/Logs")),
            JunkCategory(id: "savedstate", name: "Saved window state", detail: "Window layouts unused for a month",
                         symbol: "macwindow", url: home.appending(path: "Library/Saved Application State"),
                         onByDefault: false, minAge: 30 * day, hiddenWhenMissing: true),
            JunkCategory(id: "iosupdates", name: "iPhone updates", detail: "Software downloads, fetched again if needed",
                         symbol: "iphone.and.arrow.forward", url: home.appending(path: "Library/iTunes/iPhone Software Updates"),
                         hiddenWhenMissing: true),
            JunkCategory(id: "trash", name: "Trash", detail: "Files you already deleted",
                         symbol: "trash", url: home.appending(path: ".Trash"), onByDefault: false),

            // Shown only when present. None of these live under ~/Library/Caches, so nothing is counted twice.
            JunkCategory(id: "xcode", name: "Xcode build data", detail: "Regenerated on next build",
                         symbol: "hammer", url: developer.appending(path: "Xcode/DerivedData"), group: .developer),
            JunkCategory(id: "simulator", name: "Simulator caches", detail: "Rebuilt when a simulator starts",
                         symbol: "iphone", url: developer.appending(path: "CoreSimulator/Caches"), group: .developer),
            JunkCategory(id: "devicesupport", name: "iOS device support", detail: "Copied again when a device connects",
                         symbol: "cable.connector", url: developer.appending(path: "Xcode/iOS DeviceSupport"),
                         group: .developer),
            JunkCategory(id: "npm", name: "npm cache", detail: "Packages, fetched again on install",
                         symbol: "cube", url: home.appending(path: ".npm/_cacache"), group: .developer),
            JunkCategory(id: "gradle", name: "Gradle cache", detail: "Dependencies, fetched again on build",
                         symbol: "cube", url: home.appending(path: ".gradle/caches"), group: .developer),
            JunkCategory(id: "cargo", name: "Cargo cache", detail: "Crates, fetched again on build",
                         symbol: "cube", url: home.appending(path: ".cargo/registry/cache"), group: .developer),
            JunkCategory(id: "toolcache", name: "Tool caches", detail: "Downloads kept by command-line tools",
                         symbol: "terminal", url: home.appending(path: ".cache"), group: .developer,
                         onByDefault: false),
            JunkCategory(id: "archives", name: "Xcode archives", detail: "Old app builds; keep any you still need",
                         symbol: "archivebox", url: developer.appending(path: "Xcode/Archives"),
                         group: .developer, onByDefault: false),
        ]
    }
}

enum DiskSize {
    private static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
    private static let keySet = Set(keys)

    /// Total allocated size of everything under `url`. Unreadable items are skipped.
    /// The enumerator prefetches these keys, so reading them back is a cache lookup.
    static func of(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keySet), values.isRegularFile == true else { continue }
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
    /// Folders that don't exist on this Mac. General ones show "Not found"; developer ones are hidden.
    @Published private(set) var missing: Set<String> = []
    @Published var selected: Set<String>
    /// Everything Lume has cleared on this Mac, and since when.
    @Published private(set) var lifetimeFreed: Int64
    private(set) var tallySince: Date?
    private(set) var lastScanned: Date?

    private let all = JunkCategory.all
    private let defaults = UserDefaults.standard

    init() {
        selected = Set(JunkCategory.all.filter(\.onByDefault).map(\.id))
        lifetimeFreed = Int64(defaults.integer(forKey: "lifetimeFreed"))
        tallySince = defaults.object(forKey: "lifetimeFreedSince") as? Date
    }

    /// The rows to show: every general category, plus developer folders that exist.
    var categories: [JunkCategory] {
        all.filter { category in
            let present = sizes[category.id] != nil && !missing.contains(category.id)
            return category.group == .general && !category.hiddenWhenMissing ? true : present
        }
    }

    var selectedTotal: Int64 { total(of: selected) }

    private func total(of ids: Set<String>) -> Int64 {
        ids.subtracting(missing).subtracting(unreadable).reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    /// Everything that could be cleared, selected or not.
    var foundTotal: Int64 {
        all.filter { !missing.contains($0.id) && !unreadable.contains($0.id) }.reduce(0) { $0 + (sizes[$1.id] ?? 0) }
    }

    func scan() async {
        phase = .scanning
        sizes = [:]
        unreadable = []
        missing = []
        await measure()
        phase = .ready
    }

    /// Re-measures in place when the numbers are more than three minutes old, without the scanning state.
    func refreshIfStale() async {
        guard let lastScanned, Date().timeIntervalSince(lastScanned) > 180 else { return }
        switch phase {
        case .ready: await measure()
        case .done: await measure(); phase = .ready
        default: break
        }
    }

    private func measure() async {
        enum Result { case size(Int64), missing, unreadable }
        let keep = Self.openAppIdentifiers()
        var results: [String: Result] = [:]
        await withTaskGroup(of: (String, Result).self) { group in
            for category in all {
                group.addTask {
                    let url = category.url
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        return (category.id, .missing)
                    }
                    guard let children = try? FileManager.default.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: nil
                    ) else {
                        return (category.id, .unreadable)
                    }
                    let removable = children.filter { !Self.isKept($0, in: category, keep: keep) }
                    return (category.id, .size(removable.reduce(0) { $0 + DiskSize.of($1) }))
                }
            }
            for await (id, result) in group { results[id] = result }
        }
        // Publish once, so rows never flicker between partial results.
        var sizes: [String: Int64] = [:], missing: Set<String> = [], unreadable: Set<String> = []
        for (id, result) in results {
            switch result {
            case .size(let size): sizes[id] = size
            case .missing: missing.insert(id); sizes[id] = 0
            case .unreadable: unreadable.insert(id); sizes[id] = 0
            }
        }
        self.sizes = sizes
        self.missing = missing
        self.unreadable = unreadable
        lastScanned = Date()
    }

    /// Quick Clean: the default selection, measured and cleared without the Clean page.
    /// Caches of open apps are kept as always. Returns the bytes freed, or nil when Clean is already busy.
    func quickClean() async -> Int64? {
        guard phase != .scanning && phase != .cleaning else { return nil }
        phase = .scanning
        await measure()
        // The defaults, not the switches on the Clean page, which stay as the person left them.
        await clean(Set(all.filter(\.onByDefault).map(\.id)))
        if case .done(let freed) = phase { return freed }
        return 0
    }

    func clean() async { await clean(selected) }

    private func clean(_ ids: Set<String>) async {
        let targets = all.filter { ids.contains($0.id) && !unreadable.contains($0.id) && !missing.contains($0.id) }
        let before = total(of: ids)
        let keep = Self.openAppIdentifiers()
        phase = .cleaning
        await Task.detached(priority: .userInitiated) {
            for category in targets {
                Self.emptyContents(of: category, keep: keep)
            }
        }.value
        // Quietly, so the headline stays on "Cleaning…" instead of flashing back to scanning.
        await measure()
        let freed = max(0, before - total(of: ids))
        record(freed)
        phase = .done(freed: freed)
    }

    private func record(_ freed: Int64) {
        guard freed > 0 else { return }
        if tallySince == nil {
            tallySince = Date()
            defaults.set(tallySince, forKey: "lifetimeFreedSince")
        }
        lifetimeFreed += freed
        defaults.set(Int(lifetimeFreed), forKey: "lifetimeFreed")
    }

    /// Bundle identifiers of running apps, and Lume's own: their caches are left alone.
    private static func openAppIdentifiers() -> [String] {
        var ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        if let own = Bundle.main.bundleIdentifier { ids.append(own) }
        ids.append("app.lume.optimiser")
        return ids
    }

    /// Items left alone: anything newer than the category's minimum age, a cache or temporary item
    /// named after an open app ("com.apple.Safari.SafeBrowsing", ".com.google.Chrome.x1y2"),
    /// and the system's own temporary items and lock files.
    nonisolated private static func isKept(_ child: URL, in category: JunkCategory, keep: [String]) -> Bool {
        if let minAge = category.minAge {
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
            guard let changed = values?.contentModificationDate,
                  changed < Date().addingTimeInterval(-minAge) else { return true }
        }
        guard category.id == "caches" || category.id == "temp" else { return false }
        let name = child.lastPathComponent.hasPrefix(".") ? String(child.lastPathComponent.dropFirst())
            : child.lastPathComponent
        if category.id == "temp" && (name.hasPrefix("com.apple.") || name.lowercased().contains("lock")) { return true }
        return keep.contains { name == $0 || name.hasPrefix($0 + ".") }
    }

    /// Removes the children of a folder, leaving the folder itself in place.
    /// Items that are in use or protected are skipped silently.
    nonisolated private static func emptyContents(of category: JunkCategory, keep: [String]) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: category.url, includingPropertiesForKeys: nil) else { return }
        for child in children where !isKept(child, in: category, keep: keep) {
            try? fm.removeItem(at: child)
        }
    }
}
