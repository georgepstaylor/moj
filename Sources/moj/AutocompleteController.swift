import AppKit
import Combine

final class PopupModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Emoji] = []
    @Published var selected = 0
    var onPick: (Int) -> Void = { _ in }
}

/// Tracks what the user types system-wide and drives the suggestion popup.
final class AutocompleteController {
    private let store = EmojiStore.shared
    private let monitor = KeyMonitor()
    private let model = PopupModel()
    private lazy var panel = PopupPanel(model: model)

    private var capturing = false
    private var query = ""
    private var atBoundary = true
    private var observers: [NSObjectProtocol] = []

    var isRunning: Bool { monitor.isRunning }

    init() {
        monitor.onKeyDown = { [weak self] in self?.handleKey($0) ?? false }
        monitor.onMouseDown = { [weak self] in self?.handleMouse($0) ?? false }
        model.onPick = { [weak self] index in self?.commit(index: index) }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reset(boundary: true) })
    }

    @discardableResult
    func start() -> Bool { monitor.start() }

    // MARK: - Event handling

    private var popupVisible: Bool { panel.isVisible }

    private func handleMouse(_ event: CGEvent) -> Bool {
        // Clicks inside our popup are handled by SwiftUI; anything else cancels.
        if popupVisible && panel.frame.contains(NSEvent.mouseLocation) { return false }
        reset(boundary: true)
        return false
    }

    private func handleKey(_ event: CGEvent) -> Bool {
        guard Preferences.enabled, !isFrontmostExcluded() else {
            if capturing { reset(boundary: true) }
            return false
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            reset(boundary: true)
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 126, 125:  // up, down
            if popupVisible {
                move(keyCode == 126 ? -1 : 1)
                return true
            }
            reset(boundary: true)
            return false
        case 36, 76, 48:  // return, keypad enter, tab
            if popupVisible {
                commit(index: model.selected)
                return true
            }
            reset(boundary: true)
            return false
        case 53:  // escape
            let swallow = popupVisible
            reset(boundary: false)
            return swallow
        case 51:  // delete
            if capturing {
                if query.isEmpty {
                    reset(boundary: true)
                } else {
                    query.removeLast()
                    refresh()
                }
            } else {
                atBoundary = true
            }
            return false
        case 117, 123, 124, 115, 119, 116, 121:  // fwd-delete, arrows, home/end, page up/down
            reset(boundary: true)
            return false
        default:
            break
        }

        let typed = Self.characters(of: event)
        guard !typed.isEmpty else { return false }
        let trigger = Preferences.trigger

        if capturing {
            if typed == trigger {
                if Preferences.autoReplaceClosing, let emoji = store.exact(query) {
                    insert(emoji)
                    return true
                }
                // Treat as a fresh trigger (e.g. "::smile").
                query = ""
                refresh()
                return false
            }
            if typed.allSatisfy(Self.isShortcodeChar) {
                query += typed
                refresh()
                return false
            }
            reset(boundary: Self.isBoundary(typed))
            return false
        }

        if typed == trigger && (!Preferences.requireBoundary || atBoundary) {
            capturing = true
            query = ""
            return false
        }
        atBoundary = Self.isBoundary(typed)
        return false
    }

    // MARK: - State

    private func refresh() {
        guard capturing, query.count >= Preferences.minChars else {
            hidePanel()
            return
        }
        let results = store.search(query)
        guard !results.isEmpty else {
            hidePanel()
            return
        }
        model.query = query
        model.results = results
        model.selected = 0
        panel.show(near: CaretLocator.caretRect())
    }

    private func move(_ delta: Int) {
        let count = model.results.count
        guard count > 0 else { return }
        model.selected = (model.selected + delta + count) % count
    }

    private func commit(index: Int) {
        guard capturing, model.results.indices.contains(index) else { return }
        insert(model.results[index])
    }

    private func insert(_ emoji: Emoji) {
        store.recordUse(emoji)
        let typed = Preferences.trigger + query
        let usePaste = Preferences.usePaste
        reset(boundary: false)
        // Run after the current event has been swallowed.
        DispatchQueue.main.async {
            Inserter.replace(typed: typed, with: emoji.char, usePaste: usePaste)
        }
    }

    private func reset(boundary: Bool) {
        capturing = false
        query = ""
        atBoundary = boundary
        hidePanel()
    }

    private func hidePanel() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func isFrontmostExcluded() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Preferences.excludedApps.contains(id)
    }

    // MARK: - Helpers

    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    private static func isShortcodeChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "+" || c == "-"
    }

    private static func isBoundary(_ s: String) -> Bool {
        s.allSatisfy { $0.isWhitespace || $0.isNewline || ($0.isPunctuation && $0 != "_") || $0.isSymbol }
    }
}
