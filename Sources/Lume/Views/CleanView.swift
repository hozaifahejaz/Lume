import SwiftUI

struct CleanView: View {
    @ObservedObject var cleaner: Cleaner
    @EnvironmentObject private var diskSpace: DiskSpace
    /// The freed figure as it counts up after a clean.
    @StateObject private var shownFreed = ViewState<Int64>(0)
    @StateObject private var confirming = ViewState(false)

    var body: some View {
        let general = cleaner.categories.filter { $0.group == .general }
        let developer = cleaner.categories.filter { $0.group == .developer }

        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: headline)

            HStack(alignment: .top, spacing: Theme.gap) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("What to clean")
                        ForEach(Array(general.enumerated()), id: \.element.id) { index, category in
                            if index > 0 { Hairline().padding(.leading, 48) }
                            row(category)
                        }
                        if !developer.isEmpty {
                            sectionTitle("Developer").padding(.top, 12)
                            ForEach(Array(developer.enumerated()), id: \.element.id) { index, category in
                                if index > 0 { Hairline().padding(.leading, 48) }
                                row(category, compact: true)
                            }
                        }
                        if !cleaner.unreadable.isEmpty {
                            Label("Some folders need Full Disk Access.", systemImage: "lock")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.top, 12)
                        }
                    }
                }

                GlassPanel {
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(eyebrow).font(Theme.caption).foregroundStyle(Theme.secondary)
                        Text(bigNumber)
                            .font(Theme.number)
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText(countsDown: !isDone))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        action.padding(.top, 20)
                        Spacer(minLength: 0)
                        if let tally {
                            Text(tally)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.tertiary)
                                .multilineTextAlignment(.center)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 280)
            }
            // Both panels take the height of the taller one's content, not the whole window.
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.6), value: cleaner.phase)
        .animation(.smooth(duration: 0.6), value: cleaner.selectedTotal)
        .animation(.smooth(duration: 0.4), value: cleaner.categories.map(\.id))
        .task {
            if cleaner.phase == .idle { await cleaner.scan() } else { await cleaner.refreshIfStale() }
        }
        .onChange(of: cleaner.phase) { _, phase in
            if case .done(let freed) = phase {
                diskSpace.refresh()
                countUp(to: freed)
            }
        }
        .onAppear {
            if case .done(let freed) = cleaner.phase { shownFreed.value = freed }
        }
        // ⌘⌫: the keyboard path to cleaning, confirmed in an ordinary dialog instead of a long press.
        .background {
            Button("Clean…") { if canClean { confirming.value = true } }
                .keyboardShortcut(.delete, modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .confirmationDialog("Clean \(cleaner.selectedTotal.bytes)?", isPresented: $confirming.value) {
            Button("Clean", role: .destructive) { Task { await cleaner.clean() } }
        }
    }

    private var isDone: Bool {
        if case .done = cleaner.phase { return true }
        return false
    }

    private var canClean: Bool { cleaner.phase == .ready && cleaner.selectedTotal > 0 }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.sectionTitle)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
    }

    /// Rolls the freed figure up from zero over about a second, easing out.
    private func countUp(to freed: Int64) {
        shownFreed.value = 0
        Task { @MainActor in
            let steps = 14
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(55))
                let t = Double(step) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                withAnimation(.snappy(duration: 0.2)) {
                    shownFreed.value = step == steps ? freed : Int64(Double(freed) * eased)
                }
            }
        }
    }

    private var headline: String {
        switch cleaner.phase {
        case .idle, .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .done(let freed): return freed > 0 ? "Freed \(freed.bytes)" : "Nothing to clear"
        case .ready:
            // Everything found; the big number on the right is what's selected of it.
            let total = cleaner.foundTotal
            return total > 0 ? "\(total.bytes) found" : "Nothing to clear"
        }
    }

    private var eyebrow: String { isDone ? "Freed" : "Selected" }

    private var bigNumber: String {
        isDone ? shownFreed.value.bytes : cleaner.selectedTotal.bytes
    }

    /// "Lume has freed 38 GB since October", once anything has been freed.
    private var tally: String? {
        guard cleaner.lifetimeFreed > 0, let since = cleaner.tallySince else { return nil }
        let sameYear = Calendar.current.isDate(since, equalTo: Date(), toGranularity: .year)
        let month = since.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
        return "\(cleaner.lifetimeFreed.bytes) freed since \(month)"
    }

    @ViewBuilder private var action: some View {
        switch cleaner.phase {
        case .done:
            Button("Scan Again") { Task { await cleaner.scan() } }
                .glassButton()
                .controlSize(.large)
                .frame(height: 148)
        default:
            HoldButton(enabled: canClean, busy: cleaner.phase != .ready) {
                Task { await cleaner.clean() }
            }
            .help("Press and hold, or press ⌘⌫")
        }
    }

    private func row(_ category: JunkCategory, compact: Bool = false) -> some View {
        let missing = cleaner.missing.contains(category.id)
        let locked = cleaner.unreadable.contains(category.id)
        let isOn = Binding(
            get: { cleaner.selected.contains(category.id) && !locked && !missing },
            set: { on in
                if on { cleaner.selected.insert(category.id) } else { cleaner.selected.remove(category.id) }
            }
        )
        return HStack(spacing: 12) {
            IconTile(symbol: category.symbol, size: compact ? 24 : Theme.tileSize)
                .frame(width: Theme.tileSize)
            Text(category.name).font(Theme.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 12)
            if missing {
                Text("Not found")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
            } else if locked {
                Label("Needs access", systemImage: "lock")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
            } else if let size = cleaner.sizes[category.id] {
                Text(size.bytes)
                    .font(Theme.digits)
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.mini)
            }
            Toggle(category.name, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.graphite)
                .disabled(locked || missing)
                .accessibilityLabel(category.name)
        }
        .frame(height: compact ? 36 : 44)
        .opacity(locked || missing ? 0.6 : 1)
        .hoverWash()
        .help(category.detail)
    }
}

/// Press and hold for 1.2s while the ring fills; releasing early cancels.
private struct HoldButton: View {
    let enabled: Bool
    let busy: Bool
    let onComplete: () -> Void
    @StateObject private var progress = ViewState<Double>(0)
    private let duration = 1.2

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(progress.value > 0 ? 1 : 0)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 84, height: 84)
                    .overlay {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .scaleEffect(progress.value > 0 ? 0.94 : 1)
            }
            .frame(width: 108, height: 108)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                guard enabled else { return }
                onComplete()
                withAnimation(.smooth(duration: 0.5)) { progress.value = 0 }
            } onPressingChanged: { pressing in
                guard enabled else { return }
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress.value = 1 }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { progress.value = 0 }
                }
            }
            .allowsHitTesting(enabled)

            Text("Hold to Clean").font(Theme.sectionTitle).foregroundStyle(enabled ? Theme.ink : Theme.tertiary)
        }
        .opacity(enabled || busy ? 1 : 0.45)
        // VoiceOver can't press and hold, so it gets a direct action instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(busy ? "Working" : "Hold to Clean")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Clean") { if enabled { onComplete() } }
    }
}
