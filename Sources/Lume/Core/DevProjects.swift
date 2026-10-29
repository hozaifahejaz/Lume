import Foundation

/// Code projects on this Mac, found through Spotlight by the file at their root, and what each leaves behind.
/// Only things a project rebuilds are ever returned: dependencies, build folders, caches and renders, never source.
enum DevProjects {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Folders holding a file with one of these names. Nil when there are none, or Spotlight can't be asked,
    /// so a Mac without such projects doesn't show their rows at all.
    /// Hidden folders (tool installs like ~/.local) and ~/Library are skipped, except Claude's scratch workspaces.
    static func roots(holding names: [String]) -> [URL]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        let query = names.map { "kMDItemFSName == '\($0)'" }.joined(separator: " || ")
        process.arguments = ["-onlyin", home.path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let library = home.appending(path: "Library").path + "/"
        let scratch = home.appending(path: "Library/Application Support/Claude/scratch-workspaces").path + "/"
        let folders = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { path in
                let inside = path.dropFirst(home.path.count).split(separator: "/")
                return !inside.dropLast().contains { $0.hasPrefix(".") || $0 == "node_modules" }
                    && (!path.hasPrefix(library) || path.hasPrefix(scratch))
            }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL }
        return folders.isEmpty ? nil : Array(Set(folders)).sorted { $0.path < $1.path }
    }

    /// The contents of node_modules in JavaScript projects idle for `idle`, put back by npm install.
    /// Remotion's browser and bundler cache are left to their own row, so nothing is counted twice.
    static func dependencies(idle: TimeInterval) -> [URL]? {
        guard let projects = roots(holding: ["package.json"]) else { return nil }
        return idleOnes(projects, for: idle).flatMap { project -> [URL] in
            let modules = project.appending(path: "node_modules")
            let children = (try? FileManager.default.contentsOfDirectory(at: modules, includingPropertiesForKeys: nil)) ?? []
            return children.filter { ![".remotion", ".cache"].contains($0.lastPathComponent) }
        }
    }

    /// Build folders of projects idle for `idle`, each named by its own tool so a source folder is never taken.
    static func buildOutput(idle: TimeInterval) -> [URL]? {
        let outputs = [
            ("package.json", [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache"]),
            ("Package.swift", [".build"]),
            ("Cargo.toml", ["target"]),
        ]
        var found: [URL] = []
        var anyProjects = false
        for (marker, folders) in outputs {
            guard let projects = roots(holding: [marker]) else { continue }
            anyProjects = true
            for project in idleOnes(projects, for: idle) {
                found += folders.map { project.appending(path: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
        }
        return anyProjects ? found : nil
    }

    /// Remotion's headless browser and bundler cache in projects idle for `idle`. Both come back on the next render.
    static func remotionCaches(idle: TimeInterval) -> [URL]? {
        guard let projects = roots(holding: remotionConfigs) else { return nil }
        return idleOnes(projects, for: idle).flatMap { project in
            [project.appending(path: "node_modules/.remotion"), project.appending(path: "node_modules/.cache/webpack")]
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    /// Everything in a Remotion project's out folder left untouched for `age`.
    static func remotionRenders(age: TimeInterval) -> [URL]? {
        guard let projects = roots(holding: remotionConfigs) else { return nil }
        let cutoff = Date().addingTimeInterval(-age)
        return projects.flatMap { project -> [URL] in
            let out = project.appending(path: "out")
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: out, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return [] }
            return children.filter { (modified($0) ?? Date()) < cutoff }
        }
    }

    private static let remotionConfigs = ["remotion.config.ts", "remotion.config.js", "remotion.config.mjs"]

    private static func idleOnes(_ projects: [URL], for duration: TimeInterval) -> [URL] {
        guard duration > 0 else { return projects }
        let cutoff = Date().addingTimeInterval(-duration)
        return projects.filter { lastActive($0).map { $0 < cutoff } ?? false }
    }

    /// The newest change to any file in a project, outside dependencies, build output and hidden folders.
    /// Nil when the project can't be read or is too large to walk, so it's never mistaken for an idle one.
    private static func lastActive(_ project: URL) -> Date? {
        let skipped: Set<String> = ["node_modules", "target", "build", "dist", "out"]
        guard (try? FileManager.default.contentsOfDirectory(atPath: project.path)) != nil,
              var latest = modified(project),
              let files = FileManager.default.enumerator(
                  at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
              ) else { return nil }
        var walked = 0
        for case let file as URL in files {
            if skipped.contains(file.lastPathComponent) { files.skipDescendants() }
            if let date = modified(file), date > latest { latest = date }
            walked += 1
            if walked > 50_000 { return nil }
        }
        return latest
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
