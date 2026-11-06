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
        .attributeModificationDateKey
    ]
    private var itemsByPath: [String: FileItem] = [:]
    private var sortedCache: [FileItem] = []

    func scan(
        folders: [FolderRule],
        excludedFolders: [FolderRule],
        excludedExtensions: [String]
    ) -> [FileItem] {
        let excludedPaths = excludedFolders.map { normalizedDirectoryPath($0.url) }
        let excludedExtensionSet = Set(excludedExtensions.map { $0.lowercased() })
        var scannedItems: [String: FileItem] = [:]

        for folder in folders {
            if Task.isCancelled { return sortedCache }
            scanFolder(
                folder.url,
                resourceKeys: resourceKeys,
                excludedPaths: excludedPaths,
                excludedExtensions: excludedExtensionSet,
                into: &scannedItems
            )
        }

        guard !Task.isCancelled else { return sortedCache }
        itemsByPath = scannedItems
        rebuildSortedCache()
        return sortedCache
    }

    func applyChanges(
        _ changes: [FileSystemChange],
        folders: [FolderRule],
        excludedFolders: [FolderRule],
        excludedExtensions: [String]
    ) -> [FileItem] {
        let scanPaths = folders.map { normalizedDirectoryPath($0.url) }
        let excludedPaths = excludedFolders.map { normalizedDirectoryPath($0.url) }
        let excludedExtensionSet = Set(excludedExtensions.map { $0.lowercased() })
        let fileManager = FileManager.default
        var didMutate = false

        for change in changes {
            if Task.isCancelled { break }

            let url = URL(fileURLWithPath: change.path)
            let path = url.standardizedFileURL.path

            if change.wasRemoved || change.wasRenamed {
                didMutate = removeItemAndDescendants(at: path) || didMutate
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                didMutate = removeItemAndDescendants(at: path) || didMutate
                continue
            }

            guard isIncluded(
                url,
                scanPaths: scanPaths,
                excludedPaths: excludedPaths,
                excludedExtensions: excludedExtensionSet
            ) else {
                didMutate = removeItemAndDescendants(at: path) || didMutate
                continue
            }

            if isDirectory.boolValue {
                let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
                if !isPackage, change.wasCreated || change.wasRenamed {
                    let previousCount = itemsByPath.count
                    scanFolder(
                        url,
                        resourceKeys: resourceKeys,
                        excludedPaths: excludedPaths,
                        excludedExtensions: excludedExtensionSet,
                        into: &itemsByPath
                    )
                    didMutate = itemsByPath.count != previousCount || didMutate
                }
                continue
            }

            if let item = makeFileItem(url: url, resourceKeys: resourceKeys) {
                if itemsByPath[path] != item {
                    itemsByPath[path] = item
                    didMutate = true
                }
            } else {
                didMutate = itemsByPath.removeValue(forKey: path) != nil || didMutate
            }
        }

        if didMutate {
            rebuildSortedCache()
        }
        return sortedCache
    }

    private func rebuildSortedCache() {
        sortedCache = itemsByPath.values.sorted {
            ($0.activityAt ?? .distantPast) > ($1.activityAt ?? .distantPast)
        }
    }

    private func removeItemAndDescendants(at path: String) -> Bool {
        let directoryPrefix = path.hasSuffix("/") ? path : path + "/"
        let previousCount = itemsByPath.count
        itemsByPath = itemsByPath.filter {
            $0.key != path && !$0.key.hasPrefix(directoryPrefix)
        }
        return itemsByPath.count != previousCount
    }
}

private func scanFolder(
    _ folder: URL,
    resourceKeys: Set<URLResourceKey>,
    excludedPaths: [String],
    excludedExtensions: Set<String>,
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
        guard !excludedExtensions.contains(url.pathExtension.lowercased()) else { continue }

        itemsByPath[url.standardizedFileURL.path] = FileItem(
            url: url,
            modifiedAt: values.contentModificationDate,
            createdAt: values.creationDate,
            addedAt: values.addedToDirectoryDate,
            metadataChangedAt: values.attributeModificationDate,
            kind: .recent
        )
    }
}

private func makeFileItem(url: URL, resourceKeys: Set<URLResourceKey>) -> FileItem? {
    guard let values = try? url.resourceValues(forKeys: resourceKeys),
          values.isDirectory != true,
          values.isRegularFile == true,
          values.isHidden != true else {
        return nil
    }

    return FileItem(
        url: url,
        modifiedAt: values.contentModificationDate,
        createdAt: values.creationDate,
        addedAt: values.addedToDirectoryDate,
        metadataChangedAt: values.attributeModificationDate,
        kind: .recent
    )
}

private func isIncluded(
    _ url: URL,
    scanPaths: [String],
    excludedPaths: [String],
    excludedExtensions: Set<String>
) -> Bool {
    let path = normalizedDirectoryPath(url)
    guard let scanPath = scanPaths.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
        return false
    }
    let relativePath = path.dropFirst(scanPath.count)
    let containsHiddenComponent = relativePath
        .split(separator: "/")
        .contains { $0.hasPrefix(".") }
    return !containsHiddenComponent
        && !isExcluded(url, excludedPaths: excludedPaths)
        && !excludedExtensions.contains(url.pathExtension.lowercased())
        && !hasPackageAncestor(url, below: scanPath)
}

/// Mirrors `.skipsPackageDescendants` for incremental FSEvents updates:
/// true when any directory between the scan root and `url` is a package (e.g. `Foo.app`).
private func hasPackageAncestor(_ url: URL, below scanPath: String) -> Bool {
    var ancestor = url.standardizedFileURL.deletingLastPathComponent()
    while true {
        let ancestorPath = normalizedDirectoryPath(ancestor)
        guard ancestorPath.count > scanPath.count, ancestorPath.hasPrefix(scanPath + "/") else {
            return false
        }
        if (try? ancestor.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            return true
        }
        ancestor = ancestor.deletingLastPathComponent()
    }
}

private func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
    let path = normalizedDirectoryPath(url)
    return excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
}

private func normalizedDirectoryPath(_ url: URL) -> String {
    url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}
