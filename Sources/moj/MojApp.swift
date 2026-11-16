import AppKit
import SwiftUI

@main
struct MojApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: delegate.appState, updates: delegate.updateState)
        } label: {
            Image(systemName: "face.smiling")
        }

        Settings {
            SettingsView(appState: delegate.appState, updates: delegate.updateState)
        }
    }
}

final class AppState: ObservableObject {
    @Published var hasAccessibility = KeyMonitor.hasAccessibility
    @Published var tapRunning = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let updateState = UpdateState()
    private let controller = AutocompleteController()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        _ = EmojiStore.shared  // build the index up front

        if !KeyMonitor.hasAccessibility { KeyMonitor.promptForAccessibility() }
        tryStart()
        // Accessibility can be granted (or revoked) while we run; poll until the tap is live.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.tryStart()
        }
    }

    /// Opening moj again (Finder, Spotlight, `open`) shows Settings, since it has no Dock icon or window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// SwiftUI only opens the Settings scene through its own "Settings…" menu item (or SettingsLink),
    /// so press that item in the app menu. moj has no menu bar, but the menu still exists.
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," })
        else { return }
        appMenu.performActionForItem(at: index)
    }

    private func tryStart() {
        let trusted = KeyMonitor.hasAccessibility
        if trusted && !controller.isRunning { controller.start() }
        if appState.hasAccessibility != trusted { appState.hasAccessibility = trusted }
        if appState.tapRunning != controller.isRunning { appState.tapRunning = controller.isRunning }
    }
}

struct MenuContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updates: UpdateState
    @AppStorage(PrefKey.enabled) private var enabled = true
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !appState.tapRunning {
            Text("⚠️ Accessibility access needed")
            Button("Open Accessibility Settings…") { openAccessibilitySettings() }
            Divider()
        }
        Toggle("Enabled", isOn: $enabled)
        Divider()
        Button("Settings…") {
            // moj has no Dock icon, so bring it forward or the window opens behind other apps.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheck)
        Divider()
        Button("Quit moj") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

func openAccessibilitySettings() {
    KeyMonitor.promptForAccessibility()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}
