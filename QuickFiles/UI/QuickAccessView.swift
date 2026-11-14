import SwiftUI
import AppKit
import QuickLookThumbnailing

struct QuickAccessView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: PanelController
    @ObservedObject var model: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            recentGrid
            Divider().opacity(0.55)
            bookmarkStrip
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 760, height: 380)
        .background(.regularMaterial)
        .tint(QuickFilesTheme.accent)
        .background(
            KeyEventView { event in
                handleKeyEvent(event)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandGlyph()

            TextField("파일 이름이나 폴더 경로 검색", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            if controller.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                controller.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.11), in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("닫기")
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.035))
        .background(WindowDragRegion())
    }

    private var recentGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.snapshot.recentItems) { item in
                        FileTile(
                            item: item,
                            isSelected: model.selection.isSelected(item.id),
                            isFocused: model.selection.focusedID == item.id
                        )
                            .id(item.id)
                            .overlay(tileInteraction(for: item))
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                openOrReveal(item, modifierFlags: [])
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: model.selection.focusedID) { focusedID in
                guard let focusedID,
                      model.snapshot.recentItems.contains(where: { $0.id == focusedID }) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(focusedID, anchor: .center)
                }
            }
            .overlay {
                if model.snapshot.recentItems.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: model.snapshot.isSearching ? "magnifyingglass" : "clock")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(QuickFilesTheme.accent)
                        Text(model.snapshot.isSearching ? "검색 결과가 없습니다" : "표시할 변경 파일이 없습니다")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("검색 폴더와 제외 폴더는 설정에서 관리할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var bookmarkStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("북마크", systemImage: "bookmark.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuickFilesTheme.accent)
                Text("\(model.snapshot.bookmarkItems.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(model.snapshot.bookmarkItems) { item in
                        BookmarkTile(
                            item: item,
                            isSelected: model.selection.isSelected(item.id),
                            isFocused: model.selection.focusedID == item.id
                        )
                            .id(item.id)
                            .overlay(tileInteraction(for: item))
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                openOrReveal(item, modifierFlags: [])
                            }
                    }

                    Button {
                        addBookmark()
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(QuickFilesTheme.accent)
                                .frame(width: 42, height: 42)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("추가")
                                .font(.caption)
                        }
                        .frame(width: 72, height: 82)
                    }
                    .buttonStyle(.plain)
                    .help("북마크 추가")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .frame(height: 112)
        .background(Color.secondary.opacity(0.025))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                if let item = model.primaryItem {
                    move(item)
                }
            } label: {
                Label("이동", systemImage: "folder")
            }
            .disabled(model.primaryItem == nil)

            if model.selection.count > 1 {
                Text("\(model.selection.count)개 선택됨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("↵ 열기   ⌘↵ Finder")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침")
            .accessibilityLabel("새로고침")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.025))
        .background(WindowDragRegion())
    }

    // MARK: - Tile interaction

    private func tileInteraction(for item: FileItem) -> TileInteractionView {
        TileInteractionView(
            itemID: item.id,
            isSelected: { model.selection.isSelected($0) },
            onPress: { id, flags in
                pressItem(id, modifierFlags: flags)
            },
            onActivate: { id, flags in
                activateItem(id, modifierFlags: flags)
            },
            onContextSelection: { id in
                contextSelect(id)
            },
            makeMenu: { id in
                tileMenu(for: id)
            },
            dragURLs: { id in
                draggableURLs(for: id)
            },
            onDragStateChange: { isDragging in
                controller.setDraggingFiles(isDragging)
            }
        )
    }

    private func pressItem(_ id: FileItem.ID, modifierFlags: NSEvent.ModifierFlags) {
        let order = model.snapshot.orderedIDs

        if modifierFlags.contains(.shift) {
            model.selection.selectRange(to: id, in: order, additive: modifierFlags.contains(.command))
        } else if modifierFlags.contains(.command) {
            model.selection.toggle(id, in: order)
        } else {
            model.selection.selectOnly(id, in: order)
        }
    }

    private func activateItem(_ id: FileItem.ID, modifierFlags: NSEvent.ModifierFlags) {
        guard let item = model.snapshot.itemsByID[id] else { return }
        model.selection.selectOnly(id, in: model.snapshot.orderedIDs)
        openOrReveal(item, modifierFlags: modifierFlags)
    }

    private func contextSelect(_ id: FileItem.ID) {
        guard !model.selection.isSelected(id) else { return }
        model.selection.selectOnly(id, in: model.snapshot.orderedIDs)
    }

    private func draggableURLs(for id: FileItem.ID) -> [URL] {
        if model.selection.isSelected(id) {
            var seenPaths = Set<String>()
            return model.selectedItems.compactMap { item in
                seenPaths.insert(item.url.standardizedFileURL.path).inserted ? item.url : nil
            }
        }
        return model.snapshot.itemsByID[id].map { [$0.url] } ?? []
    }

    private func tileMenu(for id: FileItem.ID) -> NSMenu? {
        guard let item = model.snapshot.itemsByID[id] else { return nil }

        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Finder에서 위치 보기") { [controller] in
            controller.reveal(item)
        })
        menu.addItem(ClosureMenuItem(title: "열기") { [controller] in
            controller.open(item)
        })
        menu.addItem(ClosureMenuItem(title: "복사") { [controller] in
            controller.copy(item)
        })
        return menu
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, controller.isQuickPanelActive else { return false }

        // Let the input method finish composing (e.g. Hangul) before treating
        // Return/arrow keys as panel navigation.
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }

        let order = model.snapshot.orderedIDs
        let extending = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123:
            model.selection.moveFocus(by: -1, in: order, extending: extending)
            return true
        case 124:
            model.selection.moveFocus(by: 1, in: order, extending: extending)
            return true
        case 125:
            model.selection.moveFocus(by: 5, in: order, extending: extending)
            return true
        case 126:
            model.selection.moveFocus(by: -5, in: order, extending: extending)
            return true
        case 36, 76:
            if let item = model.primaryItem {
                openOrReveal(item, modifierFlags: event.modifierFlags)
                return true
            }
            return false
        case 53:
            if model.selection.count > 1 {
                model.selection.collapseToFocus(in: order)
            } else {
                controller.hide()
            }
            return true
        default:
            return false
        }
    }

    private func openOrReveal(_ item: FileItem, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            controller.reveal(item)
        } else {
            controller.open(item)
        }
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
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            FilePreviewIcon(url: item.url, version: item.activityAt)
                .frame(width: 58, height: 58)

            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)

            if let date = item.activityAt {
                Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 108, height: 122, alignment: .top)
        .padding(.vertical, 7)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
        .shadow(color: isSelected ? QuickFilesTheme.accent.opacity(0.14) : .clear, radius: 7, y: 2)
    }

    private var borderColor: Color {
        if isSelected {
            return QuickFilesTheme.accent.opacity(0.65)
        }
        if isFocused {
            return QuickFilesTheme.accent.opacity(0.45)
        }
        return .clear
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(QuickFilesTheme.accent.opacity(0.16))
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.38))
        }
    }
}

private struct BookmarkTile: View {
    let item: FileItem
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            FilePreviewIcon(url: item.url, version: item.activityAt)
                .frame(width: 46, height: 46)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(QuickFilesTheme.accent)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }

            Text(item.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: 76, height: 82, alignment: .top)
        .padding(.vertical, 4)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return QuickFilesTheme.accent.opacity(0.65)
        }
        if isFocused {
            return QuickFilesTheme.accent.opacity(0.45)
        }
        return .clear
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(QuickFilesTheme.accent.opacity(0.16))
        } else {
            Color.clear
        }
    }
}

private enum QuickFilesTheme {
    static let accent = Color.accentColor
}

private struct BrandGlyph: View {
    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 26, height: 26)
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)
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
