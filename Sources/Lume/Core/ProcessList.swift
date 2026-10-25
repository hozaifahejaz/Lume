import Foundation
import AppKit
import Darwin

/// One row of the activity list: an app with all its helper processes, or a lone process.
struct ProcessUsage: Identifiable, Hashable {
    /// A member process's pid, unique within one refresh.
    let id: Int32
    let name: String
    let memory: Int64
    /// Percent of one core, like Activity Monitor.
    let cpu: Double
    /// The enclosing .app bundle, when the process belongs to one.
    let appPath: String?
    /// The executable of the representative process, for choosing an icon when there's no app.
    let path: String
    /// Pid of the user-facing app to quit; nil for background and system processes, which can't be quit here.
    let quitPID: Int32?

    var canQuit: Bool { quitPID != nil }
}

/// Lists the heaviest apps and processes using `ps` and `proc_pid_rusage`, which need no special entitlements.
@MainActor
final class ProcessList: ObservableObject {
    enum Sort: String, CaseIterable { case memory = "Memory", cpu = "CPU" }

    @Published private(set) var processes: [ProcessUsage] = []
    @Published var sort: Sort = .memory { didSet { apply() } }

    private var raw: [ProcessUsage] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var previousCPUTime: [Int32: UInt64] = [:]
    private var previousSampleTime: UInt64 = 0

    func start() {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common keeps it ticking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
    }

    func refresh() {
        refreshTask?.cancel()
        generation += 1
        let current = generation
        let regularApps = Self.regularApps()
        let previous = Previous(cpuTimes: previousCPUTime, time: previousSampleTime)
        refreshTask = Task {
            // Listing, measuring and grouping a few hundred processes all happens off the main actor.
            let grouped = await Task.detached(priority: .utility) {
                Self.group(Self.readSample(), regularApps: regularApps, previous: previous)
            }.value
            // A slower, older refresh must never overwrite a newer one.
            guard !Task.isCancelled, current == generation else { return }
            raw = grouped.rows
            previousCPUTime = grouped.previous.cpuTimes
            previousSampleTime = grouped.previous.time
            apply()
        }
    }

    /// Quits a regular app only, after checking the pid still belongs to the same app.
    func quit(_ process: ProcessUsage) {
        guard let pid = process.quitPID,
              let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              let appPath = process.appPath,
              app.bundleURL?.path == appPath else { return }
        app.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    private func apply() {
        let sorted = raw.sorted { sort == .memory ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        let top = Array(sorted.prefix(12))
        if top != processes { processes = top }
    }

    /// Bundle path to pid for every app with a Dock icon: the ones that can be quit.
    private static func regularApps() -> [String: Int32] {
        var apps: [String: Int32] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let path = app.bundleURL?.path { apps[path] = app.processIdentifier }
        }
        return apps
    }

    /// CPU time per pid at the last sample, to turn the next one into a rate.
    struct Previous: Sendable { var cpuTimes: [Int32: UInt64]; var time: UInt64 }

    /// Turns per-process samples into rows, summing helpers under the app bundle they live in.
    nonisolated private static func group(_ sample: Sample, regularApps: [String: Int32], previous: Previous)
        -> (rows: [ProcessUsage], previous: Previous) {
        let previousCPUTime = previous.cpuTimes
        let elapsed = previous.time > 0 ? Double(sample.time &- previous.time) : 0
        var cpuTimes: [Int32: UInt64] = [:]

        struct Bucket {
            var pid: Int32; var name: String; var memory: Int64 = 0; var cpu: Double = 0; var appPath: String?; var path: String
        }
        var buckets: [String: Bucket] = [:]

        for row in sample.rows {
            var cpu = row.psCPU
            if let time = row.cpuTime {
                cpuTimes[row.pid] = time
                if elapsed > 0, let before = previousCPUTime[row.pid], time >= before {
                    cpu = Double(time - before) / elapsed * 100
                }
            }
            let appPath = outermostApp(in: row.path)
            let key = appPath ?? "pid:\(row.pid)"
            var bucket = buckets[key] ?? Bucket(
                pid: row.pid,
                name: appPath.map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") }
                    ?? (row.path as NSString).lastPathComponent,
                appPath: appPath,
                path: row.path
            )
            bucket.memory += row.memory
            bucket.cpu += cpu
            if let appPath, regularApps[appPath] == row.pid {
                bucket.pid = row.pid
                bucket.path = row.path
            }
            buckets[key] = bucket
        }

        let rows = buckets.values.map { bucket in
            ProcessUsage(id: bucket.pid, name: bucket.name, memory: bucket.memory, cpu: bucket.cpu,
                         appPath: bucket.appPath, path: bucket.path, quitPID: bucket.appPath.flatMap { regularApps[$0] })
        }
        return (rows, Previous(cpuTimes: cpuTimes, time: sample.time))
    }

    nonisolated private static func outermostApp(in path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return parts[...index].joined(separator: "/")
    }

    struct Row { let pid: Int32; let memory: Int64; let psCPU: Double; let path: String; let cpuTime: UInt64? }
    struct Sample: Sendable { let rows: [Row]; let time: UInt64 }

    nonisolated private static func readSample() -> Sample {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // rss is in KiB; comm is last so paths containing spaces stay intact.
        task.arguments = ["-axo", "pid=,rss=,%cpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return Sample(rows: [], time: 0) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let rows = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> Row? in
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count == 4,
                      let pid = Int32(parts[0]), pid != ownPID,
                      let rss = Int64(parts[1]),
                      let cpu = Double(parts[2]) else { return nil }
                // Footprint is what Activity Monitor calls Memory; RSS counts shared pages and overstates it.
                let usage = rusage(pid, timebase)
                return Row(pid: pid, memory: usage.map { Int64(clamping: $0.footprint) } ?? rss * 1024, psCPU: cpu,
                           path: String(parts[3]), cpuTime: usage?.cpuTime)
            }
        return Sample(rows: rows, time: DispatchTime.now().uptimeNanoseconds)
    }

    /// Total user + system CPU time in nanoseconds and the physical footprint in bytes,
    /// or nil if the process can't be inspected.
    nonisolated private static func rusage(_ pid: Int32, _ timebase: mach_timebase_info_data_t)
        -> (cpuTime: UInt64, footprint: UInt64)? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        let ticks = info.ri_user_time &+ info.ri_system_time
        return (ticks &* UInt64(timebase.numer) / UInt64(max(timebase.denom, 1)), info.ri_phys_footprint)
    }
}
