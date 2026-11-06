import SwiftUI
import AppKit
import QuickLookThumbnailing

struct QuickAccessView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: PanelController
    @State private var query = ""
    @State private var effectiveQuery = ""
    @State private var selectedItemID: FileItem.ID?

    private var recentItems: [FileItem] {
        sourceItems.filter { $0.kind == .recent }
    }

    private var bookmarkItems: [FileItem] {
        store.bookmarks
            .map { bookmark in
                FileItem(url: bookmark.url, modifiedAt: nil, createdAt: nil, kind: .bookmark)
            }
            .filter(matchesSearch)
    }

    private var sourceItems: [FileItem] {
        guard !searchTerms.isEmpty else { return controller.items }
        return controller.searchableItems.filter(matchesSearch)
    }

    private var displayedItems: [FileItem] {
        recentItems + bookmarkItems
    }

    private var searchTerms: [String] {
        effectiveQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map {
                String($0).folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            recentGrid
            Divider()
            bookmarkStrip
            Divider()
            footer
        }
        .frame(width: 760, height: 380)
        .background(.regularMaterial)
        .background(
            KeyEventView { event in
                handleKeyEvent(event)
            }
        )
        .onAppear {
            selectFirstItemIfNeeded()
        }
        .task(id: query) {
            if query.isEmpty {
                effectiveQuery = ""
                return
            }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            effectiveQuery = query
        }
        .onChange(of: displayedItems) { newItems in
            if let selectedItemID, newItems.contains(where: { $0.id == selectedItemID }) {
                return
            }
            selectedItemID = newItems.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.accentColor)

            TextField("파일 이름이나 폴더 경로 검색", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))

            if controller.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                controller.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("닫기")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WindowDragRegion())
    }

    private var recentGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(recentItems) { item in
                        FileTile(item: item, isSelected: item.id == selectedItemID)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItemID = item.id
                            }
                            .onTapGesture(count: 2) {
                                openOrReveal(item, modifierFlags: NSApp.currentEvent?.modifierFlags ?? [])
                            }
                            .onDrag {
                                selectedItemID = item.id
                                return fileProvider(for: item)
                            }
                            .contextMenu {
                                fileContextMenu(for: item)
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedItemID) { itemID in
                guard let itemID, recentItems.contains(where: { $0.id == itemID }) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            }
            .overlay {
                if recentItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(searchTerms.isEmpty ? "표시할 변경 파일이 없습니다" : "검색 결과가 없습니다")
                            .font(.headline)
                        Text("검색 폴더와 제외 폴더는 설정에서 관리할 수 있습니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var bookmarkStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("북마크")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(bookmarkItems) { item in
                        BookmarkTile(item: item, isSelected: item.id == selectedItemID)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItemID = item.id
                            }
                            .onTapGesture(count: 2) {
                                openOrReveal(item, modifierFlags: NSApp.currentEvent?.modifierFlags ?? [])
                            }
                            .onDrag {
                                selectedItemID = item.id
                                return fileProvider(for: item)
                            }
                            .contextMenu {
                                fileContextMenu(for: item)
                            }
                    }

                    Button {
                        addBookmark()
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("추가")
                                .font(.caption)
                        }
                        .frame(width: 72, height: 82)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .frame(height: 112)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                if let item = selectedItem {
                    move(item)
                }
            } label: {
                Label("이동", systemImage: "folder")
            }
            .disabled(selectedItem == nil)

            Spacer()

            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WindowDragRegion())
    }

    private var selectedItem: FileItem? {
        guard let selectedItemID else { return nil }
        return displayedItems.first { $0.id == selectedItemID }
    }

    private func matchesSearch(_ item: FileItem) -> Bool {
        let terms = searchTerms
        guard !terms.isEmpty else { return true }
        return terms.allSatisfy(item.searchText.contains)
    }

    private func selectFirstItemIfNeeded() {
        if selectedItemID == nil || !displayedItems.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = displayedItems.first?.id
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, controller.isQuickPanelActive else { return false }

        // Let the input method finish composing (e.g. Hangul) before treating
        // Return/arrow keys as panel navigation.
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }

        switch event.keyCode {
        case 123:
            moveSelection(by: -1)
            return true
        case 124:
            moveSelection(by: 1)
            return true
        case 125:
            moveSelection(by: 5)
            return true
        case 126:
            moveSelection(by: -5)
            return true
        case 36, 76:
            if let selectedItem {
                openOrReveal(selectedItem, modifierFlags: event.modifierFlags)
                return true
            }
            return false
        case 53:
            controller.hide()
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func fileContextMenu(for item: FileItem) -> some View {
        Button("파인더에 위치 표시") {
            controller.reveal(item)
        }
        Button("열기") {
            controller.open(item)
        }
        Button("복사") {
            controller.copy(item)
        }
    }

    private func openOrReveal(_ item: FileItem, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            controller.reveal(item)
        } else {
            controller.open(item)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !displayedItems.isEmpty else { return }
        guard let selectedItemID,
              let currentIndex = displayedItems.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = displayedItems.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), displayedItems.count - 1)
        self.selectedItemID = displayedItems[nextIndex].id
    }

    private func fileProvider(for item: FileItem) -> NSItemProvider {
        let provider = NSItemProvider(object: item.url as NSURL)
        provider.suggestedName = item.displayName
        return provider
    }

    private func move(_ item: FileItem) {
        let panel = NSOpenPanel()
        panel.message = "파일을 이동할 폴더를 선택하세요."
        panel.prompt = "이동"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url {
            controller.move(item, to: folder)
        }
    }

    private func addBookmark() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addBookmark($0) }
        }
    }
}

private struct FileTile: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            FilePreviewIcon(url: item.url, version: item.activityAt)
                .frame(width: 58, height: 58)

            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)

            if let date = item.activityAt {
                Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 110, height: 124, alignment: .top)
        .padding(.vertical, 8)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.88))
        } else {
            Color.clear
        }
    }
}

private struct BookmarkTile: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            FilePreviewIcon(url: item.url, version: item.activityAt)
                .frame(width: 46, height: 46)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }

            Text(item.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: 76, height: 82, alignment: .top)
        .padding(.vertical, 4)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.88))
        } else {
            Color.clear
        }
    }
}

private struct FilePreviewIcon: View {
    let url: URL
    let version: Date?
    @State private var image: NSImage?

    private var cacheKey: String {
        "\(url.standardizedFileURL.path)|\(version?.timeIntervalSinceReferenceDate ?? 0)"
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: cacheKey) {
            image = await ThumbnailProvider.shared.image(
                for: url,
                version: version
            )
        }
    }
}

@MainActor
private final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(for url: URL, version: Date?) async -> NSImage {
        let key = "\(url.standardizedFileURL.path)|\(version?.timeIntervalSinceReferenceDate ?? 0)"
        let cacheKey = key as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        let image = await Self.generateThumbnail(for: url)
            ?? NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: cacheKey, cost: 64 * 64 * 4 * 4)
        return image
    }

    private static func generateThumbnail(for url: URL) async -> NSImage? {
        let size = CGSize(width: 64, height: 64)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: thumbnail?.nsImage)
                }
            }
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

private struct KeyEventView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
