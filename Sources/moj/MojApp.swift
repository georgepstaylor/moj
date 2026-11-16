import AppKit
import ServiceManagement
import SwiftUI

@main
struct MojApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: delegate.appState)
        } label: {
            Image(systemName: "face.smiling")
        }

        Window("moj Settings", id: "settings") {
            SettingsView(appState: delegate.appState)
        }
        .windowResizability(.contentSize)
    }
}

final class AppState: ObservableObject {
    @Published var hasAccessibility = KeyMonitor.hasAccessibility
    @Published var tapRunning = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
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

    private func tryStart() {
        let trusted = KeyMonitor.hasAccessibility
        if trusted && !controller.isRunning { controller.start() }
        if appState.hasAccessibility != trusted { appState.hasAccessibility = trusted }
        if appState.tapRunning != controller.isRunning { appState.tapRunning = controller.isRunning }
    }
}

struct MenuContent: View {
    @ObservedObject var appState: AppState
    @AppStorage(PrefKey.enabled) private var enabled = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !appState.tapRunning {
            Text("⚠️ Accessibility access needed")
            Button("Open Accessibility Settings…") { openAccessibilitySettings() }
            Divider()
        }
        Toggle("Enabled", isOn: $enabled)
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
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

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @AppStorage(PrefKey.enabled) private var enabled = true
    @AppStorage(PrefKey.trigger) private var trigger = ":"
    @AppStorage(PrefKey.requireBoundary) private var requireBoundary = true
    @AppStorage(PrefKey.minChars) private var minChars = 2
    @AppStorage(PrefKey.autoReplaceClosing) private var autoReplaceClosing = true
    @AppStorage(PrefKey.usePaste) private var usePaste = false
    @AppStorage(PrefKey.excludedApps) private var excludedRaw = Preferences.defaultExcluded.joined(separator: "\n")

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var tryText = ""

    private var excluded: [String] {
        excludedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: appState.tapRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.tapRunning ? .green : .orange)
                    Text(appState.tapRunning ? "Accessibility access granted" : "moj needs Accessibility access to see what you type")
                    Spacer()
                    if !appState.tapRunning {
                        Button("Grant Access…") { openAccessibilitySettings() }
                    }
                }
            }

            Section("General") {
                Toggle("Enable emoji autocomplete", isOn: $enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Behaviour") {
                Picker("Trigger character", selection: $trigger) {
                    Text(": (colon)").tag(":")
                    Text("; (semicolon)").tag(";")
                    Text("\\ (backslash)").tag("\\")
                }
                Stepper("Show suggestions after \(minChars) character\(minChars == 1 ? "" : "s")", value: $minChars, in: 1...5)
                Toggle("Only trigger at the start of a word", isOn: $requireBoundary)
                    .help("Avoids popping up when typing times like 12:30 or URLs.")
                Toggle("Replace complete shortcodes like :smile: automatically", isOn: $autoReplaceClosing)
                Toggle("Insert using the clipboard (more compatible, briefly replaces clipboard)", isOn: $usePaste)
            }

            Section("Try it") {
                TextField("Type \(trigger)fire or \(trigger)tada here…", text: $tryText)
                Text("Use ↑/↓ to choose, Return or Tab to insert, Esc to dismiss.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Disabled in these apps") {
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        Text(appName(for: id)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Button {
                            excludedRaw = excluded.filter { $0 != id }.joined(separator: "\n")
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add Running App") {
                    ForEach(runningApps(), id: \.self) { id in
                        Button(appName(for: id)) {
                            excludedRaw = (excluded + [id]).joined(separator: "\n")
                        }
                    }
                }
            }

            Section("Frequently used") {
                let frequent = EmojiStore.shared.frequentlyUsed
                if frequent.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                } else {
                    Text(frequent.map(\.char).joined(separator: " ")).font(.title2)
                    Button("Reset Usage History") { EmojiStore.shared.resetUsage() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }

    private func runningApps() -> [String] {
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !excluded.contains($0) && $0 != Bundle.main.bundleIdentifier }
        return Array(Set(ids)).sorted { appName(for: $0) < appName(for: $1) }
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
