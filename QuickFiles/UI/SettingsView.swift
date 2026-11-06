import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var excludedExtensionInput = ""

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            hotKeySettings
                .tabItem {
                    Label("단축키", systemImage: "keyboard")
                }

            folderList(
                title: "검색 폴더",
                items: store.scanFolders,
                emptyText: "최근 파일을 찾을 폴더를 추가하세요.",
                addAction: addScanFolder,
                removeAction: store.removeScanFolder
            )
            .tabItem {
                Label("검색", systemImage: "folder")
            }

            exclusionSettings
            .tabItem {
                Label("제외", systemImage: "minus.circle")
            }

            bookmarkList
                .tabItem {
                    Label("북마크", systemImage: "bookmark")
                }
        }
        .frame(width: 640, height: 440)
        .padding()
    }

    @State private var hotKeyErrorMessage: String?

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("일반")
                .font(.title2.weight(.semibold))

            Toggle(
                "로그인 시 QuickFiles 자동 실행",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            if launchAtLogin.requiresApproval {
                Label("시스템 설정에서 QuickFiles 실행을 허용해야 합니다.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)

                Button("로그인 항목 설정 열기") {
                    launchAtLogin.openLoginItemsSettings()
                }
            }

            if let errorMessage = launchAtLogin.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var hotKeySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("단축키")
                .font(.title2.weight(.semibold))

            HotKeyRecorderView(hotKey: store.hotKey) { newHotKey in
                updateHotKey(newHotKey)
            }
            .frame(width: 320, height: 42)

            if let hotKeyErrorMessage {
                Label(hotKeyErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Button("기본값으로 되돌리기") {
                updateHotKey(.defaultValue)
            }

            Spacer()
        }
        .padding(20)
    }

    private func updateHotKey(_ newHotKey: HotKeyDefinition) {
        guard newHotKey.hasModifier else {
            hotKeyErrorMessage = "Command, Option, Control, Shift 중 하나 이상을 함께 눌러주세요."
            return
        }

        if newHotKey == store.hotKey {
            hotKeyErrorMessage = nil
            return
        }

        if newHotKey != .defaultValue, isLikelyReservedShortcut(newHotKey) {
            hotKeyErrorMessage = "macOS나 대부분의 앱에서 이미 쓰는 단축키입니다."
            return
        }

        if HotKeyController.canRegister(newHotKey) {
            store.hotKey = newHotKey
            hotKeyErrorMessage = nil
        } else {
            hotKeyErrorMessage = "이미 macOS나 다른 앱에서 사용 중인 단축키입니다."
        }
    }

    private func isLikelyReservedShortcut(_ hotKey: HotKeyDefinition) -> Bool {
        let command = UInt32(cmdKey)
        let commandOption = UInt32(cmdKey | optionKey)
        let reserved: Set<HotKeyDefinition> = [
            HotKeyDefinition(keyCode: UInt32(kVK_Space), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_Space), modifierFlags: commandOption),
            HotKeyDefinition(keyCode: UInt32(kVK_Tab), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_ANSI_Q), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_ANSI_W), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_ANSI_H), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_ANSI_M), modifierFlags: command),
            HotKeyDefinition(keyCode: UInt32(kVK_ANSI_Comma), modifierFlags: command)
        ]
        return reserved.contains(hotKey)
    }

    private var bookmarkList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("북마크")
                .font(.title2.weight(.semibold))

            List {
                ForEach(store.bookmarks) { bookmark in
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.yellow)
                        Text(bookmark.url.path)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            store.removeBookmark(bookmark)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Button {
                    addBookmark()
                } label: {
                    Label("추가", systemImage: "plus")
                }
                Spacer()
            }
        }
    }

    private var exclusionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("제외 규칙")
                .font(.title2.weight(.semibold))

            List {
                Section("위치") {
                    if store.excludedFolders.isEmpty {
                        Text("검색에서 제외할 폴더나 라이브러리를 추가하세요.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.excludedFolders) { rule in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: rule.url.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(rule.url.path)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                store.removeExcludedFolder(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("확장자") {
                    if store.excludedExtensions.isEmpty {
                        Text("제외할 파일 확장자를 추가하세요.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.excludedExtensions, id: \.self) { pathExtension in
                        HStack {
                            Image(systemName: "doc")
                            Text(".\(pathExtension)")
                                .monospaced()
                            Spacer()
                            Button {
                                store.removeExcludedExtension(pathExtension)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            HStack {
                Button {
                    addExcludedLocation()
                } label: {
                    Label("위치 추가", systemImage: "folder.badge.minus")
                }

                Spacer()

                TextField("예: jpg, mp3", text: $excludedExtensionInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(addExcludedExtension)

                Button {
                    addExcludedExtension()
                } label: {
                    Image(systemName: "plus")
                }
                .help("확장자 추가")
                .disabled(excludedExtensionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func folderList(
        title: String,
        items: [FolderRule],
        emptyText: String,
        addAction: @escaping () -> Void,
        removeAction: @escaping (FolderRule) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))

            List {
                if items.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }

                ForEach(items) { item in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                        Text(item.url.path)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            removeAction(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Button {
                    addAction()
                } label: {
                    Label("추가", systemImage: "plus")
                }
                Spacer()
            }
        }
    }

    private func addScanFolder() {
        chooseFolders().forEach { store.addScanFolder($0) }
    }

    private func addExcludedLocation() {
        let panel = NSOpenPanel()
        panel.message = "제외할 폴더나 사진·음악 라이브러리를 선택하세요."
        panel.prompt = "제외"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK {
            panel.urls.forEach { store.addExcludedFolder($0) }
        }
    }

    private func addExcludedExtension() {
        store.addExcludedExtension(excludedExtensionInput)
        excludedExtensionInput = ""
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

    private func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}


private struct HotKeyRecorderView: NSViewRepresentable {
    var hotKey: HotKeyDefinition
    var onChange: (HotKeyDefinition) -> Void

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.onChange = onChange
        field.hotKey = hotKey
        return field
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.onChange = onChange
        nsView.hotKey = hotKey
    }
}

private final class RecorderField: NSView {
    var hotKey: HotKeyDefinition = .defaultValue {
        didSet { needsDisplay = true }
    }
    var onChange: ((HotKeyDefinition) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            needsDisplay = true
            return
        }

        let definition = HotKeyDefinition(
            keyCode: UInt32(event.keyCode),
            modifierFlags: carbonModifierFlags(from: event.modifierFlags)
        )
        isRecording = false
        needsDisplay = true
        onChange?(definition)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "원하는 단축키를 누르세요" : hotKey.displayText
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(x: 8, y: (self.bounds.height - attributedText.size().height) / 2, width: self.bounds.width - 16, height: attributedText.size().height)
        attributedText.draw(in: textRect)
    }

    private func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
