import Foundation
import AppKit

struct ProcessUsage: Identifiable, Hashable {
    let id: Int32
    let name: String
    let memory: Int64
    let cpu: Double
}

/// Lists the heaviest processes using `ps`, which needs no special entitlements.
@MainActor
final class ProcessList: ObservableObject {
    enum Sort: String, CaseIterable { case memory = "Memory", cpu = "CPU" }

    @Published private(set) var processes: [ProcessUsage] = []
    @Published var sort: Sort = .memory { didSet { apply() } }

    private var raw: [ProcessUsage] = []
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task {
            raw = await Task.detached { Self.readPS() }.value
            apply()
        }
    }

    func quit(_ process: ProcessUsage) {
        if let app = NSRunningApplication(processIdentifier: process.id) {
            app.terminate()
        } else {
            kill(process.id, SIGTERM)
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    private func apply() {
        let sorted = raw.sorted { sort == .memory ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        processes = Array(sorted.prefix(12))
    }

    nonisolated private static func readPS() -> [ProcessUsage] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // rss is in KiB; comm is last so names containing spaces stay intact.
        task.arguments = ["-axo", "pid=,rss=,%cpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> ProcessUsage? in
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count == 4,
                      let pid = Int32(parts[0]), pid != ownPID,
                      let rss = Int64(parts[1]),
                      let cpu = Double(parts[2]) else { return nil }
                let name = (String(parts[3]) as NSString).lastPathComponent
                return ProcessUsage(id: pid, name: name, memory: rss * 1024, cpu: cpu)
            }
    }
}
