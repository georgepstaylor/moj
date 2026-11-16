import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The standard macOS settings window: one toolbar tab per area.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updates: UpdateState

    var body: some View {
        TabView {
            GeneralSettings(appState: appState, updates: updates)
                .tabItem { Label("General", systemImage: "gearshape") }
            TypingSettings()
                .tabItem { Label("Typing", systemImage: "keyboard") }
            AppsSettings()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            EmojiSettings()
                .tabItem { Label("Emoji", systemImage: "face.smiling") }
        }
        .frame(width: 500)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updates: UpdateState

    @AppStorage(PrefKey.enabled) private var enabled = true
    @State private var launchAtLogin = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Emoji autocomplete")
                    Text("Suggest emoji when you type \(Preferences.trigger) followed by a name, in any app.")
                }
                Toggle(isOn: $launchAtLogin) {
                    Text("Open at login")
                    if loginStatus == .requiresApproval {
                        Text("Allow moj in System Settings → General → Login Items.")
                    }
                }
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent {
                    if appState.tapRunning {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { openAccessibilitySettings() }
                    }
                } label: {
                    Text("Accessibility")
                    Text(appState.tapRunning
                         ? "moj can see what you type and replace shortcodes."
                         : "Needed to see what you type and replace shortcodes. Turn on moj in Privacy & Security → Accessibility.")
                }
            } header: {
                Text("Permissions")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                LabeledContent("Version") {
                    HStack {
                        Text(updates.version).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Check for Updates…") { updates.checkForUpdates() }
                            .disabled(!updates.canCheck)
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .frame(height: 376)
        .onAppear(perform: refreshLoginStatus)
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let isOn = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        guard on != isOn else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }
}

// MARK: - Typing

private struct TypingSettings: View {
    @AppStorage(PrefKey.trigger) private var trigger = ":"
    @AppStorage(PrefKey.requireBoundary) private var requireBoundary = true
    @AppStorage(PrefKey.minChars) private var minChars = 2
    @AppStorage(PrefKey.autoReplaceClosing) private var autoReplaceClosing = true
    @AppStorage(PrefKey.usePaste) private var usePaste = false
    @State private var sample = ""

    var body: some View {
        Form {
            Section {
                Picker("Trigger key", selection: $trigger) {
                    Text("Colon  :").tag(":")
                    Text("Semicolon  ;").tag(";")
                    Text("Backslash  \\").tag("\\")
                }
                Picker("Show suggestions after", selection: $minChars) {
                    ForEach(1...4, id: \.self) { n in
                        Text("\(n) character\(n == 1 ? "" : "s")").tag(n)
                    }
                }
                Toggle(isOn: $requireBoundary) {
                    Text("Only at the start of a word")
                    Text("So times like 12\(trigger)30 and links don't bring up suggestions.")
                }
            } header: {
                Text("Suggestions")
            }

            Section {
                Toggle(isOn: $autoReplaceClosing) {
                    Text("Replace complete shortcodes")
                    Text("Typing \(trigger)tada\(trigger) turns straight into 🎉.")
                }
                Toggle(isOn: $usePaste) {
                    Text("Insert using the clipboard")
                    Text("Try this if emoji don't appear in some apps. Your clipboard is restored straight after.")
                }
            } header: {
                Text("Inserting")
            }

            Section {
                TextField("Try it", text: $sample, prompt: Text("Type \(trigger)fire or \(trigger)tada…"))
                    .labelsHidden()
            } header: {
                Text("Try it")
            } footer: {
                Text("↑ ↓ to choose · Return or Tab to insert · Esc to dismiss")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(height: 510)
    }
}

// MARK: - Apps

private struct AppsSettings: View {
    @AppStorage(PrefKey.excludedApps) private var excludedRaw = Preferences.defaultExcluded.joined(separator: "\n")

    private var excluded: [String] {
        excludedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section {
                if excluded.isEmpty {
                    Text("moj works in every app.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                ForEach(excluded, id: \.self) { id in
                    HStack(spacing: 10) {
                        AppIcon(bundleID: id)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppInfo.name(for: id))
                            Text(AppInfo.isInstalled(id) ? id : "Not installed")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            remove(id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                        .help("Turn moj back on in \(AppInfo.name(for: id))")
                    }
                }
            } header: {
                Text("Turned off in")
            } footer: {
                HStack {
                    Text("For apps with their own emoji autocomplete, like Slack.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Add App") {
                        let running = runningApps()
                        if !running.isEmpty {
                            Section("Open apps") {
                                ForEach(running, id: \.self) { id in
                                    Button { add(id) } label: {
                                        Label { Text(AppInfo.name(for: id)) } icon: { Image(nsImage: AppInfo.icon(for: id, size: 16)) }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Choose an App…", action: chooseApp)
                    }
                    .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
    }

    private func add(_ id: String) {
        guard !excluded.contains(id) else { return }
        excludedRaw = (excluded + [id]).joined(separator: "\n")
    }

    private func remove(_ id: String) {
        excludedRaw = excluded.filter { $0 != id }.joined(separator: "\n")
    }

    private func runningApps() -> [String] {
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !excluded.contains($0) && $0 != Bundle.main.bundleIdentifier }
        return Array(Set(ids)).sorted { AppInfo.name(for: $0).localizedCaseInsensitiveCompare(AppInfo.name(for: $1)) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Turn Off moj"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }
}

private struct AppIcon: View {
    let bundleID: String
    var body: some View {
        Image(nsImage: AppInfo.icon(for: bundleID, size: 28))
            .resizable()
            .frame(width: 28, height: 28)
    }
}

private enum AppInfo {
    static func url(for id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    /// Names for the default exclusions, so they read well even when the app isn't installed.
    private static let knownNames = ["com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord"]

    static func isInstalled(_ id: String) -> Bool { url(for: id) != nil }

    static func name(for id: String) -> String {
        guard let url = url(for: id) else { return knownNames[id] ?? id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for id: String, size: CGFloat) -> NSImage {
        let image = url(for: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        image.size = NSSize(width: size, height: size)
        return image
    }
}

// MARK: - Emoji

private struct EmojiSettings: View {
    @State private var frequent = EmojiStore.shared.frequentlyUsed
    @State private var search = ""
    @State private var copied: String?

    private var results: [Emoji] {
        search.isEmpty ? [] : EmojiStore.shared.search(search, limit: 40)
    }

    var body: some View {
        Form {
            Section {
                if frequent.isEmpty {
                    Text("Emoji you pick show up here, and move up the suggestions.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    EmojiGrid(emoji: frequent, copied: $copied)
                }
            } header: {
                HStack {
                    Text("Frequently used")
                    Spacer()
                    if !frequent.isEmpty {
                        Button("Clear") {
                            EmojiStore.shared.resetUsage()
                            frequent = []
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }

            Section {
                TextField("Search", text: $search, prompt: Text("Search shortcodes, e.g. heart"))
                    .labelsHidden()
                if !search.isEmpty {
                    if results.isEmpty {
                        Text("No emoji match “\(search)”.").foregroundStyle(.secondary)
                    } else {
                        EmojiGrid(emoji: results, copied: $copied)
                    }
                }
            } header: {
                Text("Look up a shortcode")
            } footer: {
                Text(copied.map { "Copied \($0)" } ?? "Click an emoji to copy it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
        .onAppear { frequent = EmojiStore.shared.frequentlyUsed }
    }
}

private struct EmojiGrid: View {
    let emoji: [Emoji]
    @Binding var copied: String?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(emoji) { item in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.char, forType: .string)
                    copied = "\(item.char)  \(Preferences.trigger)\(item.shortcode)\(Preferences.trigger)"
                } label: {
                    Text(item.char)
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(Preferences.trigger)\(item.shortcode)\(Preferences.trigger)")
            }
        }
        .padding(.vertical, 4)
    }
}
