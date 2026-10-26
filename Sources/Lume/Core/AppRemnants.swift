import Foundation
import AppKit

/// The folders in ~/Library where apps keep their data, named the way Finder shows them.
enum LibraryPlaces {
    static let all: [(folder: String, label: String)] = [
        ("Application Support", "Application Support"),
        ("Caches", "Caches"),
        ("Preferences", "Preferences"),
        ("Containers", "Containers"),
        ("Saved Application State", "Saved State"),
        ("Logs", "Logs"),
        ("HTTPStorages", "Web data"),
        ("WebKit", "Web data"),
    ]

    static func url(_ folder: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library").appending(path: folder)
    }

    /// The bundle identifier an entry is named after: "com.foo.Bar.plist" and "com.foo.Bar.savedState" → "com.foo.Bar".
    static func identifier(of entry: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies"] where entry.hasSuffix(suffix) {
            return String(entry.dropLast(suffix.count))
        }
        return entry
    }

    /// Reverse-DNS names only ("com.vendor.app"); plain names such as "Google" could belong to anything.
    static func looksLikeIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
    }
}

/// Data in ~/Library left by apps that are no longer on this Mac.
struct Leftover: Identifiable, Hashable {
    /// The bundle identifier the entries are named after.
    let id: String
    let urls: [URL]
    let places: [String]
    let size: Int64
}

/// Finds leftovers conservatively: only entries named like a bundle identifier, not Apple's, whose
/// identifier no installed app (as LaunchServices knows them) or running process uses, from a vendor
/// with no app still installed, and untouched for 30 days. Anything else is left out of the list.
@MainActor
final class Leftovers: ObservableObject {
    @Published private(set) var items: [Leftover] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanned = false
    @Published var selected: Set<String> = []
    @Published private(set) var result: String?

    var selectedSize: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let found = await Task.detached(priority: .userInitiated) { Self.find(running: running) }.value
        items = found
        selected = selected.intersection(found.map(\.id))
        isScanning = false
        scanned = true
    }

    func clearResult() { result = nil }

    func trashSelected() async {
        let targets = items.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        let moved = await Task.detached(priority: .userInitiated) {
            targets.filter { item in
                item.urls.map { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }
                    .allSatisfy { $0 }
            }
        }.value
        let ids = Set(moved.map(\.id))
        items.removeAll { ids.contains($0.id) }
        selected.subtract(ids)
        let size = moved.reduce(0) { $0 + $1.size }
        result = moved.isEmpty ? "Couldn’t move to the Trash"
            : "Moved data from \(moved.count == 1 ? "1 app" : "\(moved.count) apps") (\(size.bytes)) to the Trash"
    }

    nonisolated private static func find(running: Set<String>) -> [Leftover] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let installed = installedIdentifiers()
        let vendors = Set(installed.map(vendor))

        var byID: [String: (urls: [URL], places: [String])] = [:]
        for place in LibraryPlaces.all {
            let folder = LibraryPlaces.url(place.folder)
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for entry in names {
                let id = LibraryPlaces.identifier(of: entry)
                guard LibraryPlaces.looksLikeIdentifier(id), !id.lowercased().hasPrefix("com.apple."),
                      !vendors.contains(vendor(id)), !running.contains(where: { related(id, $0) }),
                      !installed.contains(where: { related(id, $0) }) else { continue }
                let url = folder.appending(path: entry)
                // Something that changed recently is still in use by something, even without an app.
                let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard let changed, changed < cutoff else { continue }
                byID[id, default: ([], [])].urls.append(url)
                byID[id, default: ([], [])].places.append(place.label)
            }
        }
        return byID.compactMap { id, entry -> Leftover? in
            // Still registered with LaunchServices means an app with this identifier exists somewhere.
            guard NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).isEmpty else { return nil }
            let size = entry.urls.reduce(0) { $0 + DiskSize.of($1) + fileSize($1) }
            var places: [String] = []
            for place in entry.places where !places.contains(place) { places.append(place) }
            return Leftover(id: id, urls: entry.urls, places: places, size: size)
        }
        .sorted { $0.size > $1.size }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey])
        return values?.isRegularFile == true ? Int64(values?.totalFileAllocatedSize ?? 0) : 0
    }

    /// "com.vendor" from "com.vendor.app.helper".
    nonisolated private static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// The same identifier, or one is the other's helper ("com.foo.app" and "com.foo.app.agent").
    nonisolated private static func related(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        return a == b || a.hasPrefix(b + ".") || b.hasPrefix(a + ".")
    }

    /// Bundle identifiers of the apps in the usual folders, one level of subfolders deep.
    nonisolated private static func installedIdentifiers() -> Set<String> {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", fm.homeDirectoryForCurrentUser.appending(path: "Applications").path]
        var ids: Set<String> = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let path = root + "/" + name
                if name.hasSuffix(".app") {
                    if let id = Bundle(path: path)?.bundleIdentifier { ids.insert(id) }
                } else {
                    for inner in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where inner.hasSuffix(".app") {
                        if let id = Bundle(path: path + "/" + inner)?.bundleIdentifier { ids.insert(id) }
                    }
                }
            }
        }
        return ids
    }
}
