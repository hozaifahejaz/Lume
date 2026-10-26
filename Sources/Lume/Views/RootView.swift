import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case memory = "Memory"
    case clean = "Clean"
    case storage = "Storage"
    case startup = "Startup"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .memory: return "memorychip"
        case .clean: return "sparkles"
        case .storage: return "internaldrive"
        case .startup: return "power"
        }
    }
}

/// The page on screen, shared with the View menu so ⌘1–4 and ⌘R work from the menu bar too.
@MainActor
final class Navigator: ObservableObject {
    @Published var page: Page = .overview
    /// Bumped by View › Rescan; the page on screen measures again.
    @Published private(set) var rescans = 0

    func show(_ page: Page) {
        self.page = page
        MainWindow.open()
    }

    func rescan() { rescans += 1 }

    /// The ⌘K palette.
    @Published var commandBarOpen = false

    func toggleCommandBar() {
        commandBarOpen.toggle()
        if commandBarOpen { MainWindow.open() }
    }
}

struct RootView: View {
    @EnvironmentObject private var navigator: Navigator
    /// Shared with Quick Clean, which can run from the Dock or the menu bar with this window closed.
    private let cleaner = QuickActions.shared.cleaner
    @StateObject private var storage = StorageScanner()
    @StateObject private var startup = StartupItems()
    @StateObject private var processes = ProcessList()
    @StateObject private var memoryApps = ProcessList(appsOnly: true)
    @StateObject private var largeFiles = FileSweep(kind: .largeOld)
    @StateObject private var storageMode = ViewState(StorageMode.folders)
    @Namespace private var tabs
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop()

            // Every page is a fixed layout that fills the space between the title bar and the tab bar.
            ZStack {
                page(navigator.page)
                    .id(navigator.page)
                    .transition(.opacity)
            }
            .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 48)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $navigator.page, namespace: tabs)
                .padding(.bottom, 24)
        }
        // A small gear in the title bar's far corner, level with the window buttons.
        .overlay(alignment: .topTrailing) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .padding(.top, 1)
            .padding(.trailing, 12)
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if navigator.commandBarOpen {
                ZStack(alignment: .top) {
                    // A faint veil; clicking it closes the bar.
                    Color.black.opacity(0.06)
                        .ignoresSafeArea()
                        .onTapGesture { navigator.commandBarOpen = false }
                    CommandBar(commands: commands) { navigator.commandBarOpen = false }
                        .padding(.top, 96)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: navigator.page)
        .animation(.easeOut(duration: 0.15), value: navigator.commandBarOpen)
        .onChange(of: navigator.rescans) { rescan() }
    }

    /// Every tab, then the actions.
    private var commands: [Command] {
        let actions = QuickActions.shared
        var list = Page.allCases.enumerated().map { index, page in
            Command(id: page.rawValue, title: page.rawValue, symbol: page.symbol, shortcut: "⌘\(index + 1)") {
                navigator.page = page
            }
        }
        list += [
            Command(id: "quickclean", title: "Quick Clean", symbol: "sparkles", keywords: "caches junk") { actions.quickClean() },
            Command(id: "freeram", title: "Free RAM…", symbol: "memorychip", keywords: "memory purge") {
                navigator.page = .memory
                actions.freeRAM()
            },
            Command(id: "rescan", title: "Rescan", symbol: "arrow.clockwise", shortcut: "⌘R") { navigator.rescan() },
            Command(id: "settings", title: "Settings…", symbol: "gearshape", shortcut: "⌘,") { openSettings() },
        ]
        return list
    }

    private func rescan() {
        switch navigator.page {
        case .overview: processes.refresh()
        case .memory: memoryApps.refresh()
        case .clean:
            if cleaner.phase != .scanning && cleaner.phase != .cleaning { Task { await cleaner.scan() } }
        case .storage:
            switch storageMode.value {
            case .folders: if !storage.isScanning { Task { await storage.rescan() } }
            case .largeFiles: Task { await largeFiles.scan() }
            }
        case .startup: startup.reload()
        }
    }

    @ViewBuilder
    private func page(_ page: Page) -> some View {
        switch page {
        case .overview: OverviewView(processes: processes, goTo: { navigator.page = $0 })
        case .memory: MemoryView(apps: memoryApps)
        case .clean: CleanView(cleaner: cleaner)
        case .storage: StorageView(scanner: storage, largeFiles: largeFiles, mode: storageMode)
        case .startup: StartupView(items: startup)
        }
    }
}

/// A floating glass capsule; the selected tab carries a tinted highlight that glides between tabs.
private struct TabBar: View {
    @Binding var selection: Page
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            // ⌘1–4 live in the View menu.
            ForEach(Page.allCases) { page in
                let selected = selection == page
                Button { selection = page } label: {
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(page.rawValue).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accent.opacity(0.12))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(Capsule(), interactive: true)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selection)
    }
}
