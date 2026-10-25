import Foundation

struct FolderUsage: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var label: String? = nil
    /// Dot-folders measured together: not a real folder, so it can't be opened or shown in Finder.
    var isHiddenGroup = false
    var isDirectory = true
    var name: String { label ?? url.lastPathComponent }
}

/// Measures the top-level folders in the home directory plus /Applications.
/// Dot-folders (.Trash, .npm, .cache, .docker…) are measured together as "Hidden files".
/// Any folder can then be opened to measure what's inside it.
@MainActor
final class StorageScanner: ObservableObject {
    @Published private(set) var folders: [FolderUsage] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    /// True when macOS kept Lume out of folders such as Desktop or Mail, so totals read low.
    @Published private(set) var protectedSkipped = false

    /// The folders opened from the top level, outermost first. Empty means the top level.
    @Published private(set) var path: [FolderUsage] = []
    @Published private(set) var children: [FolderUsage] = []
    private var childCache: [URL: [FolderUsage]] = [:]
    private var childTask: Task<Void, Never>?

    /// What the list shows right now.
    var visible: [FolderUsage] { path.isEmpty ? folders : children }

    func scan() async {
        isScanning = true
        progress = 0
        folders = []
        childCache = [:]

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let children = (try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        var targets = children.filter { !$0.lastPathComponent.hasPrefix(".") }
        targets.append(URL(fileURLWithPath: "/Applications"))
        let hidden = children.filter { $0.lastPathComponent.hasPrefix(".") }
        protectedSkipped = await Task.detached { Self.protectedFoldersUnreadable(home: home) }.value

        let total = Double(targets.count + 1)
        var done = 0.0
        await withTaskGroup(of: FolderUsage.self) { group in
            for url in targets {
                // Two folders are called "Applications"; the one in the home folder is yours alone.
                let label = url == home.appending(path: "Applications") ? "Your Applications" : nil
                group.addTask { FolderUsage(url: url, size: DiskSize.of(url), label: label) }
            }
            group.addTask {
                FolderUsage(url: home.appending(path: ".hidden-files"), size: hidden.reduce(0) { $0 + DiskSize.of($1) },
                            label: "Hidden files", isHiddenGroup: true)
            }
            for await usage in group {
                done += 1
                progress = done / max(total, 1)
                if usage.size > 0 {
                    folders.append(usage)
                    folders.sort { $0.size > $1.size }
                }
            }
        }
        isScanning = false
        if let current = path.last { await measureChildren(of: current) }
    }

    /// Rescans whatever is on screen: the top level, or the open folder.
    func rescan() async {
        if let current = path.last {
            childCache[current.url] = nil
            await measureChildren(of: current)
        } else {
            await scan()
        }
    }

    /// Opens a folder from the list.
    func open(_ folder: FolderUsage) {
        guard folder.isDirectory, !folder.isHiddenGroup else { return }
        path.append(folder)
        load(folder)
    }

    /// Goes back to a crumb; nil is the top level.
    func goBack(to folder: FolderUsage?) {
        childTask?.cancel()
        if let folder, let index = path.firstIndex(of: folder) {
            path = Array(path.prefix(through: index))
            load(folder)
        } else {
            path = []
            children = []
            isScanning = false
        }
    }

    private func load(_ folder: FolderUsage) {
        childTask?.cancel()
        if let cached = childCache[folder.url] {
            children = cached
            isScanning = false
            return
        }
        children = []
        childTask = Task { await measureChildren(of: folder) }
    }

    private func measureChildren(of folder: FolderUsage) async {
        isScanning = true
        progress = 0
        let url = folder.url
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: []
        )) ?? []
        let total = Double(max(items.count, 1))
        var done = 0.0
        var measured: [FolderUsage] = []
        await withTaskGroup(of: FolderUsage.self) { group in
            for item in items {
                group.addTask {
                    let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    // Apps and other packages look like single files in Finder, so they're not opened here either.
                    let isFolder = values?.isDirectory == true && values?.isPackage != true
                    let size = values?.isDirectory == true ? DiskSize.of(item) : Self.fileSize(item)
                    return FolderUsage(url: item, size: size, isDirectory: isFolder)
                }
            }
            for await usage in group {
                guard !Task.isCancelled else { return }
                done += 1
                if path.last?.url == url { progress = done / total }
                if usage.size > 0 { measured.append(usage) }
            }
        }
        guard !Task.isCancelled else { return }
        measured.sort { $0.size > $1.size }
        childCache[url] = measured
        if path.last?.url == url {
            children = measured
            isScanning = false
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    /// Folders macOS guards with privacy permissions; if any can't be listed, their sizes are missing.
    nonisolated private static func protectedFoldersUnreadable(home: URL) -> Bool {
        let fm = FileManager.default
        return ["Desktop", "Documents", "Downloads", "Library/Mail", "Library/Messages"].contains { name in
            let path = home.appending(path: name).path
            return fm.fileExists(atPath: path) && (try? fm.contentsOfDirectory(atPath: path)) == nil
        }
    }
}
