import Foundation

struct FolderUsage: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var name: String { url.lastPathComponent }
}

/// Measures the top-level folders in the home directory plus /Applications.
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
        var targets = (try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        targets.append(URL(fileURLWithPath: "/Applications"))

        let total = Double(targets.count)
        var done = 0.0
        await withTaskGroup(of: FolderUsage.self) { group in
            for url in targets {
                group.addTask { FolderUsage(url: url, size: DiskSize.of(url)) }
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
