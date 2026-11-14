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
    private var isDraggingFiles = false
    private var isPositioningPanel = false
    private var isPresentingModal = false

    private(set) var viewModel: PanelViewModel?

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
            let model = PanelViewModel(store: store, controller: self)
            viewModel = model
            let root = QuickAccessView(store: store, controller: self, model: model)
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

    func setDraggingFiles(_ dragging: Bool) {
        isDraggingFiles = dragging
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !staysVisibleUntilClosed, !isDraggingFiles, !isPresentingModal else { return }
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        guard panel?.isVisible == true, !isPositioningPanel else { return }
        keepVisibleUntilClosed()
    }

    @objc private func appDidResignActive() {
        guard !staysVisibleUntilClosed, !isDraggingFiles, !isPresentingModal else { return }
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

    /// Run an AppKit modal (NSOpenPanel / NSAlert runModal) without the quick panel hiding itself.
    func runModal<T>(_ body: () -> T) -> T {
        isPresentingModal = true
        defer {
            isPresentingModal = false
            panel?.makeKeyAndOrderFront(nil)
        }
        return body()
    }

    func open(_ item: FileItem) {
        open([item])
    }

    /// Opens every item once (duplicates by standardized path collapse); hides the panel once.
    func open(_ items: [FileItem]) {
        let urls = Self.uniqueURLs(for: items)
        guard !urls.isEmpty else { return }

        if urls.count > Self.batchOpenConfirmationThreshold {
            let confirmed = runModal { () -> Bool in
                let alert = NSAlert()
                alert.messageText = "\(urls.count)개 파일을 여시겠습니까?"
                alert.addButton(withTitle: "열기")
                alert.addButton(withTitle: "취소")
                return alert.runModal() == .alertFirstButtonReturn
            }
            guard confirmed else { return }
        }

        for url in urls {
            NSWorkspace.shared.open(url)
        }
        hide()
    }

    func reveal(_ item: FileItem) {
        reveal([item])
    }

    func reveal(_ items: [FileItem]) {
        let urls = Self.uniqueURLs(for: items)
        guard !urls.isEmpty else { return }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
        hide()
    }

    func copy(_ item: FileItem) {
        copy([item])
    }

    func copy(_ items: [FileItem]) {
        let urls = Self.uniqueURLs(for: items)
        guard !urls.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    /// Event ownership for the local key monitor: only the key quick panel takes keys.
    func ownsKeyEvent(_ event: NSEvent) -> Bool {
        guard let panel, panel.isVisible, panel.isKeyWindow, !isPresentingModal else { return false }
        return event.window === panel && panel.attachedSheet == nil
    }

    /// Make the window itself first responder (ends text editing, results get keyboard focus).
    func focusResults() {
        panel?.makeFirstResponder(nil)
    }

    func move(_ item: FileItem, to folder: URL) {
        let sourceParent = item.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let destinationFolder = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard sourceParent != destinationFolder else {
            hide()
            return
        }

        var startIndex = 1
        for _ in 0..<5 {
            let destination = availableDestinationURL(for: item.url, in: folder, startingAt: startIndex)
            do {
                try FileManager.default.moveItem(at: item.url, to: destination.url)
                hide()
                return
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                // Destination appeared between the existence check and the move; try the next suffix.
                startIndex = destination.index + 1
            } catch {
                break
            }
        }
        NSSound.beep()
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

    /// Finds the first non-existing destination starting at `startIndex`
    /// (1 = original name, 2+ = "name N.ext") and returns it with the index used.
    private func availableDestinationURL(for source: URL, in folder: URL, startingAt startIndex: Int) -> (url: URL, index: Int) {
        var index = startIndex
        while true {
            let candidate = destinationURL(for: source, in: folder, index: index)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return (candidate, index)
            }
            index += 1
        }
    }

    private func destinationURL(for source: URL, in folder: URL, index: Int) -> URL {
        guard index > 1 else { return folder.appendingPathComponent(source.lastPathComponent) }
        let baseName = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        let name = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
        return folder.appendingPathComponent(name)
    }

    // MARK: - Batch helpers

    /// Above this many files, opening asks for confirmation first.
    private static let batchOpenConfirmationThreshold = 10

    /// Drops items pointing at the same standardized path, keeping the first occurrence's order.
    private static func uniqueURLs(for items: [FileItem]) -> [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(items.count)
        for item in items {
            let url = item.url.standardizedFileURL
            guard seenPaths.insert(url.path).inserted else { continue }
            urls.append(item.url)
        }
        return urls
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
