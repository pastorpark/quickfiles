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
            let storedScanFolders = decoded.scanFolders ?? Self.defaultScanFolders()
            let storedExcludedFolders = decoded.excludedFolders ?? Self.defaultExcludedFolders()
            let scanFolders = storedScanFolders.map(Self.resolve)
            let excludedFolders = storedExcludedFolders.map(Self.resolve)
            let bookmarks = decoded.bookmarks.map(Self.resolve)
            self.scanFolders = scanFolders
            self.excludedFolders = excludedFolders
            self.excludedExtensions = decoded.excludedExtensions
            self.bookmarks = bookmarks
            self.maxRecentFiles = decoded.maxRecentFiles
            let decodedHotKey = decoded.hotKey
            self.hotKey = decodedHotKey == .legacyOptionSpace ? .defaultValue : decodedHotKey

            let refreshedBookmarkData = scanFolders.map(\.bookmarkData) != storedScanFolders.map(\.bookmarkData)
                || excludedFolders.map(\.bookmarkData) != storedExcludedFolders.map(\.bookmarkData)
                || bookmarks.map(\.bookmarkData) != decoded.bookmarks.map(\.bookmarkData)
            if decodedHotKey == .legacyOptionSpace || refreshedBookmarkData || decoded.wasMigrated {
                save()
            }
        } else {
            Self.backUpUnreadableSettings(at: fileURL)
            self.scanFolders = Self.defaultScanFolders()
            self.excludedFolders = Self.defaultExcludedFolders()
            self.excludedExtensions = []
            self.bookmarks = []
            self.maxRecentFiles = PersistedSettings.defaultMaxRecentFiles
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
        guard let (url, data) = resolveBookmark(rule.bookmarkData) else { return rule }
        return FolderRule(id: rule.id, url: url, bookmarkData: data)
    }

    private static func resolve(_ bookmark: StoredBookmark) -> StoredBookmark {
        guard let (url, data) = resolveBookmark(bookmark.bookmarkData) else { return bookmark }
        return StoredBookmark(id: bookmark.id, url: url, bookmarkData: data)
    }

    /// Resolves stored bookmark data, regenerating it when the system reports it as stale
    /// so the refreshed data can be persisted. QuickFiles is not sandboxed, so the bookmarks
    /// are used to follow moved/renamed items, not to obtain security-scoped access.
    private static func resolveBookmark(_ bookmarkData: Data?) -> (URL, Data?)? {
        guard let bookmarkData else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        guard stale else { return (url, bookmarkData) }
        let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return (url, refreshed ?? bookmarkData)
    }

    private static func backUpUnreadableSettings(at fileURL: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("settings.backup-\(formatter.string(from: Date())).json")
        do {
            try manager.copyItem(at: fileURL, to: backupURL)
            NSLog("QuickFiles: unreadable settings.json backed up to \(backupURL.path)")
        } catch {
            NSLog("QuickFiles: failed to back up unreadable settings.json: \(error)")
        }
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
    static let defaultMaxRecentFiles = 40

    /// nil only when decoding a file that lacks the key; the store then falls back to its defaults.
    var scanFolders: [FolderRule]?
    var excludedFolders: [FolderRule]?
    var excludedExtensions: [String]
    var bookmarks: [StoredBookmark]
    var maxRecentFiles: Int
    var hotKey: HotKeyDefinition
    /// True when a field was missing and filled with a default, so the file should be rewritten.
    var wasMigrated = false

    private enum CodingKeys: String, CodingKey {
        case scanFolders, excludedFolders, excludedExtensions, bookmarks, maxRecentFiles, hotKey
    }

    init(
        scanFolders: [FolderRule],
        excludedFolders: [FolderRule],
        excludedExtensions: [String],
        bookmarks: [StoredBookmark],
        maxRecentFiles: Int,
        hotKey: HotKeyDefinition
    ) {
        self.scanFolders = scanFolders
        self.excludedFolders = excludedFolders
        self.excludedExtensions = excludedExtensions
        self.bookmarks = bookmarks
        self.maxRecentFiles = maxRecentFiles
        self.hotKey = hotKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scanFolders = try container.decodeIfPresent([FolderRule].self, forKey: .scanFolders)
        let excludedFolders = try container.decodeIfPresent([FolderRule].self, forKey: .excludedFolders)
        let excludedExtensions = try container.decodeIfPresent([String].self, forKey: .excludedExtensions)
        let bookmarks = try container.decodeIfPresent([StoredBookmark].self, forKey: .bookmarks)
        let maxRecentFiles = try container.decodeIfPresent(Int.self, forKey: .maxRecentFiles)
        let hotKey = try container.decodeIfPresent(HotKeyDefinition.self, forKey: .hotKey)

        self.scanFolders = scanFolders
        self.excludedFolders = excludedFolders
        self.excludedExtensions = excludedExtensions ?? []
        self.bookmarks = bookmarks ?? []
        self.maxRecentFiles = maxRecentFiles ?? Self.defaultMaxRecentFiles
        self.hotKey = hotKey ?? .defaultValue
        self.wasMigrated = [
            scanFolders == nil, excludedFolders == nil, excludedExtensions == nil,
            bookmarks == nil, maxRecentFiles == nil, hotKey == nil
        ].contains(true)
    }
}
