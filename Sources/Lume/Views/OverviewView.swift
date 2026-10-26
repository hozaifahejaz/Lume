import SwiftUI

/// The page itself observes only the process list; the parts that change every second
/// (the headline and the live stats) observe the monitor on their own, so a tick redraws
/// just them and not the activity rows.
struct OverviewView: View {
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            OverviewHeader(goTo: goTo)
            LiveStats()

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("", selection: $processes.sort) {
                            ForEach(ProcessList.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.leading, 8)

                    FittingRows(items: processes.processes, rowHeight: 34) { process in
                        ProcessRow(process: process, sort: processes.sort) {
                            processes.quit(process)
                        }
                    }
                }
            }
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }
}

private struct OverviewHeader: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var diskSpace: DiskSpace
    let goTo: (Page) -> Void

    var body: some View {
        PageHeader(title: headline, subtitle: detail) {
            if diskSpace.stats.nearlyFull {
                Button("Free Up Space…") { goTo(.clean) }
                    .glassButton()
            }
        }
    }

    private var headline: String {
        switch monitor.load {
        case .smooth: return "Running smoothly"
        case .busy: return "Busy"
        case .heavy: return "Under heavy load"
        }
    }

    private var detail: String {
        var parts: [String] = []
        if monitor.cpu >= 0.7 { parts.append("The processor is busy at \(monitor.cpu.percent).") }
        switch monitor.pressure {
        case .normal: break
        case .warning: parts.append("Memory pressure is elevated.")
        case .critical: parts.append("Memory pressure is high.")
        }
        if diskSpace.stats.nearlyFull { parts.append("Disk is nearly full.") }
        return parts.joined(separator: " ")
    }
}

/// Processor, memory and disk, with the last minute of processor use.
private struct LiveStats: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var diskSpace: DiskSpace
    /// Read once when Overview appears; health moves over months, not seconds. Nil on desktops.
    @StateObject private var battery = ViewState<BatteryHealth?>(nil)

    var body: some View {
        let disk = diskSpace.stats
        GlassPanel(fill: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 0) {
                    stat("Processor", monitor.cpu.percent,
                         ["\(ProcessInfo.processInfo.activeProcessorCount) cores", Self.coreKinds], monitor.cpu)
                    Hairline(vertical: true).padding(.horizontal, 20)
                    stat("Memory", monitor.memory.used.bytes,
                         ["of \(monitor.memory.total.bytes)", "Pressure \(monitor.pressure.word)"],
                         monitor.memory.fraction, alert: monitor.pressure == .critical)
                    Hairline(vertical: true).padding(.horizontal, 20)
                    stat("Disk", disk.used.bytes,
                         ["of \(disk.total.bytes)", "\(disk.available.bytes) available"],
                         disk.fraction)
                }
                .fixedSize(horizontal: false, vertical: true)

                Hairline()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Processor, last minute").font(Theme.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(monitor.cpu.percent).font(Theme.digits).foregroundStyle(Theme.secondary)
                    }
                    Sparkline(values: monitor.cpuHistory)
                        .frame(height: 28)
                }

                if let health = battery.value {
                    Hairline()
                    batteryLine(health)
                }
            }
        }
        .task {
            let health = await Task.detached(priority: .utility) { BatteryHealth.read() }.value
            if health != battery.value { battery.value = health }
        }
    }

    /// "Battery  97% capacity · 110 cycles · Normal", on MacBooks only.
    private func batteryLine(_ health: BatteryHealth) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "battery.100percent")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text("Battery").font(Theme.caption).foregroundStyle(Theme.secondary)
            Spacer()
            Text("\(health.capacity.percent) capacity · \(health.cycles) cycles · ")
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
                + Text(health.condition)
                .font(Theme.caption)
                .foregroundStyle(health.needsService ? Theme.alert : Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// `alert` turns the number red; by default that happens past 85%. Memory passes it in,
    /// because a nearly full memory figure is normal on macOS and only high pressure is a problem.
    private func stat(_ label: String, _ value: String, _ captions: [String], _ fraction: Double,
                      alert: Bool? = nil) -> some View {
        let high = alert ?? Theme.isHigh(fraction)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
            Text(value)
                .font(Theme.number)
                .foregroundStyle(high ? Theme.alert : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                ForEach(captions.filter { !$0.isEmpty }, id: \.self) { caption in
                    Text(caption).font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
            HairBar(fraction: fraction, alert: high).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "4 performance · 6 efficiency" on Apple silicon; empty where the split isn't reported.
    private static let coreKinds: String = {
        func int(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        func string(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
            return String(cString: buffer)
        }
        let levels = int("hw.nperflevels")
        guard levels > 1 else { return "" }
        return (0..<levels).compactMap { level -> String? in
            let count = int("hw.perflevel\(level).physicalcpu")
            let name = string("hw.perflevel\(level).name").lowercased()
            return count > 0 && !name.isEmpty ? "\(count) \(name)" : nil
        }.joined(separator: " · ")
    }()
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let sort: ProcessList.Sort
    let onQuit: () -> Void
    @StateObject private var hovering = ViewState(false)

    var body: some View {
        HStack(spacing: 12) {
            if let image = AppIcons.forProcess(process.id, appPath: process.appPath) {
                AppIconView(image: image)
            } else {
                IconTile(symbol: ProcessSymbol.forPath(process.path), size: Theme.rowIcon)
            }
            Text(process.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(value)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            // Only regular apps can be quit; system and background processes never show the button.
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
            .accessibilityLabel("Quit \(process.name)")
            .opacity(process.canQuit && hovering.value ? 1 : 0)
            .disabled(!process.canQuit)
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering.value = $0 }
        .hoverWash()
    }

    private var value: String {
        switch sort {
        case .memory: return process.memory.bytes
        case .cpu: return String(format: "%.1f%%", process.cpu)
        }
    }
}
