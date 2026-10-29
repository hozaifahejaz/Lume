import Foundation

/// Remotion projects on this Mac, found by their config file, and what each leaves behind.
/// Only build output is ever returned: the headless browser, the bundler cache and rendered files, never source.
enum RemotionProjects {
    /// Folders holding a remotion.config file, found through Spotlight. Nil when Spotlight can't be asked.
    static func roots() -> [URL]? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", home.path, "kMDItemFSName == 'remotion.config.*'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let folders = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.contains("/node_modules/") && !$0.contains("/.Trash/") }
            .map { URL(fileURLWithPath: String($0)).deletingLastPathComponent().standardizedFileURL }
        return Array(Set(folders)).sorted { $0.path < $1.path }
    }

    /// The headless browser and bundler cache of projects untouched for `idle`. Both come back on the next render.
    static func caches(in projects: [URL], idle: TimeInterval) -> [URL] {
        let cutoff = Date().addingTimeInterval(-idle)
        return projects.filter { lastActive($0).map { $0 < cutoff } ?? false }.flatMap { project in
            [project.appending(path: "node_modules/.remotion"), project.appending(path: "node_modules/.cache/webpack")]
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    /// Everything in a project's out folder left untouched for `age`.
    static func renders(in projects: [URL], age: TimeInterval) -> [URL] {
        let cutoff = Date().addingTimeInterval(-age)
        return projects.flatMap { project -> [URL] in
            let out = project.appending(path: "out")
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: out, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return [] }
            return children.filter { (modified($0) ?? Date()) < cutoff }
        }
    }

    /// The last time anyone worked on a project: the newest of its folder, its out folder and every file in src.
    /// Nil when the project can't be read, so a folder Lume can't see into is never mistaken for an idle one.
    private static func lastActive(_ project: URL) -> Date? {
        guard (try? FileManager.default.contentsOfDirectory(atPath: project.path)) != nil else { return nil }
        var latest = [project, project.appending(path: "out"), project.appending(path: "package.json")]
            .compactMap(modified).max() ?? .distantPast
        if let files = FileManager.default.enumerator(
            at: project.appending(path: "src"), includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for case let file as URL in files {
                if let date = modified(file), date > latest { latest = date }
            }
        }
        return latest
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
