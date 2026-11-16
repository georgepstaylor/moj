import AppKit
import ApplicationServices

/// Finds the text caret on screen via the Accessibility API.
enum CaretLocator {
    /// Caret rect in Cocoa screen coordinates (origin bottom-left), or nil if unavailable.
    static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)

        // Many apps return an empty rect for a zero-length range, so measure the previous character.
        var probe = range
        if probe.length == 0 && probe.location > 0 {
            probe = CFRange(location: probe.location - 1, length: 1)
        }
        guard let probeValue = AXValueCreate(.cfRange, &probe) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, probeValue, &boundsRef
        ) == .success, let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect)
        guard rect.width > 0 || rect.height > 0, rect.origin != .zero else { return nil }

        // AX uses top-left origin relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.maxX, y: primaryHeight - rect.maxY, width: 1, height: rect.height)
    }
}
