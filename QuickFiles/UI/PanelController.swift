import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    private let store: SettingsStore
    private let scanner = RecentFileScanner()
    private let eventMonitor = FileSystemEventMonitor()
    private var panel: NSPanel?
    private var refreshTask: Task<Void, Never>?
    private var pendingChangesByPath: [String: FileSystemChange] = [:]
    private var pendingFullRefresh = false
    private var hasLoadedData = false
    private var isMonitoring = false
    private var cancellables = Set<AnyCancellable>()
    private var staysVisibleUntilClosed = false
    private var isPositioningPanel = false

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
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        observeSettings()
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
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 380),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentViewController = hosting
            self.panel = panel
        }

        eventMonitor.flush()
        if !hasLoadedData {
            refresh()
        }

        staysVisibleUntilClosed = false
        centerPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel?.alphaValue = 1.0
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }

    func hide() {
        staysVisibleUntilClosed = false
        panel?.alphaValue = 1.0
        panel?.orderOut(nil)
    }

    func keepVisibleUntilClosed() {
        staysVisibleUntilClosed = true
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !staysVisibleUntilClosed else { return }
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        guard panel?.isVisible == true, !isPositioningPanel else { return }
        keepVisibleUntilClosed()
    }

    @objc private func appDidResignActive() {
        guard !staysVisibleUntilClosed else { return }
        hide()
    }

    @objc private func workspaceDidWake() {
        refresh(showLoading: false)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        restartEventMonitor()
        refresh(showLoading: false)
    }

    func refresh(showLoading: Bool = true) {
        if refreshTask != nil {
            pendingFullRefresh = true
            if showLoading {
                isLoading = true
            }
            return
        }
        performRefresh(changes: nil, showLoading: showLoading)
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
            hide()
        } catch {
            NSSound.beep()
        }
    }

    private func observeSettings() {
        store.$scanFolders
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.restartEventMonitor()
                self.refresh(showLoading: false)
            }
            .store(in: &cancellables)

        store.$excludedFolders
            .dropFirst()
            .sink { [weak self] _ in
                self?.refresh(showLoading: false)
            }
            .store(in: &cancellables)

        store.$excludedExtensions
            .dropFirst()
            .sink { [weak self] _ in
                self?.refresh(showLoading: false)
            }
            .store(in: &cancellables)

        store.$maxRecentFiles
            .dropFirst()
            .sink { [weak self] limit in
                guard let self else { return }
                self.items = Array(self.searchableItems.prefix(max(1, limit)))
            }
            .store(in: &cancellables)
    }

    private func restartEventMonitor() {
        guard isMonitoring else { return }
        eventMonitor.start(folders: store.scanFolders.map(\.url)) { [weak self] changes, needsFullRescan in
            Task { @MainActor [weak self] in
                self?.receiveFileChanges(changes, needsFullRescan: needsFullRescan)
            }
        }
    }

    private func receiveFileChanges(_ changes: [FileSystemChange], needsFullRescan: Bool) {
        let relevantChanges = changes.filter(isRelevantChange)
        guard !relevantChanges.isEmpty || needsFullRescan else { return }

        if refreshTask != nil {
            if needsFullRescan {
                pendingFullRefresh = true
                pendingChangesByPath.removeAll(keepingCapacity: true)
            } else if !pendingFullRefresh {
                mergePendingChanges(relevantChanges)
            }
            return
        }

        if needsFullRescan {
            performRefresh(changes: nil, showLoading: false)
        } else {
            performRefresh(changes: relevantChanges, showLoading: false)
        }
    }

    private func isRelevantChange(_ change: FileSystemChange) -> Bool {
        let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
        let scanPaths = store.scanFolders.map { $0.url.standardizedFileURL.path }
        guard let scanPath = scanPaths.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            return false
        }

        let excludedPaths = store.excludedFolders.map { $0.url.standardizedFileURL.path }
        if excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }

        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if store.excludedExtensions.contains(pathExtension) {
            return false
        }

        return !path
            .dropFirst(scanPath.count)
            .split(separator: "/")
            .contains { $0.hasPrefix(".") }
    }

    private func mergePendingChanges(_ changes: [FileSystemChange]) {
        for change in changes {
            if let existing = pendingChangesByPath[change.path] {
                pendingChangesByPath[change.path] = FileSystemChange(
                    path: change.path,
                    flags: existing.flags | change.flags
                )
            } else {
                pendingChangesByPath[change.path] = change
            }
        }
    }

    private func performRefresh(changes: [FileSystemChange]?, showLoading: Bool) {
        if showLoading {
            isLoading = true
        }

        let folders = store.scanFolders
        let excluded = store.excludedFolders
        let excludedExtensions = store.excludedExtensions
        let limit = store.maxRecentFiles

        refreshTask = Task { [weak self] in
            guard let self else { return }
            let scanned: [FileItem]
            if let changes {
                scanned = await scanner.applyChanges(
                    changes,
                    folders: folders,
                    excludedFolders: excluded,
                    excludedExtensions: excludedExtensions
                )
            } else {
                scanned = await scanner.scan(
                    folders: folders,
                    excludedFolders: excluded,
                    excludedExtensions: excludedExtensions
                )
            }

            guard !Task.isCancelled else {
                finishRefresh()
                return
            }

            searchableItems = scanned
            items = Array(scanned.prefix(max(1, limit)))
            hasLoadedData = true
            finishRefresh()
        }
    }

    private func finishRefresh() {
        refreshTask = nil
        isLoading = false

        if pendingFullRefresh {
            pendingFullRefresh = false
            pendingChangesByPath.removeAll(keepingCapacity: true)
            performRefresh(changes: nil, showLoading: false)
            return
        }

        guard !pendingChangesByPath.isEmpty else { return }
        let changes = Array(pendingChangesByPath.values)
        pendingChangesByPath.removeAll(keepingCapacity: true)
        performRefresh(changes: changes, showLoading: false)
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
        isPositioningPanel = true
        panel.setFrameOrigin(origin)
        DispatchQueue.main.async { [weak self] in
            self?.isPositioningPanel = false
        }
    }

    deinit {
        eventMonitor.stop()
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
