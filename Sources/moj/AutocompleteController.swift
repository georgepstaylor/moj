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

    /// What the user has typed since we last lost track of the caret (click, arrow keys,
    /// app switch, shortcut). Backspace pops from it, so deleting back into `:word`
    /// brings the suggestions back, like Slack.
    private var buffer: [Character] = []
    /// Whether the text just before `buffer` ends a word.
    private var startsAtBoundary = true
    /// Position in `buffer` of a trigger the user dismissed with Escape.
    private var dismissedAt: Int?
    private var query = ""
    private static let maxBuffer = 128
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
            if !buffer.isEmpty { reset(boundary: true) }
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
            if let active = activeTrigger() { dismissedAt = active.index }
            hidePanel()
            return swallow
        case 51:  // delete
            if flags.contains(.maskAlternate) {  // option-delete removes a whole word
                reset(boundary: true)
            } else if buffer.isEmpty {
                startsAtBoundary = true
            } else {
                buffer.removeLast()
                if let d = dismissedAt, d >= buffer.count { dismissedAt = nil }
                update()
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

        if typed == Preferences.trigger, Preferences.autoReplaceClosing,
           let active = activeTrigger(), active.index != dismissedAt,
           let emoji = store.exact(active.query) {
            query = active.query
            insert(emoji)
            return true
        }

        append(typed)
        update()
        return false
    }

    // MARK: - State

    /// The trigger and shortcode just before the caret, if the user is typing one.
    private func activeTrigger() -> (index: Int, query: String)? {
        var i = buffer.count
        while i > 0, Self.isShortcodeChar(buffer[i - 1]) { i -= 1 }
        guard i > 0, triggerStarts(at: i - 1) else { return nil }
        return (i - 1, String(buffer[i...]))
    }

    /// Whether the trigger at `index` can start a shortcode.
    private func triggerStarts(at index: Int) -> Bool {
        guard String(buffer[index]) == Preferences.trigger else { return false }
        guard Preferences.requireBoundary else { return true }
        guard index > 0 else { return startsAtBoundary }
        let before = buffer[index - 1]
        if Self.isBoundary(String(before)) { return true }
        // A trigger straight after an unmatched code, e.g. "notreal:smile".
        var j = index
        while j > 0, Self.isShortcodeChar(buffer[j - 1]) { j -= 1 }
        return j < index && j > 0 && triggerStarts(at: j - 1)
    }

    private func append(_ text: String) {
        buffer.append(contentsOf: text)
        let overflow = buffer.count - Self.maxBuffer
        guard overflow > 0 else { return }
        startsAtBoundary = Self.isBoundary(String(buffer[overflow - 1]))
        buffer.removeFirst(overflow)
        if let d = dismissedAt { dismissedAt = d >= overflow ? d - overflow : nil }
    }

    private func update() {
        guard let active = activeTrigger(), active.index != dismissedAt else {
            query = ""
            hidePanel()
            return
        }
        query = active.query
        refresh()
    }

    private func refresh() {
        guard query.count >= Preferences.minChars else {
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
        guard popupVisible, model.results.indices.contains(index) else { return }
        insert(model.results[index])
    }

    private func insert(_ emoji: Emoji) {
        store.recordUse(emoji)
        let typed = Preferences.trigger + query
        let usePaste = Preferences.usePaste
        if let active = activeTrigger() { buffer.removeSubrange(active.index...) }
        buffer.append(contentsOf: emoji.char)
        dismissedAt = nil
        query = ""
        hidePanel()
        // Run after the current event has been swallowed.
        DispatchQueue.main.async {
            Inserter.replace(typed: typed, with: emoji.char, usePaste: usePaste)
        }
    }

    private func reset(boundary: Bool) {
        buffer.removeAll()
        startsAtBoundary = boundary
        dismissedAt = nil
        query = ""
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
