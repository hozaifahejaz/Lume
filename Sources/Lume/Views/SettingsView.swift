import SwiftUI
import ServiceManagement

/// Lume's few choices on glass over the same still backdrop as the main window.
struct SettingsView: View {
    @AppStorage(MenuBarMeter.showsCPUKey) private var showsCPU = false
    @AppStorage(Alerts.enabledKey) private var alerts = true
    @AppStorage(QuickActions.weeklyKey) private var weekly = false
    @StateObject private var login = LoginItem()

    var body: some View {
        VStack(spacing: 16) {
            // Grouped the way System Settings groups related rows: one glass panel, hairlines between.
            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 10) {
                    row("Open at login") {
                        Toggle("Open at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.graphite)
                            .disabled(!login.isAvailable)
                    }
                    if let note = login.note {
                        Text(note)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Hairline()
                    row("Menu bar shows") {
                        Picker("Menu bar shows", selection: $showsCPU) {
                            Text("Icon").tag(false)
                            Text("Icon and processor %").tag(true)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Theme.graphite)
                        .fixedSize()
                    }
                }
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 10) {
                    row("Quick Clean weekly", help: "Clears caches and logs once a week") {
                        Toggle("Quick Clean weekly", isOn: $weekly)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.graphite)
                    }
                    if let lastRun {
                        Text(lastRun)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Hairline()
                    row("Alerts", help: "When the disk is nearly full, or memory pressure stays high; at most once a day each") {
                        Toggle("Alerts", isOn: $alerts)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.graphite)
                    }
                }
            }

            // A quiet credit at the foot, like the fine print of an About pane.
            HStack(spacing: 4) {
                Text("Made with")
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .accessibilityLabel("love")
                Text("by Huzaifa")
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 24)
        // Room for the window buttons, which sit over the backdrop.
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background { Backdrop().ignoresSafeArea() }
        .background(TransparentTitleBar())
        .modifier(HiddenToolbarBackground())
        .preferredColorScheme(.light)
        .onAppear { login.refresh() }
    }

    /// "Last run 3 days ago", once Quick Clean has run.
    private var lastRun: String? {
        guard let last = UserDefaults.standard.object(forKey: QuickActions.lastCleanKey) as? Date else { return nil }
        return "Last run \(last.formatted(.relative(presentation: .named)))"
    }

    private func row<Control: View>(_ title: String, help: String? = nil,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(Theme.body.weight(.medium)).foregroundStyle(Theme.ink).help(help ?? "")
            Spacer(minLength: 16)
            control()
        }
        .frame(minHeight: 24)
    }
}

/// Lets the backdrop run under the title bar, as it does in the main window.
/// The Settings scene has no window style of its own, so this reaches the NSWindow when the view joins it.
private struct TransparentTitleBar: NSViewRepresentable {
    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
        }
    }

    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Asks SwiftUI not to paint its own band or title in the title bar, where it can (macOS 15 and later).
private struct HiddenToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // The main window shows no title either.
            content
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// Lume's own login item through SMAppService, with a plain explanation when it can't be changed.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var note: String?

    /// Only a real app bundle can register itself; `swift run` can't.
    let isAvailable = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")

    func refresh() {
        guard isAvailable else {
            note = "Available when Lume runs as an app from the Applications folder."
            return
        }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        note = status == .requiresApproval ? "Waiting for your approval in System Settings › General › Login Items." : nil
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            note = "Couldn’t change this: \(error.localizedDescription)"
        }
    }
}
