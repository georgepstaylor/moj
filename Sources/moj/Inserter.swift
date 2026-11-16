import AppKit
import ApplicationServices

/// Replaces the typed `:shortcode` with an emoji in the focused text field.
enum Inserter {
    static let marker: Int64 = 0x4D4F_4A21  // "MOJ!"

    private static let source = CGEventSource(stateID: .privateState)

    static func replace(typed: String, with emoji: String, usePaste: Bool) {
        // Best case: swap the text in one Accessibility edit, so nothing flickers.
        if replaceViaAccessibility(typed: typed, with: emoji) { return }

        // Fallback: select the shortcode, then type over it so it is replaced in one step.
        for _ in 0..<typed.count { post(keyCode: 123, flags: .maskShift) }  // ⇧←
        if usePaste {
            paste(emoji)
        } else {
            post(keyCode: 0, unicode: Array(emoji.utf16))
        }
    }

    // MARK: - Accessibility

    private static func replaceViaAccessibility(typed: String, with emoji: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return false }
        let element = focusedRef as! AXUIElement

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let caret = selectedRange(of: element), caret.length == 0
        else { return false }

        // AX ranges are in UTF-16 units. Make sure the text before the caret is what we expect.
        let typedLength = typed.utf16.count
        guard caret.location >= typedLength else { return false }
        let target = CFRange(location: caret.location - typedLength, length: typedLength)
        guard string(of: element, in: target) == typed else { return false }

        guard setSelectedRange(of: element, to: target) else { return false }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, emoji as CFString)

        // Some apps claim success without changing anything, so check the text actually changed.
        let inserted = CFRange(location: target.location, length: emoji.utf16.count)
        if result == .success, string(of: element, in: inserted) == emoji {
            _ = setSelectedRange(of: element, to: CFRange(location: inserted.location + inserted.length, length: 0))
            return true
        }
        _ = setSelectedRange(of: element, to: caret)  // put the caret back for the fallback
        return false
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        return AXValueGetValue(ref as! AXValue, .cfRange, &range) ? range : nil
    }

    private static func setSelectedRange(of element: AXUIElement, to range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private static func string(of element: AXUIElement, in range: CFRange) -> String? {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, value, &ref
        ) == .success else { return nil }
        return ref as? String
    }

    // MARK: - Synthesised keystrokes

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags = [], unicode: [UniChar]? = nil) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = flags
            if let unicode {
                e.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
    }

    private static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        pb.clearContents()
        pb.setString(text, forType: .string)
        post(keyCode: 9, flags: .maskCommand)  // ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pb.clearContents()
            if !saved.isEmpty { pb.writeObjects(saved) }
        }
    }
}
