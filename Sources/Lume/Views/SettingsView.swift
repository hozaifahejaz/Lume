import SwiftUI
import ServiceManagement

/// Two choices on glass over the same still backdrop as the main window:
/// whether Lume opens at login, and what the menu bar shows.
struct SettingsView: View {
    @AppStorage(MenuBarMeter.showsCPUKey) private var showsCPU = false
    @AppStorage(Alerts.enabledKey) private var alerts = true
    @AppStorage(QuickActions.weeklyKey) private var weekly = false
    @StateObject private var login = LoginItem()

    var body: some View {
        VStack(spacing: 16) {
            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 6) {
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
                }
            }

            GlassPanel(fill: false) {
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

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 6) {
                    row("Quick Clean weekly") {
                        Toggle("Quick Clean weekly", isOn: $weekly)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.graphite)
                    }
                    Text(weeklyNote)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 6) {
                    row("Alerts") {
                        Toggle("Alerts", isOn: $alerts)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.graphite)
                    }
                    Text("When the disk is nearly full, or memory pressure stays high. At most once a day each.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// "Clears caches and logs once a week. Last run 3 days ago."
    private var weeklyNote: String {
        var text = "Clears caches and logs once a week, quietly."
        if let last = UserDefaults.standard.object(forKey: QuickActions.lastCleanKey) as? Date {
            text += " Last run \(last.formatted(.relative(presentation: .named)))."
        }
        return text
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(Theme.body.weight(.medium)).foregroundStyle(Theme.ink)
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
