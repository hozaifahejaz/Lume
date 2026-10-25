import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: headline, subtitle: detail) {
                if Theme.isHigh(monitor.disk.fraction) {
                    Button("Free Up Space…") { goTo(.clean) }
                        .glassButton()
                }
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 0) {
                        stat("Processor", percent(monitor.cpu),
                             "\(ProcessInfo.processInfo.activeProcessorCount) cores", monitor.cpu)
                        Hairline(vertical: true).padding(.horizontal, 20)
                        stat("Memory", monitor.memory.used.bytes, "of \(monitor.memory.total.bytes)",
                             monitor.memory.fraction)
                        Hairline(vertical: true).padding(.horizontal, 20)
                        stat("Disk", monitor.disk.available.bytes, "available of \(monitor.disk.total.bytes)",
                             monitor.disk.fraction)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Hairline()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Processor, last minute").font(Theme.caption).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(percent(monitor.cpu)).font(Theme.digits).foregroundStyle(Theme.secondary)
                        }
                        Sparkline(values: monitor.cpuHistory)
                            .frame(height: 32)
                    }
                }
            }

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

    private func stat(_ label: String, _ value: String, _ caption: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
            Text(value)
                .font(Theme.number)
                .foregroundStyle(Theme.isHigh(fraction) ? Theme.alert : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption).font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
            HairBar(fraction: fraction).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private var resources: [(name: String, value: Double)] {
        [("Processor", monitor.cpu), ("Memory", monitor.memory.fraction), ("Disk", monitor.disk.fraction)]
    }

    private var headline: String {
        switch monitor.load {
        case ..<0.7: return "Your Mac is running smoothly."
        case ..<0.85: return "Your Mac is busy."
        default: return "Your Mac is under heavy load."
        }
    }

    private var detail: String {
        let busy = resources.filter { $0.value >= 0.7 }.sorted { $0.value > $1.value }
        guard !busy.isEmpty else { return "Processor, memory and disk all have plenty of headroom." }
        let parts = busy.enumerated().map { index, resource in
            "\(index == 0 ? resource.name : resource.name.lowercased()) at \(percent(resource.value))"
        }
        let rest = busy.count < resources.count ? " Everything else is fine." : ""
        return parts.joined(separator: " and ") + "." + rest
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let sort: ProcessList.Sort
    let onQuit: () -> Void
    @StateObject private var hovering = ViewState(false)

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: AppIcons.forProcess(process.id))
            Text(process.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(value)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
            .opacity(hovering.value ? 1 : 0)
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
