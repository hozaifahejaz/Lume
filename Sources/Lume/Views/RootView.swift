import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case clean = "Clean"
    case storage = "Storage"
    case startup = "Startup"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "circle.grid.2x2"
        case .clean: return "sparkles"
        case .storage: return "internaldrive"
        case .startup: return "power"
        }
    }
}

struct RootView: View {
    @StateObject private var sectionState = ViewState<Page?>(.overview)
    private var section: Page? {
        get { sectionState.value }
        nonmutating set { sectionState.value = newValue }
    }
    @StateObject private var cleaner = Cleaner()
    @StateObject private var storage = StorageScanner()
    @StateObject private var startup = StartupItems()
    @StateObject private var processes = ProcessList()

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $sectionState.value) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 3)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundStyle(Theme.accent.gradient)
                    Text("Lume").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 240)
        } detail: {
            ScrollView {
                Group {
                    switch section ?? .overview {
                    case .overview: OverviewView(processes: processes, goTo: { section = $0 })
                    case .clean: CleanView(cleaner: cleaner)
                    case .storage: StorageView(scanner: storage)
                    case .startup: StartupView(items: startup)
                    }
                }
                .padding(Theme.gutter)
                .padding(.top, 8)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(.background.secondary)
            .animation(.smooth(duration: 0.25), value: section)
        }
    }
}
