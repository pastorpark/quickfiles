import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    private let store: SettingsStore
    private let scanner = RecentFileScanner()
    private var panel: NSPanel?
    @Published var items: [FileItem] = []
    @Published var searchableItems: [FileItem] = []
    @Published var isLoading = false

    init(store: SettingsStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let root = QuickAccessView(store: store, controller: self)
            let hosting = NSHostingController(rootView: root)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentViewController = hosting
            self.panel = panel
        }

        refresh()
        centerPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    @objc private func appDidResignActive() {
        hide()
    }

    func refresh() {
        isLoading = true
        let folders = store.scanFolders
        let excluded = store.excludedFolders
        let bookmarks = store.bookmarks
        let limit = store.maxRecentFiles

        Task {
            let scanned = await scanner.scan(
                folders: folders,
                excludedFolders: excluded,
                bookmarks: bookmarks
            )
            await MainActor.run {
                self.searchableItems = scanned
                self.items = scanned.prefix(max(1, limit)).map { $0 }
                self.isLoading = false
            }
        }
    }

    func open(_ item: FileItem) {
        NSWorkspace.shared.open(item.url)
        hide()
    }

    func reveal(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        hide()
    }


    func copy(_ item: FileItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }

    var isQuickPanelActive: Bool {
        panel?.isVisible == true && panel?.isKeyWindow == true
    }

    func move(_ item: FileItem, to folder: URL) {
        let destination = availableDestinationURL(for: item.url, in: folder)
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
            refresh()
        } catch {
            NSSound.beep()
        }
    }

    private func availableDestinationURL(for source: URL, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let name = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
            candidate = folder.appendingPathComponent(name)
            index += 1
        }

        return candidate
    }

    private func centerPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 90
        )
        panel.setFrameOrigin(origin)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
