import AppKit
import Quartz

@MainActor
final class QuickPanelWindow: NSPanel, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    /// Snapshot of the URLs to preview (unique, display order). Set by PanelController before opening.
    var previewURLs: [URL] = []
    /// True only while PanelController is actively requesting/holding preview control.
    var wantsPreviewControl = false
    /// Exact Cmd+Y / Space / Esc that Quick Look itself did not handle while it is key.
    var onPreviewToggleKey: (() -> Void)?
    /// Called (on main) after Quick Look stopped using this window as its controller.
    var onPreviewControlEnded: (() -> Void)?
    private var savedPreviewLevel: NSWindow.Level?

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { wantsPreviewControl && isVisible && !previewURLs.isEmpty }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
            savedPreviewLevel = panel.level
            panel.level = NSWindow.Level(rawValue: level.rawValue + 1)   // above our .floating panel
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            if (panel.dataSource as AnyObject?) === self { panel.dataSource = nil }
            if (panel.delegate as AnyObject?) === self { panel.delegate = nil }
            if let savedPreviewLevel { panel.level = savedPreviewLevel }
            savedPreviewLevel = nil
            onPreviewControlEnded?()
        }
    }

    // QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }

    // QLPreviewPanelDelegate — only receives events Quick Look did not handle itself.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let isCmdY = event.keyCode == 16 && mods == .command
        let isSpaceOrEsc = (event.keyCode == 49 || event.keyCode == 53) && mods.isEmpty
        guard isCmdY || isSpaceOrEsc else { return false }
        onPreviewToggleKey?()
        return true
    }
}
