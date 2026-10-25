import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: greeting, subtitle: summary)

            Card {
                HStack(spacing: 12) {
                    Ring(fraction: monitor.cpu, label: "Processor",
                         caption: "\(ProcessInfo.processInfo.activeProcessorCount) cores")
                    Ring(fraction: monitor.memory.fraction, label: "Memory",
                         caption: "\(monitor.memory.used.bytes) of \(monitor.memory.total.bytes)")
                    Ring(fraction: monitor.disk.fraction, label: "Disk",
                         caption: "\(monitor.disk.available.bytes) free")
                }
                .padding(.vertical, 8)
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Processor · last minute").font(Theme.label).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(monitor.cpu * 100))%").font(Theme.number(15))
                    }
                    Sparkline(values: monitor.cpuHistory, tint: Theme.tint(for: monitor.cpu))
                        .frame(height: 70)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Activity").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Picker("", selection: $processes.sort) {
                            ForEach(ProcessList.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(.bottom, 8)

                    ForEach(processes.processes) { process in
                        ProcessRow(process: process, sort: processes.sort, total: monitor.memory.total) {
                            processes.quit(process)
                        }
                    }
                }
            }

            if monitor.disk.fraction > 0.8 {
                Button { goTo(.clean) } label: {
                    Label("Your disk is getting full. Free up space", systemImage: "sparkles")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var summary: String {
        let worst = max(monitor.cpu, monitor.memory.fraction, monitor.disk.fraction)
        switch worst {
        case ..<0.6: return "Everything is running smoothly."
        case ..<0.85: return "Your Mac is working, but has room to spare."
        default: return "Something is running hot. Take a look below."
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let sort: ProcessList.Sort
    let total: UInt64
    let onQuit: () -> Void
    @StateObject private var hoverState = ViewState(false)
    private var hovering: Bool {
        get { hoverState.value }
        nonmutating set { hoverState.value = newValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(process.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
            UsageBar(fraction: fraction, tint: sort == .memory ? Theme.accent : Theme.calm)
            Text(value)
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hovering ? 0.04 : 0)))
        .onHover { hovering = $0 }
    }

    private var fraction: Double {
        switch sort {
        case .memory: return total > 0 ? Double(process.memory) / Double(total) * 4 : 0
        case .cpu: return process.cpu / 100
        }
    }

    private var value: String {
        switch sort {
        case .memory: return process.memory.bytes
        case .cpu: return String(format: "%.1f%%", process.cpu)
        }
    }
}
