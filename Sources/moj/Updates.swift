import AppKit
import Combine
import Sparkle

/// Sparkle updates. The feed (SUFeedURL) is appcast.xml on the public releases repo's main branch,
/// and only archives signed with the matching private key (SUPublicEDKey) install.
enum Updates {
    static let controller = SPUStandardUpdaterController(
        // Unbundled `swift run` builds have no feed or key, so don't start the updater there.
        startingUpdater: Bundle.main.bundleURL.pathExtension == "app",
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static var updater: SPUUpdater { controller.updater }
}

/// Mirrors Sparkle's state for SwiftUI, so "Check for Updates…" greys out while a check runs.
final class UpdateState: ObservableObject {
    @Published var canCheck = false
    @Published var automaticallyChecks: Bool {
        didSet { Updates.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        let updater = Updates.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        Updates.updater.checkForUpdates()
    }

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
