import Foundation
import AppKit

/// An app bundle as the uninstaller sees it.
struct AppInfo: Equatable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String?

    init?(url: URL) {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        self.url = url
        bundleID = id
        name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Apple's own apps and Lume are never removed here.
    var refusal: String? {
        if bundleID.hasPrefix("com.apple.") || url.path.hasPrefix("/System/") {
            return "\(name) is part of macOS and can’t be removed."
        }
        if bundleID == Bundle.main.bundleIdentifier || bundleID == "app.lume.optimiser" {
            return "Lume can’t remove itself. Drag it to the Trash from Applications instead."
        }
        return nil
    }
}

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

    /// "com.vendor" from "com.vendor.app.helper".
    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Bundle identifiers of the apps in the usual folders, one level of subfolders deep.
    static func installedIdentifiers() -> Set<String> {
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

    /// The entries in each place named after `id` (or one of its helpers, "id.helper"), or exactly after the app's name.
    /// An entry belonging to another installed app whose identifier extends this one ("id.pro") is left out.
    static func entries(for id: String, name: String?,
                        installed: Set<String> = []) -> [(url: URL, label: String, byName: Bool)] {
        let others = installed.filter { $0.hasPrefix(id + ".") }
        let fm = FileManager.default
        var found: [(URL, String, Bool)] = []
        for place in all {
            let folder = url(place.folder)
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for entry in names {
                let entryID = identifier(of: entry)
                let byID = (entryID == id || entryID.hasPrefix(id + "."))
                    && !others.contains { entryID == $0 || entryID.hasPrefix($0 + ".") }
                // Folders named after the app itself, such as "Application Support/Slack".
                let byName = name.map { entry == $0 && place.folder != "Preferences" } ?? false
                if byID || byName { found.append((folder.appending(path: entry), place.label, !byID)) }
            }
        }
        return found
    }
}

/// One app's bundle and its files in ~/Library, with Move to Trash for the ones ticked.
@MainActor
final class Uninstaller: ObservableObject {
    /// Shared, so an app dropped on the Dock icon arrives on the Apps page.
    static let shared = Uninstaller()
    /// Called when an app arrives from outside the window; shows the Apps page.
    var onOpen: (() -> Void)?

    @Published private(set) var app: AppInfo?
    @Published private(set) var files: [SweepFile] = []
    /// Where each file lives ("Caches"), keyed by its URL; the app itself has none.
    private(set) var places: [URL: String] = [:]
    @Published var selected: Set<URL> = []
    @Published private(set) var isWorking = false
    /// Why an app can't be removed, or the outcome of removing it.
    @Published private(set) var message: String?

    var selectedSize: Int64 { files.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func place(of file: SweepFile) -> String? { places[file.url] }

    /// Shows an app and finds its files. Apple's apps and Lume are refused straight away.
    func load(_ url: URL) {
        guard let info = AppInfo(url: url) else {
            message = "That isn’t an app Lume can read."
            return
        }
        app = info
        files = []
        selected = []
        message = info.refusal
        guard info.refusal == nil else { return }
        isWorking = true
        Task {
            let (files, places, unsure) = await Task.detached(priority: .userInitiated) { Self.measure(info) }.value
            guard app == info else { return }
            self.places = places
            self.files = files
            selected = Set(files.map(\.url)).subtracting(unsure)
            isWorking = false
        }
    }

    func clear() {
        app = nil
        files = []
        selected = []
        message = nil
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose an app to remove along with its files."
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    /// Quits the app politely if it's open, then moves the ticked items to the Trash.
    func trashSelected() async {
        guard let app, app.refusal == nil else { return }
        let targets = files.filter { selected.contains($0.url) }
        guard !targets.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        if !running.isEmpty {
            running.forEach { $0.terminate() }
            // Up to five seconds for it to save and close.
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if running.contains(where: { !$0.isTerminated }) {
                message = "\(app.name) is still open. Quit it, then try again."
                return
            }
        }

        let moved = await Task.detached(priority: .userInitiated) {
            targets.filter { (try? FileManager.default.trashItem(at: $0.url, resultingItemURL: nil)) != nil }
        }.value
        let movedURLs = Set(moved.map(\.url))
        files.removeAll { movedURLs.contains($0.url) }
        selected.subtract(movedURLs)
        let size = moved.reduce(0) { $0 + $1.size }
        if moved.count == targets.count {
            let fileCount = moved.count - (movedURLs.contains(app.url) ? 1 : 0)
            var what = fileCount == 1 ? "1 file" : "\(fileCount) files"
            if movedURLs.contains(app.url) { what = fileCount == 0 ? app.name : "\(app.name) and " + what }
            message = "Moved \(what) (\(size.bytes)) to the Trash."
            if movedURLs.contains(app.url) {
                // Gone: back to the drop zone, which keeps the message.
                self.app = nil
                files = []
            }
        } else if moved.isEmpty {
            message = "Couldn’t move \(app.name) to the Trash. It may need an administrator; try Finder."
        } else {
            message = "Moved \(moved.count) of \(targets.count) items to the Trash; the rest couldn’t be moved."
        }
    }

    /// The bundle and its files. A folder matched only by the app's name (such as "Application Support/Google")
    /// may be shared with another app from the same maker, so it's listed but left unticked when one is installed.
    nonisolated private static func measure(_ app: AppInfo) -> ([SweepFile], [URL: String], Set<URL>) {
        var files = [SweepFile(url: app.url, size: DiskSize.of(app.url), date: nil)]
        var places: [URL: String] = [:]
        var unsure: Set<URL> = []
        let vendor = LibraryPlaces.vendor(app.bundleID)
        let installed = LibraryPlaces.installedIdentifiers()
        let siblings = installed.contains { $0 != app.bundleID && LibraryPlaces.vendor($0) == vendor }
        for (url, label, byName) in LibraryPlaces.entries(for: app.bundleID, name: app.name, installed: installed) {
            let size = DiskSize.of(url) + fileSize(url)
            files.append(SweepFile(url: url, size: size, date: nil))
            places[url] = label
            if byName && siblings { unsure.insert(url) }
        }
        return (files, places, unsure)
    }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey])
        return values?.isRegularFile == true ? Int64(values?.totalFileAllocatedSize ?? 0) : 0
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
        let installed = LibraryPlaces.installedIdentifiers()
        let vendors = Set(installed.map(LibraryPlaces.vendor))

        var byID: [String: (urls: [URL], places: [String])] = [:]
        for place in LibraryPlaces.all {
            let folder = LibraryPlaces.url(place.folder)
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for entry in names {
                let id = LibraryPlaces.identifier(of: entry)
                guard LibraryPlaces.looksLikeIdentifier(id), !id.lowercased().hasPrefix("com.apple."),
                      !vendors.contains(LibraryPlaces.vendor(id)), !running.contains(where: { related(id, $0) }),
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
            let size = entry.urls.reduce(0) { $0 + DiskSize.of($1) + Uninstaller.fileSize($1) }
            var places: [String] = []
            for place in entry.places where !places.contains(place) { places.append(place) }
            return Leftover(id: id, urls: entry.urls, places: places, size: size)
        }
        .sorted { $0.size > $1.size }
    }

    /// The same identifier, or one is the other's helper ("com.foo.app" and "com.foo.app.agent").
    nonisolated private static func related(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        return a == b || a.hasPrefix(b + ".") || b.hasPrefix(a + ".")
    }
}
