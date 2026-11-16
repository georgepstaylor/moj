import Foundation

enum PrefKey {
    static let enabled = "enabled"
    static let trigger = "trigger"
    static let requireBoundary = "requireBoundary"
    static let minChars = "minChars"
    static let autoReplaceClosing = "autoReplaceClosing"
    static let usePaste = "usePaste"
    static let excludedApps = "excludedApps"
}

/// Thin typed wrapper over UserDefaults; SwiftUI views bind the same keys with @AppStorage.
enum Preferences {
    static let defaultExcluded = [
        "com.tinyspeck.slackmacgap",  // Slack has its own emoji autocomplete
        "com.hnc.Discord",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.enabled: true,
            PrefKey.trigger: ":",
            PrefKey.requireBoundary: true,
            PrefKey.minChars: 2,
            PrefKey.autoReplaceClosing: true,
            PrefKey.usePaste: false,
            PrefKey.excludedApps: defaultExcluded.joined(separator: "\n"),
        ])
    }

    private static var d: UserDefaults { .standard }

    static var enabled: Bool { d.bool(forKey: PrefKey.enabled) }
    static var trigger: String {
        let t = d.string(forKey: PrefKey.trigger) ?? ":"
        return t.isEmpty ? ":" : String(t.prefix(1))
    }
    static var requireBoundary: Bool { d.bool(forKey: PrefKey.requireBoundary) }
    static var minChars: Int { max(1, d.integer(forKey: PrefKey.minChars)) }
    static var autoReplaceClosing: Bool { d.bool(forKey: PrefKey.autoReplaceClosing) }
    static var usePaste: Bool { d.bool(forKey: PrefKey.usePaste) }
    static var excludedApps: [String] {
        (d.string(forKey: PrefKey.excludedApps) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
