import Foundation

/// Splits a selection into what must be moved, what is pointless to move and what travels inside a moving folder.
public struct MovePlan: Equatable {
    /// Move these.
    public var toMove: [URL]
    /// Already in the destination, or a folder that would move into itself / its own subfolder.
    public var skipped: [URL]
    /// Not moved separately because a selected folder that IS moving contains them.
    public var carried: [URL]
}

public enum MovePlanner {
    /// Pure planning (no file system writes), O(n · path depth).
    ///
    /// - Items already in the destination are skipped, as are folders that contain the destination.
    /// - A child of a skipped folder is still moved; a child of a moving folder is carried by it.
    /// - Symlinks are never treated as folders, so a path reached through a symlink is not carried by it.
    public static func plan(_ urls: [URL], to destination: URL) -> MovePlan {
        let dest = destination.resolvingSymlinksInPath().standardizedFileURL.path
        let unique = deduplicated(urls)

        var eligible: [URL] = []
        var skipped: [URL] = []
        var movingDirectories = Set<String>()
        eligible.reserveCapacity(unique.count)
        skipped.reserveCapacity(unique.count)

        for url in unique {
            let path = url.standardizedFileURL.path
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path

            if parent == dest {
                skipped.append(url)
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isRealDirectory = values?.isDirectory == true && values?.isSymbolicLink != true

            if isRealDirectory {
                let real = url.resolvingSymlinksInPath().standardizedFileURL.path
                if dest == real || dest.hasPrefix(real + "/") {
                    skipped.append(url)
                    continue
                }
                movingDirectories.insert(path)
            }

            eligible.append(url)
        }

        var toMove: [URL] = []
        var carried: [URL] = []
        toMove.reserveCapacity(eligible.count)
        carried.reserveCapacity(eligible.count)

        for url in eligible {
            if hasMovingAncestor(url.standardizedFileURL.path, movingDirectories: movingDirectories) {
                carried.append(url)
            } else {
                toMove.append(url)
            }
        }

        return MovePlan(toMove: toMove, skipped: skipped, carried: carried)
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var unique: [URL] = []
        unique.reserveCapacity(urls.count)
        for url in urls {
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            unique.append(url)
        }
        return unique
    }

    /// Walks up the standardized path looking for a directory that is itself being moved.
    private static func hasMovingAncestor(_ path: String, movingDirectories: Set<String>) -> Bool {
        guard !movingDirectories.isEmpty else { return false }
        var ancestor = (path as NSString).deletingLastPathComponent
        while !ancestor.isEmpty, ancestor != "/" {
            if movingDirectories.contains(ancestor) {
                return true
            }
            let next = (ancestor as NSString).deletingLastPathComponent
            if next == ancestor {
                break
            }
            ancestor = next
        }
        return false
    }
}
