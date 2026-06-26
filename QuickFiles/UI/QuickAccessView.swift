import SwiftUI
import AppKit
import QuickLookThumbnailing

struct QuickAccessView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: PanelController
    @State private var query = ""
    @State private var selectedItemID: FileItem.ID?

    private var filteredItems: [FileItem] {
        let terms = searchTerms
        guard !terms.isEmpty else {
            return controller.items
        }

        return controller.searchableItems.filter { item in
            terms.allSatisfy { term in
                item.displayName.localizedCaseInsensitiveContains(term) ||
                item.parentPath.localizedCaseInsensitiveContains(term)
            }
        }
    }

    private var searchTerms: [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(.regularMaterial)
        .background(
            KeyEventView { event in
                handleKeyEvent(event)
            }
        )
        .onAppear {
            selectFirstItemIfNeeded()
        }
        .onChange(of: filteredItems) { newItems in
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
        }
        .padding(18)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredItems) { item in
                        let isSelected = item.id == selectedItemID
                        FileRow(item: item, isSelected: isSelected)
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
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedItemID) { itemID in
                guard let itemID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            }
            .overlay {
                if filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("표시할 파일이 없습니다")
                            .font(.headline)
                        Text("설정에서 검색 폴더를 추가하거나 북마크를 등록하세요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                addBookmark()
            } label: {
                Label("북마크 추가", systemImage: "bookmark")
            }

            Button {
                addScanFolder()
            } label: {
                Label("검색 폴더", systemImage: "folder.badge.plus")
            }

            Button {
                addExcludedFolder()
            } label: {
                Label("제외 폴더", systemImage: "folder.badge.minus")
            }

            Spacer()

            Button {
                if let item = selectedItem {
                    move(item)
                }
            } label: {
                Label("이동", systemImage: "folder")
            }
            .disabled(selectedItem == nil)

            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침")
        }
        .buttonStyle(.bordered)
        .padding(12)
    }

    private var selectedItem: FileItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
    }

    private func selectFirstItemIfNeeded() {
        if selectedItemID == nil || !filteredItems.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = filteredItems.first?.id
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, controller.isQuickPanelActive else { return false }

        switch event.keyCode {
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
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

    private func openOrReveal(_ item: FileItem, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            controller.reveal(item)
        } else {
            controller.open(item)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        guard let selectedItemID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = filteredItems.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        self.selectedItemID = filteredItems[nextIndex].id
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
            controller.refresh()
        }
    }

    private func addScanFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addScanFolder($0) }
            controller.refresh()
        }
    }

    private func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addExcludedFolder($0) }
            controller.refresh()
        }
    }
}

private struct FileRow: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            FilePreviewIcon(url: item.url)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if item.kind == .bookmark {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(item.parentPath)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let date = item.activityAt {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var iconColor: Color {
        isSelected ? .white.opacity(0.9) : .secondary
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(0.88))
        } else {
            Color.clear
        }
    }
}

private struct FilePreviewIcon: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: url.path) {
            image = await thumbnail(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private func thumbnail(for url: URL) async -> NSImage? {
        let size = CGSize(width: 64, height: 64)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
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
