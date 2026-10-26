import Foundation
import AppKit

/// Quick Clean and Free RAM, shared by the Memory page, the menu bar panel and the Dock menu,
/// so they work with the window closed and never run twice at once.
@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()

    /// The same Cleaner the Clean page shows, so a Quick Clean appears there too.
    let cleaner = Cleaner()
    /// Called after a Quick Clean, to re-read free disk space.
    var onCleaned: (() -> Void)?

    enum Job { case cleaning, freeingMemory }
    @Published private(set) var running: Job?
    /// The last outcome in a few words, such as "Freed 1.2 GB".
    @Published private(set) var cleanResult: String?
    @Published private(set) var memoryResult: String?

    func quickClean() {
        guard running == nil else { return }
        running = .cleaning
        cleanResult = nil
        Task {
            let freed = await cleaner.quickClean()
            running = nil
            guard let freed else { return }
            UserDefaults.standard.set(Date(), forKey: Self.lastCleanKey)
            let text = freed > 0 ? "Freed \(freed.bytes)" : "Nothing to clear right now"
            cleanResult = text
            onCleaned?()
            Self.notify(title: "Quick Clean", body: text)
        }
    }

    // MARK: Weekly Quick Clean

    static let weeklyKey = "quickCleanWeekly"
    static let lastCleanKey = "lastQuickClean"
    private var scheduleTimer: Timer?

    /// Checks at launch, on wake and every few hours whether a week has passed since the last Quick Clean.
    /// Off by default; the check itself is a date comparison.
    func startSchedule() {
        runIfDue()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // Give the network and disks a minute to settle after waking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                MainActor.assumeIsolated { QuickActions.shared.runIfDue() }
            }
        }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in QuickActions.shared.runIfDue() }
        }
        timer.tolerance = 30 * 60
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    private func runIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.weeklyKey), running == nil else { return }
        if let last = defaults.object(forKey: Self.lastCleanKey) as? Date,
           Date().timeIntervalSince(last) < 7 * 24 * 60 * 60 { return }
        quickClean()
    }

    /// Runs macOS's own `purge`, which empties the file cache. It needs an administrator password,
    /// so macOS asks for it each time.
    func freeRAM() {
        guard running == nil else { return }
        running = .freeingMemory
        memoryResult = nil
        Task {
            // Read just before and just after purge itself, so the time spent at the password prompt
            // doesn't count other apps' comings and goings as freed.
            let outcome = await Task.detached(priority: .userInitiated) { Self.purge() }.value
            running = nil
            switch outcome {
            case .done(let before, let after):
                let freed = Int64(clamping: after) - Int64(clamping: before)
                // Under 50 MB is within the noise of everything else that's running.
                let text = freed >= 50_000_000 ? "Freed \(freed.bytes)" : "Nothing to free"
                memoryResult = text
                Self.notify(title: "Free RAM", body: text)
            case .cancelled:
                break
            case .failed:
                memoryResult = "Couldn’t free memory"
            }
        }
    }

    /// Free memory in bytes before and after.
    enum Outcome: Sendable { case done(before: UInt64, after: UInt64), cancelled, failed }

    /// The password prompt and purge run in one shell: vm_stat is read on both sides of purge,
    /// once the password has been given.
    nonisolated private static func purge() -> Outcome {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let script = "/usr/bin/vm_stat; /usr/sbin/purge; echo ---; /usr/bin/vm_stat"
        task.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
        let output = Pipe()
        let errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        do { try task.run() } catch { return .failed }
        // Small outputs, read after exit without risk of filling the pipes.
        task.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard task.terminationStatus == 0 else {
            // -128 is "User canceled" from the password prompt.
            return message.contains("-128") ? .cancelled : .failed
        }
        let halves = text.components(separatedBy: "---")
        guard halves.count == 2, let before = freeBytes(halves[0]), let after = freeBytes(halves[1]) else {
            return .failed
        }
        return .done(before: before, after: after)
    }

    /// Free plus speculative pages from vm_stat's output, in bytes; the same "free" the Memory page shows.
    nonisolated private static func freeBytes(_ vmStat: String) -> UInt64? {
        func value(_ label: String) -> UInt64? {
            // do shell script hands output back with \r line endings, so split on any newline.
            guard let line = vmStat.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(label) })
            else { return nil }
            return UInt64(line.filter(\.isNumber))
        }
        guard let free = value("Pages free:"), let speculative = value("Pages speculative:") else { return nil }
        return (free + speculative) * UInt64(vm_kernel_page_size)
    }

    /// A banner with the result, for actions started from the Dock or the menu bar with no window open.
    /// With the window on screen the result is already shown there.
    private static func notify(title: String, body: String) {
        guard !MainWindow.isOnScreen else { return }
        Notifier.post(title: title, body: body)
    }
}
