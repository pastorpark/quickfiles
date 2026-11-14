import Foundation

/// Finder-like multi-selection over an ordered list of unique IDs.
///
/// Every mutating method receives the current ordered list of visible IDs. IDs that are
/// not present in that list are ignored, so selection can never point at an invisible row.
public struct SelectionModel<ID: Hashable>: Equatable {
    public private(set) var selectedIDs: Set<ID>
    public private(set) var anchorID: ID?
    public private(set) var focusedID: ID?

    public init() {
        self.selectedIDs = []
        self.anchorID = nil
        self.focusedID = nil
    }

    public var count: Int {
        selectedIDs.count
    }

    public func isSelected(_ id: ID) -> Bool {
        selectedIDs.contains(id)
    }

    /// Selected IDs in display order (never rely on Set iteration order).
    public func selectedIDs(in order: [ID]) -> [ID] {
        order.filter { selectedIDs.contains($0) }
    }

    /// Plain click / plain arrow target: select only `id`; anchor = focus = id.
    public mutating func selectOnly(_ id: ID, in order: [ID]) {
        guard order.contains(id) else { return }

        selectedIDs = [id]
        anchorID = id
        focusedID = id
    }

    /// Cmd-click: toggle membership of `id`; anchor = focus = id (focus may now be on an
    /// UNSELECTED item).
    public mutating func toggle(_ id: ID, in order: [ID]) {
        guard order.contains(id) else { return }

        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
        focusedID = id
    }

    /// Shift-click (additive == false): selection = contiguous range anchor...id (either
    /// direction), REPLACING the previous selection; anchor unchanged; focus = id.
    /// If there is no valid anchor, behaves like selectOnly.
    /// Cmd+Shift-click (additive == true): union of current selection and the range
    /// anchor...id; anchor unchanged; focus = id.
    public mutating func selectRange(to id: ID, in order: [ID], additive: Bool) {
        let index = indexMap(for: order)

        guard let targetIndex = index[id] else { return }
        guard let anchor = anchorID, let anchorIndex = index[anchor] else {
            selectOnly(id, in: order)
            return
        }

        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Set(order[lower...upper])

        if additive {
            selectedIDs.formUnion(rangeIDs)
        } else {
            selectedIDs = rangeIDs
        }
        anchorID = anchor
        focusedID = id
    }

    /// Arrow keys. Moves focus by `offset` positions, clamped to [0, order.count - 1].
    /// If there is no valid focus, focus the first item (offset >= 0) or last item
    /// (offset < 0) and select only it.
    public mutating func moveFocus(by offset: Int, in order: [ID], extending: Bool) {
        guard !order.isEmpty else { return }

        let index = indexMap(for: order)
        guard let current = focusedID, let currentIndex = index[current] else {
            let newFocus = offset >= 0 ? order[0] : order[order.count - 1]
            selectOnly(newFocus, in: order)
            return
        }

        let targetIndex = min(max(currentIndex + offset, 0), order.count - 1)
        let newFocus = order[targetIndex]

        if extending {
            selectRange(to: newFocus, in: order, additive: false)
        } else {
            selectOnly(newFocus, in: order)
        }
    }

    /// Cmd+A: select every ID in order; keep focus if valid else first; anchor = first.
    public mutating func selectAll(in order: [ID]) {
        guard let first = order.first else {
            clear()
            return
        }

        selectedIDs = Set(order)
        anchorID = first
        if let focus = focusedID, indexMap(for: order)[focus] != nil {
            focusedID = focus
        } else {
            focusedID = first
        }
    }

    /// Esc with count > 1: keep only the focused item if it is selected; otherwise keep
    /// the first selected item in display order. No-op when count <= 1.
    public mutating func collapseToFocus(in order: [ID]) {
        guard selectedIDs.count > 1 else { return }

        let firstSelected = selectedIDs(in: order).first

        if let focus = focusedID, selectedIDs.contains(focus) {
            selectedIDs = [focus]
            anchorID = focus
            focusedID = focus
        } else if let firstSelected {
            selectedIDs = [firstSelected]
            anchorID = firstSelected
            focusedID = firstSelected
        }
    }

    /// Clear everything.
    public mutating func clear() {
        selectedIDs.removeAll()
        anchorID = nil
        focusedID = nil
    }

    /// Called when the visible list changes (search/filter/rescan): intersect selection
    /// with `order`; if anchor/focus vanished, set them to the first remaining selected ID
    /// in display order (or nil). Must never add new selections.
    public mutating func reconcile(with order: [ID]) {
        let index = indexMap(for: order)

        selectedIDs.formIntersection(order)
        let firstSelected = selectedIDs(in: order).first

        if let anchor = anchorID, index[anchor] == nil {
            anchorID = firstSelected
        }
        if let focus = focusedID, index[focus] == nil {
            focusedID = firstSelected
        }
    }

    // MARK: - Helpers

    private func indexMap(for order: [ID]) -> [ID: Int] {
        var map: [ID: Int] = [:]
        map.reserveCapacity(order.count)
        for (position, id) in order.enumerated() {
            map[id] = position
        }
        return map
    }
}
