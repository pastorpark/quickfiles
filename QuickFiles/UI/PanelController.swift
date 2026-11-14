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

    /// Moves the items, then hides the panel when nothing failed or reports the failure inside the panel.
    func moveAndReport(_ items: [FileItem], to folder: URL) async {
        let result = await move(items, to: folder)

        guard !result.failed.isEmpty else {
            hide()
            return
        }

        _ = runModal { () -> NSApplication.ModalResponse in
            let alert = NSAlert()
            alert.messageText = "\(result.moved.count)개 이동, \(result.failed.count)개 실패"
            alert.informativeText = result.failed.first?.error.localizedDescription ?? ""
            alert.addButton(withTitle: "확인")
            return alert.runModal()
        }
    }

    /// Runs the plan on a background task so large / cross-volume moves don't block the UI.
    func move(_ items: [FileItem], to folder: URL) async -> BatchMoveResult {
        let plan = Self.planMove(items.map(\.url), to: folder)
        var result = BatchMoveResult(skipped: plan.skipped)
        let toMove = plan.toMove
        let outcome = await Task.detached(priority: .userInitiated) { () -> BatchMoveOutcome in
            var outcome = BatchMoveOutcome()
            for url in toMove {
                do {
                    outcome.moved.append(try PanelController.moveFile(url, into: folder))
                } catch {
                    outcome.failed.append((url, error))
                }
            }
            return outcome
        }.value
        result.moved = outcome.moved
        result.failed = outcome.failed
        refresh(showLoading: false)
        return result
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
    nonisolated private static func availableDestinationURL(for source: URL, in folder: URL, startingAt startIndex: Int) -> (url: URL, index: Int) {
        var index = startIndex
        while true {
            let candidate = destinationURL(for: source, in: folder, index: index)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return (candidate, index)
            }
            index += 1
        }
    }

    nonisolated private static func destinationURL(for source: URL, in folder: URL, index: Int) -> URL {
        guard index > 1 else { return folder.appendingPathComponent(source.lastPathComponent) }
        let baseName = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        let name = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
        return folder.appendingPathComponent(name)
    }

    /// Moves `source` into `folder`, picking "name 2.ext", "name 3.ext"… on collisions, retrying up to 5 times
    /// when the destination appears mid-move (CocoaError.fileWriteFileExists). Returns the final URL.
    nonisolated private static func moveFile(_ source: URL, into folder: URL) throws -> URL {
        var startIndex = 1
        var lastError: Error?
        for _ in 0..<5 {
            let destination = availableDestinationURL(for: source, in: folder, startingAt: startIndex)
            do {
                try FileManager.default.moveItem(at: source, to: destination.url)
                return destination.url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                // Destination appeared between the existence check and the move; try the next suffix.
                lastError = error
                startIndex = destination.index + 1
            } catch {
                throw error
            }
        }

        guard let lastError else {
            // Unreachable: every attempt either moves the file, advances the suffix or throws.
            throw CocoaError(.fileWriteFileExists)
        }
        throw lastError
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

    /// Pure planning (no file system writes): splits the selection into items to move and items to skip.
    ///
    /// - Items already in the destination folder, and folders that contain the destination, are skipped.
    /// - Items whose ancestor folder is part of the list are dropped: they travel with that folder.
    nonisolated static func planMove(_ urls: [URL], to folder: URL) -> (toMove: [URL], skipped: [URL]) {
        let destinationPath = folder.resolvingSymlinksInPath().standardizedFileURL.path

        var seenPaths = Set<String>()
        var unique: [URL] = []
        unique.reserveCapacity(urls.count)
        for url in urls {
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            unique.append(url)
        }

        let itemPaths = unique.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }

        var toMove: [URL] = []
        var skipped: [URL] = []
        toMove.reserveCapacity(unique.count)

        for (offset, url) in unique.enumerated() {
            let itemPath = itemPaths[offset]

            let parentPath = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            guard parentPath != destinationPath else {
                skipped.append(url)
                continue
            }

            guard destinationPath != itemPath, !destinationPath.hasPrefix(itemPath + "/") else {
                skipped.append(url)
                continue
            }

            let hasListedAncestor = itemPaths.contains { otherPath in
                otherPath != itemPath && itemPath.hasPrefix(otherPath + "/")
            }
            guard !hasListedAncestor else { continue }

            toMove.append(url)
        }

        return (toMove, skipped)
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

// MARK: - Batch move

/// Outcome of a batch move: what moved, what was skipped by the plan, and what failed.
struct BatchMoveResult {
    var moved: [URL] = []
    var skipped: [URL] = []                 // already in the destination, or would move a folder into itself
    var failed: [(url: URL, error: Error)] = []
}

/// Payload handed back from the detached move task; only URLs and errors cross the boundary.
private struct BatchMoveOutcome: @unchecked Sendable {
    var moved: [URL] = []
    var failed: [(url: URL, error: Error)] = []
}
