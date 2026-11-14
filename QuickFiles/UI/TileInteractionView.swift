import AppKit
import SwiftUI

/// One AppKit view per tile: replaces SwiftUI tap/drag/context-menu gestures so that
/// clicks report their modifier flags immediately and a drag can carry several files.
struct TileInteractionView: NSViewRepresentable {
    let itemID: FileItem.ID
    var isSelected: (FileItem.ID) -> Bool
    /// Selection change for a click (called at mouseDown, or at mouseUp for the deferred case).
    var onPress: (FileItem.ID, NSEvent.ModifierFlags) -> Void
    /// Double click.
    var onActivate: (FileItem.ID, NSEvent.ModifierFlags) -> Void
    /// Right/control click: make sure the clicked item is part of the selection before the menu shows.
    var onContextSelection: (FileItem.ID) -> Void
    var makeMenu: (FileItem.ID) -> NSMenu?
    /// URLs to drag when a drag starts on this tile.
    var dragURLs: (FileItem.ID) -> [URL]
    var onDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        // Views are reused, so every stored value must be refreshed here.
        apply(to: nsView)
    }

    private func apply(to view: InteractionNSView) {
        view.itemID = itemID
        view.isSelected = isSelected
        view.onPress = onPress
        view.onActivate = onActivate
        view.onContextSelection = onContextSelection
        view.makeMenu = makeMenu
        view.dragURLs = dragURLs
        view.onDragStateChange = onDragStateChange
    }

    final class InteractionNSView: NSView, NSDraggingSource {
        var itemID: FileItem.ID = ""
        var isSelected: (FileItem.ID) -> Bool = { _ in false }
        var onPress: (FileItem.ID, NSEvent.ModifierFlags) -> Void = { _, _ in }
        var onActivate: (FileItem.ID, NSEvent.ModifierFlags) -> Void = { _, _ in }
        var onContextSelection: (FileItem.ID) -> Void = { _ in }
        var makeMenu: (FileItem.ID) -> NSMenu? = { _ in nil }
        var dragURLs: (FileItem.ID) -> [URL] = { _ in [] }
        var onDragStateChange: (Bool) -> Void = { _ in }

        private var mouseDownEvent: NSEvent?
        private var pendingSelectOnly = false
        private var dragStarted = false

        // MARK: - Window / responder behaviour

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // The SwiftUI tile stays the accessible element.
        override func isAccessibilityElement() -> Bool { false }

        // NOTE: scrollWheel is deliberately not overridden, so scrolling keeps
        // travelling to the enclosing scroll view.

        // MARK: - Mouse

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onContextSelection(itemID)
                if let menu = makeMenu(itemID) {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
                return
            }

            if event.clickCount >= 2 {
                dragStarted = false
                mouseDownEvent = nil
                pendingSelectOnly = false
                onActivate(itemID, event.modifierFlags)
                return
            }

            mouseDownEvent = event
            dragStarted = false

            let flags = event.modifierFlags.intersection([.command, .shift])
            if !flags.isEmpty || !isSelected(itemID) {
                onPress(itemID, event.modifierFlags)
                pendingSelectOnly = false
            } else {
                // Plain click on an already selected tile: delay the collapse to mouseUp
                // so that dragging one member of a multi-selection keeps the selection.
                pendingSelectOnly = true
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragStarted else { return }

            let reference = mouseDownEvent ?? event
            let start = reference.locationInWindow
            let current = event.locationInWindow
            let distance = hypot(current.x - start.x, current.y - start.y)
            guard distance > 4 else { return }

            dragStarted = true
            pendingSelectOnly = false

            let urls = dragURLs(itemID)
            guard !urls.isEmpty else { return }

            let anchor = convert(start, from: nil)
            let items: [NSDraggingItem] = urls.enumerated().map { index, url in
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let image = NSWorkspace.shared.icon(forFile: url.path)
                let offset = CGFloat(min(index, 5)) * 6
                let frame = NSRect(
                    x: anchor.x - 24 + offset,
                    y: anchor.y - 24 - offset,
                    width: 48,
                    height: 48
                )
                draggingItem.setDraggingFrame(frame, contents: image)
                return draggingItem
            }

            onDragStateChange(true)
            beginDraggingSession(with: items, event: reference, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if pendingSelectOnly && !dragStarted {
                onPress(itemID, [])
            }
            pendingSelectOnly = false
            mouseDownEvent = nil
            dragStarted = false
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            onContextSelection(itemID)
            return makeMenu(itemID)
        }

        // MARK: - NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            dragStarted = false
            onDragStateChange(false)
        }
    }
}

/// Menu item that runs a closure instead of an ObjC target/action pair.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}
