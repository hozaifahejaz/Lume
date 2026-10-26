import SwiftUI

/// Where memory goes, which apps hold the most of it, and an honest way to give some back.
/// Like Overview, only the parts that change every second observe the monitor.
struct MemoryView: View {
    @ObservedObject var apps: ProcessList

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            MemoryHeader()
            MemoryBreakdown()

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apps using the most memory").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Quitting apps you aren’t using frees the most.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)

                    FittingRows(items: apps.processes, rowHeight: 36) { app in
                        MemoryAppRow(app: app, first: app.id == apps.processes.first?.id) { apps.quit(app) }
                    }
                }
            }
        }
        .onAppear { apps.start() }
        .onDisappear { apps.stop() }
    }
}

private struct MemoryHeader: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject private var actions = QuickActions.shared

    var body: some View {
        PageHeader(title: title, subtitle: subtitle) {
            Button {
                actions.freeRAM()
            } label: {
                if actions.running == .freeingMemory {
                    // A quiet spinner in place of the icon while macOS asks for the password and purges.
                    Label { Text("Freeing…") } icon: { ProgressView().controlSize(.small) }
                } else {
                    Label("Free RAM…", systemImage: "memorychip")
                }
            }
            .glassButton()
            .disabled(actions.running != nil)
            .help("Empties the file cache with macOS’s own purge; asks for your password")
        }
    }

    private var title: String {
        switch monitor.pressure {
        case .normal: return "Memory pressure is normal."
        case .warning: return "Memory pressure is elevated."
        case .critical: return "Memory pressure is high."
        }
    }

    /// "Memory used" is Activity Monitor's own term for app, wired and compressed memory together.
    private var subtitle: String {
        "Memory used \(monitor.memory.used.bytes) of \(monitor.memory.total.bytes). "
            + "macOS keeps memory full on purpose and frees it the moment it’s needed."
    }
}

/// What the memory holds, as one bar and four figures, with swap and the last Free RAM result beneath.
private struct MemoryBreakdown: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject private var actions = QuickActions.shared

    private struct Part: Identifiable {
        let id: String
        let caption: String
        let bytes: UInt64
        let color: Color
    }

    var body: some View {
        let memory = monitor.memory
        let parts = [
            Part(id: "App memory", caption: "Open apps and their data", bytes: memory.app, color: Theme.storageTones[0]),
            Part(id: "Wired memory", caption: "Held by macOS itself", bytes: memory.wired, color: Theme.storageTones[1]),
            Part(id: "Compressed", caption: "Squeezed to make room", bytes: memory.compressed, color: Theme.storageTones[2]),
            Part(id: "Cached files", caption: "Given back when needed", bytes: memory.cached, color: Theme.storageOther),
        ]
        GlassPanel(fill: false) {
            VStack(alignment: .leading, spacing: 16) {
                bar(parts, total: memory.total)

                HStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        if index > 0 { Hairline(vertical: true).padding(.horizontal, 20) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(part.color).frame(width: 8, height: 8)
                                Text(part.id).font(Theme.caption).foregroundStyle(Theme.secondary)
                            }
                            Text(part.bytes.bytes)
                                .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(part.caption).font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Hairline()

                HStack {
                    Text("Swap used \(memory.swapUsed.bytes) · \(memory.free.bytes) free")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    // The last Free RAM result in place of the note, in the darker caption colour.
                    Text(actions.memoryResult ?? "Free RAM empties the file cache. It rarely makes a Mac faster.")
                        .font(Theme.caption)
                        .foregroundStyle(actions.memoryResult == nil ? Theme.tertiary : Theme.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    /// One capsule split by what the memory holds; free memory is the plain track.
    private func bar(_ parts: [Part], total: UInt64) -> some View {
        GeometryReader { geo in
            // The parts can add up to a little more than physical memory between samples;
            // scale to whichever is larger, and leave room for the 1pt gaps, so the bar never overflows.
            let scale = Double(max(total, parts.reduce(0) { $0 + $1.bytes }, 1))
            let width = max(0, geo.size.width - CGFloat(parts.count))
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(1, width * CGFloat(Double(part.bytes) / scale)))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.track)
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

private struct MemoryAppRow: View {
    let app: ProcessUsage
    let first: Bool
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: AppIcons.forProcess(app.id, appPath: app.appPath))
            Text(app.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(app.memory.bytes)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            // Only apps with a Dock icon can be quit; they're asked politely and can save their work first.
            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.black.opacity(0.05)))
                .contentShape(Capsule())
                .help("Quit \(app.name)")
                .opacity(app.canQuit ? 1 : 0)
                .disabled(!app.canQuit)
                .accessibilityHidden(!app.canQuit)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !first { Hairline().padding(.leading, 32) }
        }
        .hoverWash()
    }
}
