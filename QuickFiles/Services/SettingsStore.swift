import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var scanFolders: [FolderRule] {
        didSet { save() }
    }

    @Published var excludedFolders: [FolderRule] {
        didSet { save() }
    }

    @Published var excludedExtensions: [String] {
        didSet { save() }
    }

    @Published var bookmarks: [StoredBookmark] {
        didSet { save() }
    }

    @Published var maxRecentFiles: Int {
        didSet { save() }
    }

    @Published var hotKey: HotKeyDefinition {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuickFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            self.scanFolders = decoded.scanFolders.map(Self.resolve)
            self.excludedFolders = decoded.excludedFolders.map(Self.resolve)
            self.excludedExtensions = decoded.excludedExtensions ?? []
            self.bookmarks = decoded.bookmarks.map(Self.resolve)
            self.maxRecentFiles = decoded.maxRecentFiles
            let decodedHotKey = decoded.hotKey ?? .defaultValue
            self.hotKey = decodedHotKey == .legacyOptionSpace ? .defaultValue : decodedHotKey
            if decodedHotKey == .legacyOptionSpace {
                save()
            }
        } else {
            self.scanFolders = Self.defaultScanFolders()
            self.excludedFolders = Self.defaultExcludedFolders()
            self.excludedExtensions = []
            self.bookmarks = []
            self.maxRecentFiles = 40
            self.hotKey = .defaultValue
            save()
        }
    }

    func addScanFolder(_ url: URL) {
        guard !scanFolders.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        scanFolders.append(FolderRule(url: url, bookmarkData: makeBookmarkData(for: url)))
    }

    func addExcludedFolder(_ url: URL) {
        guard !excludedFolders.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        excludedFolders.append(FolderRule(url: url, bookmarkData: makeBookmarkData(for: url)))
    }

    func addExcludedExtension(_ value: String) {
        let normalized = Self.normalizeExtension(value)
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !excludedExtensions.contains(normalized) else { return }
        excludedExtensions.append(normalized)
        excludedExtensions.sort()
    }

    func addBookmark(_ url: URL) {
        guard !bookmarks.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        bookmarks.append(StoredBookmark(url: url, bookmarkData: makeBookmarkData(for: url)))
    }

    func removeScanFolder(_ rule: FolderRule) {
        scanFolders.removeAll { $0.id == rule.id }
    }

    func removeExcludedFolder(_ rule: FolderRule) {
        excludedFolders.removeAll { $0.id == rule.id }
    }

    func removeExcludedExtension(_ value: String) {
        excludedExtensions.removeAll { $0 == value }
    }

    func removeBookmark(_ bookmark: StoredBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    private func save() {
        let payload = PersistedSettings(
            scanFolders: scanFolders,
            excludedFolders: excludedFolders,
            excludedExtensions: excludedExtensions,
            bookmarks: bookmarks,
            maxRecentFiles: maxRecentFiles,
            hotKey: hotKey
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func makeBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolve(_ rule: FolderRule) -> FolderRule {
        guard let bookmarkData = rule.bookmarkData else { return rule }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return rule }

        return FolderRule(id: rule.id, url: url, bookmarkData: stale ? nil : bookmarkData)
    }

    private static func resolve(_ bookmark: StoredBookmark) -> StoredBookmark {
        guard let bookmarkData = bookmark.bookmarkData else { return bookmark }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return bookmark }

        return StoredBookmark(id: bookmark.id, url: url, bookmarkData: stale ? nil : bookmarkData)
    }

    private static func defaultScanFolders() -> [FolderRule] {
        let manager = FileManager.default
        let folders = [
            manager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            manager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            manager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        return folders.map { FolderRule(url: $0) }
    }

    private static func defaultExcludedFolders() -> [FolderRule] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            "/Applications",
            "/Library",
            "/System",
            "/private",
            "/usr",
            "/bin",
            "/sbin",
            home.appendingPathComponent("Library").path,
            home.appendingPathComponent(".Trash").path
        ]

        return paths.map { FolderRule(url: URL(fileURLWithPath: $0, isDirectory: true)) }
    }

    private static func normalizeExtension(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}

private struct PersistedSettings: Codable {
    var scanFolders: [FolderRule]
    var excludedFolders: [FolderRule]
    var excludedExtensions: [String]?
    var bookmarks: [StoredBookmark]
    var maxRecentFiles: Int
    var hotKey: HotKeyDefinition?
}
