import SwiftUI

struct CleanView: View {
    @ObservedObject var cleaner: Cleaner
    @StateObject private var confirmState = ViewState(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Clean", subtitle: "Remove files your Mac and apps can safely rebuild.")

            Card {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline).font(Theme.label).foregroundStyle(.secondary)
                        Text(bigNumber)
                            .font(Theme.number(46))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    actionButton
                }
                .animation(.smooth, value: cleaner.phase)
            }

            Card {
                VStack(spacing: 0) {
                    ForEach(Array(cleaner.categories.enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Divider().padding(.leading, 48) }
                        row(category)
                    }
                }
            }

            if !cleaner.unreadable.isEmpty {
                Text("Some folders need Full Disk Access. Grant it in System Settings › Privacy & Security.")
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
            }
        }
        .task { if cleaner.phase == .idle { await cleaner.scan() } }
        .confirmationDialog("Remove \(cleaner.selectedTotal.bytes) of files?", isPresented: $confirmState.value) {
            Button("Clean", role: .destructive) { Task { await cleaner.clean() } }
        } message: {
            Text("Caches and logs are recreated automatically. Emptied Trash cannot be recovered.")
        }
    }

    private var headline: String {
        switch cleaner.phase {
        case .idle, .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .done: return "Freed"
        case .ready: return "Ready to clean"
        }
    }

    private var bigNumber: String {
        if case .done(let freed) = cleaner.phase { return freed.bytes }
        return cleaner.selectedTotal.bytes
    }

    @ViewBuilder private var actionButton: some View {
        switch cleaner.phase {
        case .idle, .scanning, .cleaning:
            ProgressView().controlSize(.small)
        case .ready:
            Button("Clean") { confirmState.value = true }
                .buttonStyle(PillButtonStyle())
                .disabled(cleaner.selectedTotal == 0)
        case .done:
            Button("Scan again") { Task { await cleaner.scan() } }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
    }

    private func row(_ category: JunkCategory) -> some View {
        let locked = cleaner.unreadable.contains(category.id)
        let isOn = Binding(
            get: { cleaner.selected.contains(category.id) && !locked },
            set: { on in
                if on { cleaner.selected.insert(category.id) } else { cleaner.selected.remove(category.id) }
            }
        )
        return HStack(spacing: 14) {
            IconBadge(symbol: category.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.system(size: 13, weight: .medium))
                Text(category.detail).font(Theme.label).foregroundStyle(.secondary)
            }
            Spacer()
            if locked {
                Image(systemName: "lock").foregroundStyle(.tertiary)
            } else if let size = cleaner.sizes[category.id] {
                Text(size.bytes)
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(locked)
        }
        .padding(.vertical, 10)
    }
}
