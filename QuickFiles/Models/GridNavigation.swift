import Foundation

/// Vertical movement inside the quick panel: recents form a row-major grid of `columns`
/// columns and the bookmarks form a single row directly below it.
public enum GridDirection {
    case up
    case down
}

public enum GridNavigation {
    /// The ID that ↑/↓ should move focus to, or nil when focus should stay where it is.
    public static func target<ID: Hashable>(
        from current: ID?,
        direction: GridDirection,
        recentIDs: [ID],
        bookmarkIDs: [ID],
        columns: Int
    ) -> ID? {
        let columns = max(columns, 1)

        guard let current,
              let recentIndex = recentIDs.firstIndex(of: current) else {
            // No focus, or focus is not in either list: enter from the matching edge.
            if let current, bookmarkIDs.contains(current) {
                // Bookmarks sit below the grid: up goes to the last recent, down stays put.
                return direction == .up ? recentIDs.last : nil
            }
            switch direction {
            case .down:
                return recentIDs.first ?? bookmarkIDs.first
            case .up:
                return recentIDs.last ?? bookmarkIDs.last
            }
        }

        let row = recentIndex / columns

        switch direction {
        case .down:
            // Only when another row actually exists below this one; the ragged last row
            // clamps to its final item instead of jumping past it.
            if (row + 1) * columns < recentIDs.count {
                return recentIDs[min(recentIndex + columns, recentIDs.count - 1)]
            }
            return bookmarkIDs.first
        case .up:
            guard row > 0 else { return nil }
            return recentIDs[recentIndex - columns]
        }
    }
}
