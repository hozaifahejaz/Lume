import Foundation

struct FolderUsage: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var label: String? = nil
    var name: String { label ?? url.lastPathComponent }
}

/// Measures the top-level folders in the home directory plus /Applications.
/// Dot-folders (.Trash, .npm, .cache, .docker…) are measured together as "Hidden files".
@MainActor
final class StorageScanner: ObservableObject {
    @Published private(set) var folders: [FolderUsage] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0

    func scan() async {
        isScanning = true
        progress = 0
        folders = []

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let children = (try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        var targets = children.filter { !$0.lastPathComponent.hasPrefix(".") }
        targets.append(URL(fileURLWithPath: "/Applications"))
        let hidden = children.filter { $0.lastPathComponent.hasPrefix(".") }

        let total = Double(targets.count + 1)
        var done = 0.0
        await withTaskGroup(of: FolderUsage.self) { group in
            for url in targets {
                group.addTask { FolderUsage(url: url, size: DiskSize.of(url)) }
            }
            // Reveal opens the home folder, where the hidden folders live.
            group.addTask {
                FolderUsage(url: home, size: hidden.reduce(0) { $0 + DiskSize.of($1) }, label: "Hidden files")
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
    }
}
