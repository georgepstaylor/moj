import AppKit
import SwiftUI

/// Borderless, non-activating floating panel so the target app keeps keyboard focus.
final class PopupPanel: NSPanel {
    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 30
    static let padding: CGFloat = 6

    private let model: PopupModel

    init(model: PopupModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = NSHostingView(rootView: PopupView(model: model))
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(near caret: NSRect?) {
        let height = CGFloat(model.results.count) * Self.rowHeight + Self.padding * 2 + 22
        let anchor = caret ?? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 1, height: 18))
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: anchor.minX - 8, y: anchor.minY - height - 4)
        if origin.y < bounds.minY { origin.y = anchor.maxY + 4 }  // flip above caret
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - Self.width - 4)

        setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
        orderFrontRegardless()
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(":\(model.query)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22, alignment: .leading)

            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, emoji in
                HStack(spacing: 10) {
                    Text(emoji.char).font(.system(size: 18))
                        .frame(width: 24)
                    Text(":\(emoji.shortcode):")
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if index == model.selected {
                        Text("↩").font(.system(size: 11)).opacity(0.7)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: PopupPanel.rowHeight)
                .foregroundStyle(index == model.selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index == model.selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .onHover { if $0 { model.selected = index } }
                .onTapGesture { model.onPick(index) }
            }
        }
        .padding(.horizontal, PopupPanel.padding)
        .padding(.vertical, PopupPanel.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }
}
