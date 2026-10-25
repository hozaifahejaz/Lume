import Foundation
import AppKit

struct StartupItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let label: String
    let program: String
    let isUserScope: Bool
    var isEnabled: Bool
    /// The name of the app the helper belongs to, when its program lives inside one.
    var appName: String? = nil
    /// Set when the app reinstalled a helper the user had paused.
    var reenabledBy: String? = nil

    var displayName: String {
        if let appName { return appName }
        // "com.vendor.product.agent" reads better as "Product Agent".
        let parts = label.split(separator: ".")
        let meaningful = parts.count > 2 ? parts.dropFirst(2) : parts[...]
        return meaningful.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

/// Reads launch agents, the background helpers apps install to run at login.
/// User agents can be paused by moving the plist into a sibling "Disabled" folder,
/// which is fully reversible. System-wide agents are shown read-only.
@MainActor
final class StartupItems: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    /// Helpers whose plist is being moved; their switches wait until it's done.
    @Published private(set) var busy: Set<URL> = []
    /// Labels an app turned back on behind Lume's back, with who did it, kept for this session.
    private var reenabled: [String: String] = [:]

    private let fm = FileManager.default
    private var userAgents: URL { fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents") }
    private var userDisabled: URL { fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents (Disabled by Lume)") }
    private let systemAgents = URL(fileURLWithPath: "/Library/LaunchAgents")

    func reload() {
        var live = read(userAgents, user: true, enabled: true)
        var paused = read(userDisabled, user: true, enabled: false)

        // An app that reinstalled a helper the user paused: the live copy wins, the stale paused one goes.
        let liveLabels = Set(live.map(\.label))
        for stale in paused where liveLabels.contains(stale.label) {
            try? fm.removeItem(at: stale.url)
            reenabled[stale.label] = stale.appName ?? stale.displayName
        }
        paused.removeAll { liveLabels.contains($0.label) }
        for index in live.indices {
            live[index].reenabledBy = reenabled[live[index].label]
        }

        let result = live + paused + read(systemAgents, user: false, enabled: true)
        items = result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        guard item.isUserScope, item.isEnabled != enabled, !busy.contains(item.url) else { return }
        let source = item.url
        let destination = (enabled ? userAgents : userDisabled).appending(path: source.lastPathComponent)
        busy.insert(source)
        if !enabled { reenabled[item.label] = nil }
        Task {
            let moved = await Task.detached { Self.move(source, to: destination, enabling: enabled) }.value
            if !moved { NSSound.beep() }
            busy.remove(source)
            reload()
        }
    }

    /// Moves a plist between the live and paused folders, keeping launchd in step. Runs off the main actor.
    nonisolated private static func move(_ source: URL, to destination: URL, enabling: Bool) -> Bool {
        let fm = FileManager.default
        let domain = "gui/\(getuid())"
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !enabling { launchctl(["bootout", domain, source.path]) }
        do {
            if fm.fileExists(atPath: destination.path) {
                if enabling {
                    // The app reinstalled its agent meanwhile: keep that one and drop our paused copy.
                    try fm.removeItem(at: source)
                    launchctl(["bootstrap", domain, destination.path])
                    return true
                }
                // An older paused copy is in the way; the live one replaces it.
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: source, to: destination)
            if enabling { launchctl(["bootstrap", domain, destination.path]) }
            return true
        } catch {
            // Pausing failed after bootout: load the agent again so nothing is left half-off.
            if !enabling { launchctl(["bootstrap", domain, source.path]) }
            return false
        }
    }

    func reveal(_ item: StartupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func read(_ folder: URL, user: Bool, enabled: Bool) -> [StartupItem] {
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
            let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let program = (dict["Program"] as? String)
                ?? (dict["ProgramArguments"] as? [String])?.first
                ?? ""
            return StartupItem(url: url, label: label, program: program, isUserScope: user, isEnabled: enabled,
                               appName: Self.appName(for: program))
        }
    }

    /// CFBundleDisplayName or CFBundleName of the outermost .app containing `program`.
    private static func appName(for program: String) -> String? {
        let parts = program.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }),
              let bundle = Bundle(path: parts[...index].joined(separator: "/")) else { return nil }
        let info = bundle.localizedInfoDictionary ?? [:]
        let plain = bundle.infoDictionary ?? [:]
        return (info["CFBundleDisplayName"] ?? plain["CFBundleDisplayName"]
            ?? info["CFBundleName"] ?? plain["CFBundleName"]) as? String
    }

    nonisolated private static func launchctl(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {}
    }
}
