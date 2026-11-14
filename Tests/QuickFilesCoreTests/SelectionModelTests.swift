import XCTest
@testable import QuickFilesCore

final class SelectionModelTests: XCTestCase {

    private let order = ["a", "b", "c", "d", "e"]

    private func makeModel(selecting ids: [String] = []) -> SelectionModel<String> {
        var model = SelectionModel<String>()
        guard let first = ids.first else { return model }
        model.selectOnly(first, in: order)
        for id in ids.dropFirst() {
            model.toggle(id, in: order)
        }
        return model
    }

    // MARK: - Initial state

    func testInitialStateIsEmpty() {
        let model = SelectionModel<String>()

        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.focusedID)
        XCTAssertEqual(model.selectedIDs, [])
        XCTAssertEqual(model.selectedIDs(in: order), [])
        XCTAssertFalse(model.isSelected("a"))
    }

    // MARK: - selectOnly

    func testSelectOnlyReplacesSelectionAndSetsAnchorAndFocus() {
        var model = makeModel(selecting: ["a", "b"])

        model.selectOnly("d", in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["d"])
        XCTAssertEqual(model.anchorID, "d")
        XCTAssertEqual(model.focusedID, "d")
        XCTAssertEqual(model.count, 1)
        XCTAssertTrue(model.isSelected("d"))
        XCTAssertFalse(model.isSelected("a"))
    }

    func testSelectOnlyIgnoresUnknownID() {
        var model = makeModel(selecting: ["b"])

        model.selectOnly("zzz", in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["b"])
        XCTAssertEqual(model.anchorID, "b")
        XCTAssertEqual(model.focusedID, "b")
    }

    // MARK: - toggle

    func testToggleAddsAndRemoves() {
        var model = SelectionModel<String>()

        model.toggle("c", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["c"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "c")

        model.toggle("a", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["a", "c"])

        model.toggle("c", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["a"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "c")
        XCTAssertFalse(model.isSelected("c"))
    }

    func testToggleCanLeaveFocusOnUnselectedItem() {
        var model = makeModel(selecting: ["a"])

        model.toggle("a", in: order)

        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.focusedID, "a")
        XCTAssertEqual(model.anchorID, "a")
        XCTAssertFalse(model.isSelected("a"))
    }

    func testToggleIgnoresUnknownID() {
        var model = makeModel(selecting: ["b"])

        model.toggle("zzz", in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["b"])
        XCTAssertEqual(model.focusedID, "b")
    }

    // MARK: - selectRange

    func testForwardShiftRangeReplacesSelection() {
        var model = makeModel(selecting: ["a"])

        model.selectRange(to: "d", in: order, additive: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["a", "b", "c", "d"])
        XCTAssertEqual(model.anchorID, "a")
        XCTAssertEqual(model.focusedID, "d")
    }

    func testReverseShiftRangeReplacesSelection() {
        var model = makeModel(selecting: ["e"])

        model.selectRange(to: "c", in: order, additive: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d", "e"])
        XCTAssertEqual(model.anchorID, "e")
        XCTAssertEqual(model.focusedID, "c")
    }

    func testRangeWithoutAnchorBehavesLikeSelectOnly() {
        var model = SelectionModel<String>()

        model.selectRange(to: "c", in: order, additive: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["c"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "c")
    }

    func testRangeWithStaleAnchorBehavesLikeSelectOnly() {
        var model = makeModel(selecting: ["a"])
        model.reconcile(with: ["b", "c", "d", "e"])

        XCTAssertNil(model.anchorID)

        model.selectRange(to: "d", in: order, additive: true)

        XCTAssertEqual(model.selectedIDs(in: order), ["d"])
        XCTAssertEqual(model.anchorID, "d")
        XCTAssertEqual(model.focusedID, "d")
    }

    func testAdditiveRangeUnionsSelection() {
        var model = makeModel(selecting: ["a", "b"])
        model.selectOnly("c", in: order)
        model.toggle("e", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["c", "e"])
        XCTAssertEqual(model.anchorID, "e")

        // Anchor is "e", so add the range c...e on top of the existing selection.
        model.selectRange(to: "c", in: order, additive: true)

        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d", "e"])
        XCTAssertEqual(model.anchorID, "e")
        XCTAssertEqual(model.focusedID, "c")
    }

    func testAdditiveRangeDoesNotShrinkEarlierSelection() {
        var model = makeModel(selecting: ["a", "d"])
        model.selectOnly("c", in: order)
        XCTAssertEqual(model.anchorID, "c")

        model.selectRange(to: "d", in: order, additive: true)
        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d"])

        // Existing selection holds "a"? No: selectOnly replaced it. Add "a" first.
        model.toggle("a", in: order)
        XCTAssertEqual(model.anchorID, "a")
        model.selectRange(to: "b", in: order, additive: true)

        XCTAssertEqual(model.selectedIDs(in: order), ["a", "b", "c", "d"])
        XCTAssertEqual(model.focusedID, "b")
    }

    func testSelectRangeIgnoresUnknownTarget() {
        var model = makeModel(selecting: ["b"])

        model.selectRange(to: "zzz", in: order, additive: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["b"])
        XCTAssertEqual(model.anchorID, "b")
        XCTAssertEqual(model.focusedID, "b")
    }

    func testSelectRangeToAnchorSelectsSingleItem() {
        var model = makeModel(selecting: ["c"])

        model.selectRange(to: "c", in: order, additive: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["c"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "c")
    }

    // MARK: - moveFocus

    func testMoveFocusWithoutExtendingSelectsOnlyNewFocus() {
        var model = makeModel(selecting: ["b"])
        model.selectRange(to: "d", in: order, additive: false)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c", "d"])

        model.moveFocus(by: 1, in: order, extending: false)

        XCTAssertEqual(model.selectedIDs(in: order), ["e"])
        XCTAssertEqual(model.anchorID, "e")
        XCTAssertEqual(model.focusedID, "e")
    }

    func testMoveFocusWithExtendingShrinksOnReversal() {
        var model = SelectionModel<String>()
        model.selectOnly("c", in: order)

        model.moveFocus(by: 1, in: order, extending: true)
        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d"])
        XCTAssertEqual(model.anchorID, "c")

        model.moveFocus(by: 1, in: order, extending: true)
        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d", "e"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "e")

        model.moveFocus(by: -1, in: order, extending: true)
        XCTAssertEqual(model.selectedIDs(in: order), ["c", "d"])
        XCTAssertEqual(model.anchorID, "c")
        XCTAssertEqual(model.focusedID, "d")
    }

    func testMoveFocusWithExtendingBackwards() {
        var model = SelectionModel<String>()
        model.selectOnly("d", in: order)

        model.moveFocus(by: -2, in: order, extending: true)

        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c", "d"])
        XCTAssertEqual(model.anchorID, "d")
        XCTAssertEqual(model.focusedID, "b")
    }

    func testMoveFocusClampsAtBothEnds() {
        var model = SelectionModel<String>()
        model.selectOnly("c", in: order)

        model.moveFocus(by: -99, in: order, extending: false)
        XCTAssertEqual(model.focusedID, "a")
        XCTAssertEqual(model.selectedIDs(in: order), ["a"])

        model.moveFocus(by: 99, in: order, extending: false)
        XCTAssertEqual(model.focusedID, "e")
        XCTAssertEqual(model.selectedIDs(in: order), ["e"])
    }

    func testMoveFocusWithNoFocusUsesFirstForPositiveOffset() {
        var model = SelectionModel<String>()

        model.moveFocus(by: 2, in: order, extending: false)

        XCTAssertEqual(model.focusedID, "a")
        XCTAssertEqual(model.anchorID, "a")
        XCTAssertEqual(model.selectedIDs(in: order), ["a"])
    }

    func testMoveFocusWithNoFocusUsesLastForNegativeOffset() {
        var model = SelectionModel<String>()

        model.moveFocus(by: -1, in: order, extending: true)

        XCTAssertEqual(model.focusedID, "e")
        XCTAssertEqual(model.anchorID, "e")
        XCTAssertEqual(model.selectedIDs(in: order), ["e"])
    }

    // MARK: - selectAll

    func testSelectAllSelectsEverythingAndSetsAnchorToFirst() {
        var model = makeModel(selecting: ["c"])

        model.selectAll(in: order)

        XCTAssertEqual(model.selectedIDs(in: order), order)
        XCTAssertEqual(model.count, order.count)
        XCTAssertEqual(model.anchorID, "a")
        XCTAssertEqual(model.focusedID, "c")
    }

    func testSelectAllUsesFirstFocusWhenFocusInvalid() {
        var model = SelectionModel<String>()
        model.toggle("d", in: order)
        model.reconcile(with: ["a", "b", "c"])

        model.selectAll(in: order)

        XCTAssertEqual(model.selectedIDs(in: order), order)
        XCTAssertEqual(model.focusedID, "a")
        XCTAssertEqual(model.anchorID, "a")
    }

    // MARK: - collapseToFocus

    func testCollapseToFocusKeepsFocusedItemWhenSelected() {
        var model = makeModel(selecting: ["b", "d"])
        model.toggle("d", in: order)
        model.toggle("e", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "e"])
        XCTAssertEqual(model.focusedID, "e")

        model.collapseToFocus(in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["e"])
        XCTAssertEqual(model.focusedID, "e")
        XCTAssertEqual(model.anchorID, "e")
    }

    func testCollapseToFocusFallsBackToFirstSelectedWhenFocusUnselected() {
        var model = makeModel(selecting: ["b", "c"])
        model.toggle("e", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c", "e"])
        XCTAssertEqual(model.focusedID, "e")

        model.toggle("e", in: order)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c"])
        XCTAssertEqual(model.focusedID, "e")
        XCTAssertFalse(model.isSelected("e"))
        XCTAssertEqual(model.count, 2)

        model.collapseToFocus(in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["b"])
        XCTAssertEqual(model.focusedID, "b")
        XCTAssertEqual(model.anchorID, "b")
    }

    func testCollapseToFocusIsNoOpWhenCountIsOne() {
        var model = makeModel(selecting: ["c"])
        XCTAssertEqual(model.count, 1)

        model.collapseToFocus(in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["c"])
        XCTAssertEqual(model.focusedID, "c")
        XCTAssertEqual(model.anchorID, "c")
    }

    func testCollapseToFocusIsNoOpWhenEmpty() {
        var model = SelectionModel<String>()

        model.collapseToFocus(in: order)

        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.focusedID)
    }

    // MARK: - clear

    func testClearRemovesEverything() {
        var model = makeModel(selecting: ["a", "c"])

        model.clear()

        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.focusedID)
        XCTAssertEqual(model.selectedIDs(in: order), [])
    }

    // MARK: - reconcile

    func testReconcileRemovesVanishedItems() {
        var model = makeModel(selecting: ["a", "c", "e"])

        model.reconcile(with: ["a", "b", "c"])

        XCTAssertEqual(model.selectedIDs(in: order), ["a", "c"])
        XCTAssertEqual(model.count, 2)
        XCTAssertEqual(model.anchorID, "a")
        XCTAssertEqual(model.focusedID, "a")
    }

    func testReconcileRepairsVanishedAnchorAndFocus() {
        var model = SelectionModel<String>()
        model.selectOnly("b", in: order)
        model.selectRange(to: "d", in: order, additive: false)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c", "d"])
        XCTAssertEqual(model.anchorID, "b")
        XCTAssertEqual(model.focusedID, "d")

        model.reconcile(with: ["b", "c"])

        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c"])
        XCTAssertEqual(model.anchorID, "b")
        XCTAssertEqual(model.focusedID, "b")
    }

    func testReconcileRepairsVanishedAnchorButKeepsPresentFocus() {
        var model = SelectionModel<String>()
        model.selectOnly("b", in: order)
        model.selectRange(to: "e", in: order, additive: false)
        XCTAssertEqual(model.selectedIDs(in: order), ["b", "c", "d", "e"])
        XCTAssertEqual(model.anchorID, "b")
        XCTAssertEqual(model.focusedID, "e")

        model.reconcile(with: ["d", "e"])

        XCTAssertEqual(model.selectedIDs(in: order), ["d", "e"])
        XCTAssertEqual(model.anchorID, "d")
        XCTAssertEqual(model.focusedID, "e")
    }

    func testReconcileDoesNotReselectAfterDeselectAll() {
        var model = makeModel(selecting: ["a", "b"])
        model.clear()

        model.reconcile(with: ["a", "b", "c"])

        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.focusedID)
        XCTAssertEqual(model.selectedIDs(in: order), [])
    }

    func testReconcileKeepsFocusWhenStillPresentButUnselected() {
        var model = makeModel(selecting: ["c"])
        model.toggle("c", in: order)
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.focusedID, "c")

        model.reconcile(with: order)

        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.focusedID, "c")
        XCTAssertEqual(model.anchorID, "c")
    }

    func testReconcileWithEmptyOrderClearsEverything() {
        var model = makeModel(selecting: ["a", "d"])

        model.reconcile(with: [])

        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.focusedID)
    }

    // MARK: - Empty order safety

    func testEveryMethodHandlesEmptyOrderWithoutCrashing() {
        var model = makeModel(selecting: ["a"])

        model.selectOnly("a", in: [])
        XCTAssertEqual(model.selectedIDs(in: order), ["a"])
        XCTAssertEqual(model.focusedID, "a")

        model.toggle("a", in: [])
        model.selectRange(to: "a", in: [], additive: false)
        model.selectRange(to: "a", in: [], additive: true)
        model.moveFocus(by: 1, in: [], extending: false)
        model.moveFocus(by: -1, in: [], extending: true)
        model.selectAll(in: [])
        XCTAssertEqual(model.count, 0)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.focusedID)

        model.collapseToFocus(in: [])
        model.reconcile(with: [])
        model.clear()
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.selectedIDs(in: []), [])
    }

    // MARK: - Display order

    func testSelectedIDsFollowDisplayOrderRegardlessOfSelectionOrder() {
        var model = SelectionModel<String>()
        model.toggle("e", in: order)
        model.toggle("b", in: order)
        model.toggle("d", in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["b", "d", "e"])

        model.toggle("d", in: order)

        XCTAssertEqual(model.selectedIDs(in: order), ["b", "e"])
    }

    func testSelectedIDsIgnoresIDsNotInOrder() {
        var model = makeModel(selecting: ["a", "c"])

        XCTAssertEqual(model.selectedIDs(in: ["c", "a"]), ["c", "a"])
        XCTAssertEqual(model.selectedIDs(in: ["a"]), ["a"])
    }

    // MARK: - Equatable

    func testEquatableComparesSelectionAnchorAndFocus() {
        var first = makeModel(selecting: ["a", "b"])
        let second = makeModel(selecting: ["a", "b"])
        XCTAssertEqual(first, second)

        first.toggle("c", in: order)
        XCTAssertNotEqual(first, second)
    }
}
