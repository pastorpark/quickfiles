import AppKit
import Combine

@MainActor
final class PanelViewModel: ObservableObject {
    struct Snapshot: Equatable {
        var recentItems: [FileItem] = []
        var bookmarkItems: [FileItem] = []
        var orderedIDs: [FileItem.ID] = []          // recents, then bookmarks; UNIQUE
        var itemsByID: [FileItem.ID: FileItem] = [:]
        var isSearching = false
    }

    @Published var query = ""                           // bound to the search TextField
    @Published private(set) var snapshot = Snapshot()
    @Published var selection = SelectionModel<FileItem.ID>()

    private let store: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(store: SettingsStore, controller: PanelController) {
        self.store = store
        observeInputs(controller: controller)
    }

    var selectedItems: [FileItem] {
        selection.selectedIDs(in: snapshot.orderedIDs).compactMap { snapshot.itemsByID[$0] }
    }

    var focusedItem: FileItem? {
        guard let focusedID = selection.focusedID else { return nil }
        return snapshot.itemsByID[focusedID]
    }

    /// The item single-item actions use: focused item if it is selected, else first selected item, else nil.
    var primaryItem: FileItem? {
        if let focusedID = selection.focusedID,
           selection.isSelected(focusedID),
           let item = snapshot.itemsByID[focusedID] {
            return item
        }
        return selectedItems.first
    }

    // MARK: - Observation

    private func observeInputs(controller: PanelController) {
        // Empty query applies immediately; non-empty waits 150 ms and a newer query cancels the older one.
        let debouncedQuery = $query
            .removeDuplicates()
            .map { query -> AnyPublisher<String, Never> in
                if query.isEmpty {
                    return Just(query).eraseToAnyPublisher()
                }
                return Just(query)
                    .delay(for: .milliseconds(150), scheduler: RunLoop.main)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()

        Publishers.CombineLatest4(
            controller.$items,
            controller.$searchableItems,
            store.$bookmarks,
            debouncedQuery
        )
        .sink { [weak self] items, searchableItems, bookmarks, query in
            self?.rebuild(
                items: items,
                searchableItems: searchableItems,
                bookmarks: bookmarks,
                query: query
            )
        }
        .store(in: &cancellables)
    }

    // MARK: - Snapshot

    /// Rebuilds from the emitted publisher values. Never reads the observed properties
    /// directly: `@Published` emits before the property itself is updated.
    private func rebuild(
        items: [FileItem],
        searchableItems: [FileItem],
        bookmarks: [StoredBookmark],
        query: String
    ) {
        let terms = Self.searchTerms(from: query)
        let matches: (FileItem) -> Bool = { item in
            guard !terms.isEmpty else { return true }
            return terms.allSatisfy(item.searchText.contains)
        }

        let recentItems = terms.isEmpty ? items : searchableItems.filter(matches)

        var visiblePaths = Set<String>()
        visiblePaths.reserveCapacity(recentItems.count)
        for item in recentItems {
            visiblePaths.insert(item.url.standardizedFileURL.path)
        }

        // A file must appear only once: drop bookmarks already present in the recents.
        let bookmarkItems = bookmarks
            .map { FileItem(url: $0.url, modifiedAt: nil, createdAt: nil, kind: .bookmark) }
            .filter(matches)
            .filter { !visiblePaths.contains($0.url.standardizedFileURL.path) }

        var orderedIDs: [FileItem.ID] = []
        var itemsByID: [FileItem.ID: FileItem] = [:]
        let capacity = recentItems.count + bookmarkItems.count
        orderedIDs.reserveCapacity(capacity)
        itemsByID.reserveCapacity(capacity)

        for item in recentItems {
            guard itemsByID[item.id] == nil else { continue }
            orderedIDs.append(item.id)
            itemsByID[item.id] = item
        }
        for item in bookmarkItems {
            guard itemsByID[item.id] == nil else { continue }
            orderedIDs.append(item.id)
            itemsByID[item.id] = item
        }

        snapshot = Snapshot(
            recentItems: recentItems,
            bookmarkItems: bookmarkItems,
            orderedIDs: orderedIDs,
            itemsByID: itemsByID,
            isSearching: !terms.isEmpty
        )

        selection.reconcile(with: orderedIDs)
        if selection.count == 0, selection.focusedID == nil, let first = orderedIDs.first {
            selection.selectOnly(first, in: orderedIDs)
        }
    }

    private static func searchTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map {
                String($0).folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
            }
    }
}
