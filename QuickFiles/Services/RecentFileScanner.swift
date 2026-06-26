import Foundation

actor RecentFileScanner {
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isHiddenKey,
        .isPackageKey,
        .contentModificationDateKey,
        .creationDateKey,
        .addedToDirectoryDateKey,
        .attributeModificationDateKey,
        .localizedTypeDescriptionKey
    ]

    func scan(
        folders: [FolderRule],
        excludedFolders: [FolderRule],
        bookmarks: [StoredBookmark],
        limit: Int? = nil
    ) async -> [FileItem] {
        let excludedPaths = excludedFolders.map { normalizedDirectoryPath($0.url) }
        var itemsByPath: [String: FileItem] = [:]

        for folder in folders {
            scanFolder(folder.url, resourceKeys: resourceKeys, excludedPaths: excludedPaths, into: &itemsByPath)
        }

        for bookmark in bookmarks {
            let values = try? bookmark.url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .addedToDirectoryDateKey,
                .attributeModificationDateKey
            ])
            itemsByPath[bookmark.url.path] = FileItem(
                url: bookmark.url,
                modifiedAt: values?.contentModificationDate,
                createdAt: values?.creationDate,
                addedAt: values?.addedToDirectoryDate,
                metadataChangedAt: values?.attributeModificationDate,
                kind: .bookmark
            )
        }

        let sortedItems = itemsByPath.values
            .sorted { lhs, rhs in
                sortDate(for: lhs) > sortDate(for: rhs)
            }

        guard let limit else { return sortedItems }
        return sortedItems.prefix(max(1, limit)).map { $0 }
    }

    private func sortDate(for item: FileItem) -> Date {
        item.activityAt ?? .distantPast
    }
}

private func scanFolder(
    _ folder: URL,
    resourceKeys: Set<URLResourceKey>,
    excludedPaths: [String],
    into itemsByPath: inout [String: FileItem]
) {
    guard !isExcluded(folder, excludedPaths: excludedPaths) else { return }

    let options: FileManager.DirectoryEnumerationOptions = [
        .skipsHiddenFiles,
        .skipsPackageDescendants
    ]

    guard let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: Array(resourceKeys),
        options: options
    ) else { return }

    var visitedCount = 0
    while let url = enumerator.nextObject() as? URL {
        if Task.isCancelled { return }
        visitedCount += 1
        if visitedCount > 10_000 { return }

        if isExcluded(url, excludedPaths: excludedPaths) {
            enumerator.skipDescendants()
            continue
        }

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
        if values.isDirectory == true {
            continue
        }

        guard values.isRegularFile == true, values.isHidden != true else { continue }

        itemsByPath[url.path] = FileItem(
            url: url,
            modifiedAt: values.contentModificationDate,
            createdAt: values.creationDate,
            addedAt: values.addedToDirectoryDate,
            metadataChangedAt: values.attributeModificationDate,
            kind: .recent
        )
    }
}

private func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
    let path = normalizedDirectoryPath(url)
    return excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
}

private func normalizedDirectoryPath(_ url: URL) -> String {
    url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}
