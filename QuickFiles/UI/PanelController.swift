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
    private var modalDepth = 0
    private var presentationGeneration = 0

    private var isPresentingModal: Bool { modalDepth > 0 }

    private(set) var viewModel: PanelViewModel?

    @Published var items: [FileItem] = []
    @Published var searchableItems: [FileItem] = []
    @Published var isLoading = false
    @Published private(set) var isMoving = false

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
        presentationGeneration += 1

        if panel == nil {
            let model = PanelViewModel(store: store, controller: self)
            viewModel = model
            let root = QuickAccessView(store: store, controller: self, model: model)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = [.minSize]
            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: QuickAccessLayout.panelWidth,
                    height: store.panelHeight
                ),
                styleMask: [.titled, .fullSizeContentView, .resizable],
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
            // Set after attaching the hosting controller: its .minSize sizing option can
            // otherwise overwrite the limits below.
            panel.contentMinSize = NSSize(
                width: QuickAccessLayout.panelWidth,
                height: QuickAccessLayout.minPanelHeight
            )
            panel.contentMaxSize = NSSize(
                width: QuickAccessLayout.panelWidth,
                height: QuickAccessLayout.maxPanelHeight
            )
            self.panel = panel
        }

        eventMonitor.flush()
        if !hasLoadedData {
            refresh()
        }

        staysVisibleUntilClosed = false
        positionPanel()
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
        guard !dragging else { return }

        // The drag interaction ends while AppKit still considers the drag active; re-apply the
        // hide policy on the next run-loop turn, by which time the key/main window state settled.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDraggingFiles else { return }
            guard self.panel?.isVisible == true,
                  !self.staysVisibleUntilClosed,
                  !self.isPresentingModal else { return }
            guard !NSApp.isActive || self.panel?.isKeyWindow != true else { return }
            self.hide()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !staysVisibleUntilClosed, !isDraggingFiles, !isPresentingModal else { return }
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        guard panel?.isVisible == true, !isPositioningPanel else { return }
        // Resizing from the left edge moves the origin; that must not pin the panel open.
        guard panel?.inLiveResize != true else { return }
        keepVisibleUntilClosed()
    }

    /// Persists the user's chosen height once, at the end of a live resize (not on every tick).
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        store.panelHeight = SettingsStore.clampPanelHeight(Double(panel.contentLayoutRect.height))
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
        let wasVisible = panel?.isVisible == true
        modalDepth += 1
        defer {
            modalDepth -= 1
            // Nested modals must not steal focus back while an outer one is still running.
            if modalDepth == 0, wasVisible {
                panel?.makeKeyAndOrderFront(nil)
            }
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
        guard !isMoving else {
            NSSound.beep()
            return
        }
        isMoving = true
        defer { isMoving = false }

        let generation = presentationGeneration
        let result = await move(items, to: folder)

        guard !result.failed.isEmpty else {
            // Only close the panel instance the user actually started this move from.
            if generation == presentationGeneration {
                hide()
            }
            return
        }

        // An open-panel / alert modal would swallow this one; wait for the main run loop to drain it.
        while modalDepth > 0 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        _ = runModal { () -> NSApplication.ModalResponse in
            let alert = NSAlert()
            alert.messageText = "\(result.moved.count)개 이동, \(result.failed.count)개 실패"
            alert.informativeText = result.failed.first?.error.localizedDescription ?? ""
            alert.addButton(withTitle: "확인")
            return alert.runModal()
        }
    }

    /// Plans and moves on a background task so large / cross-volume moves don't block the UI.
    func move(_ items: [FileItem], to folder: URL) async -> BatchMoveResult {
        let urls = items.map(\.url)
        let outcome = await Task.detached(priority: .userInitiated) { () -> BatchMoveOutcome in
            var outcome = BatchMoveOutcome()
            let plan = MovePlanner.plan(urls, to: folder)
            outcome.skipped = plan.skipped
            outcome.carried = plan.carried
            for url in plan.toMove {
                do {
                    outcome.moved.append(try PanelController.moveFile(url, into: folder))
                } catch {
                    outcome.failed.append((url, error))
                }
            }
            return outcome
        }.value

        refresh(showLoading: false)
        return BatchMoveResult(
            moved: outcome.moved,
            skipped: outcome.skipped,
            carried: outcome.carried,
            failed: outcome.failed
        )
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

    /// Places the panel on the screen under the mouse, centred horizontally near the top of the visible frame.
    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        // A shrink can move the frame too; flag it before the resize so windowDidMove stays quiet.
        isPositioningPanel = true

        // Restore the user's height first: a previous show on a short screen may have fitted the
        // panel to that screen, and that temporary size must not stick on a taller one. Never
        // persisted here — only a live resize saves the height.
        if abs(panel.contentLayoutRect.height - CGFloat(store.panelHeight)) > 1 {
            panel.setContentSize(NSSize(width: QuickAccessLayout.panelWidth, height: CGFloat(store.panelHeight)))
        }

        // The width is fixed, so only a frame taller than the screen needs a temporary fit.
        // This smaller height is deliberately not persisted: only a live resize saves it.
        let titlebar = panel.frame.height - panel.contentLayoutRect.height
        if panel.frame.height > visible.height - 100 {
            let newHeight = max(QuickAccessLayout.minPanelHeight, visible.height - 100 - titlebar)
            panel.setContentSize(NSSize(width: QuickAccessLayout.panelWidth, height: newHeight))
        }

        let size = panel.frame.size
        let origin = NSPoint(
            x: min(max(visible.midX - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(visible.maxY - size.height - 90, visible.minY), visible.maxY - size.height)
        )
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

/// Outcome of a batch move: what moved, what the plan skipped or carried, and what failed.
struct BatchMoveResult {
    var moved: [URL] = []
    var skipped: [URL] = []                 // already in the destination, or would move a folder into itself
    var carried: [URL] = []                 // inside a selected folder that moved, so not moved separately
    var failed: [(url: URL, error: Error)] = []
}

/// Payload handed back from the detached move task; only URLs and errors cross the boundary.
private struct BatchMoveOutcome: @unchecked Sendable {
    var moved: [URL] = []
    var skipped: [URL] = []
    var carried: [URL] = []
    var failed: [(url: URL, error: Error)] = []
}
