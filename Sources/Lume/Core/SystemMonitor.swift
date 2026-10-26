import Foundation
import AppKit
import Darwin

/// Samples CPU, memory and memory pressure once a second using Mach APIs.
/// With no window on screen (only the menu bar icon), sampling eases off to every 5 seconds.
/// Disk space lives in its own `DiskSpace`, so pages that only show the disk don't redraw every second.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var memory = MemoryStats()
    @Published private(set) var pressure: Pressure = .normal
    let diskSpace = DiskSpace()

    private var timer: Timer?
    private var previousTicks: [CPUTicks] = []
    private var interval: TimeInterval = 0
    /// The latest reading, kept even while nobody is watching; the menu bar meter reads it from here.
    private(set) var latestCPU: Double = 0
    private(set) var latestMemory = MemoryStats()
    private var latestPressure: Pressure = .normal
    private var latestHistory: [Double] = Array(repeating: 0, count: 60)
    /// With every window closed, a closed window's views are still alive and would lay out on each
    /// published change, so readings are only published while a window or the panel is on screen.
    private var watched = true
    private var observers: [NSObjectProtocol] = []

    init() {
        sample()
        schedule(every: 1)

        // Any window appearing, hiding, closing or being covered can change whether anyone is looking.
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Let a closing window finish leaving the screen before looking.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.updatePace() } }
            }
        }
    }

    /// One second while a Lume window or the menu bar panel is on screen, five otherwise.
    private func updatePace() {
        let watched = NSApp.windows.contains { window in
            window.isVisible && window.occlusionState.contains(.visible)
                // The status item's own window is always on screen; it doesn't count as someone watching.
                && !window.className.contains("StatusBarWindow")
        }
        self.watched = watched
        if watched { publish() }
        schedule(every: watched ? 1 : 5)
    }

    private func schedule(every seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        timer?.invalidate()
        // .common keeps it ticking while a menu is open.
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = seconds * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if seconds == 1 { sample() }
    }

    func sample() {
        let ticks = Self.readCPUTicks()
        if !previousTicks.isEmpty, previousTicks.count == ticks.count {
            var busy: Double = 0
            var total: Double = 0
            for (now, before) in zip(ticks, previousTicks) {
                let b = Double(now.busy &- before.busy)
                busy += b
                total += b + Double(now.idle &- before.idle)
            }
            latestCPU = total > 0 ? busy / total : 0
            latestHistory.removeFirst()
            latestHistory.append(latestCPU)
        }
        previousTicks = ticks
        latestMemory = Self.readMemory()
        latestPressure = Self.readPressure()
        if watched { publish() }
    }

    /// Assigns only what moved, so an unchanged reading doesn't redraw anything.
    private func publish() {
        if latestCPU != cpu { cpu = latestCPU }
        if latestHistory != cpuHistory { cpuHistory = latestHistory }
        if latestMemory != memory { memory = latestMemory }
        if latestPressure != pressure { pressure = latestPressure }
    }

    // MARK: CPU

    struct CPUTicks {
        var busy: UInt32
        var idle: UInt32
    }

    private static func readCPUTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [CPUTicks] = []
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            ticks.append(CPUTicks(busy: user &+ system &+ nice, idle: idle))
        }
        return ticks
    }

    // MARK: Memory

    struct MemoryStats: Equatable {
        var total: UInt64 = ProcessInfo.processInfo.physicalMemory
        var used: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var app: UInt64 = 0
        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    private static func readMemory() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var out = MemoryStats()
        guard result == KERN_SUCCESS else { return out }
        let page = UInt64(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used" = app + wired + compressed.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        out.app = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * page
        out.wired = UInt64(stats.wire_count) * page
        out.compressed = UInt64(stats.compressor_page_count) * page
        out.used = out.app + out.wired + out.compressed
        return out
    }

    /// The kernel's own verdict on memory, the same signal Activity Monitor's pressure graph uses.
    /// A full-looking memory number is normal on macOS; pressure is what says whether it hurts.
    enum Pressure: Int {
        case normal = 1, warning = 2, critical = 4

        var word: String {
            switch self {
            case .normal: return "normal"
            case .warning: return "elevated"
            case .critical: return "high"
            }
        }
    }

    private static func readPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return Pressure(rawValue: Int(level)) ?? .normal
    }
}

/// Free and used space on the startup disk, read every 30 seconds off the main actor.
@MainActor
final class DiskSpace: ObservableObject {
    @Published private(set) var stats = DiskStats()
    private var timer: Timer?

    init() {
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-reads free space in the background; the volume query can be slow.
    func refresh() {
        Task {
            let stats = await Task.detached { Self.read() }.value
            if stats != self.stats { self.stats = stats }
        }
    }

    nonisolated private static func read() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return DiskStats() }
        return DiskStats(
            total: Int64(values.volumeTotalCapacity ?? 0),
            available: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}

struct DiskStats: Equatable {
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { total - available }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Under 10% free: the one point where disk space starts to matter for speed.
    var nearlyFull: Bool { total > 0 && Double(available) / Double(total) < 0.1 }
}
