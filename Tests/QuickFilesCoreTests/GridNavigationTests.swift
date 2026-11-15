import XCTest
@testable import QuickFilesCore

final class GridNavigationTests: XCTestCase {

    private let columns = 6

    // MARK: - Helpers

    private func recentIDs(_ count: Int) -> [String] {
        (0..<count).map { "r\($0)" }
    }

    private func bookmarkIDs(_ count: Int) -> [String] {
        (0..<count).map { "b\($0)" }
    }

    private func target(
        from current: String?,
        _ direction: GridDirection,
        recents: Int,
        bookmarks: Int = 0,
        columns: Int? = nil
    ) -> String? {
        GridNavigation.target(
            from: current,
            direction: direction,
            recentIDs: recentIDs(recents),
            bookmarkIDs: bookmarkIDs(bookmarks),
            columns: columns ?? self.columns
        )
    }

    // MARK: - Empty panel / no focus

    func testEmptyPanelReturnsNil() {
        XCTAssertNil(target(from: nil, .down, recents: 0))
        XCTAssertNil(target(from: nil, .up, recents: 0))
    }

    func testNoFocusDownEntersFirstRecent() {
        // Recent counts 0, 1, 5, 6, 7, 12, 13, 14; without bookmarks the entry point is r0.
        for count in [1, 5, 6, 7, 12, 13, 14] {
            XCTAssertEqual(target(from: nil, .down, recents: count), "r0", "recents: \(count)")
        }
    }

    func testNoFocusUpEntersLastRecent() {
        for count in [1, 5, 6, 7, 12, 13, 14] {
            XCTAssertEqual(target(from: nil, .up, recents: count), "r\(count - 1)", "recents: \(count)")
        }
    }

    func testNoFocusFallsBackToBookmarksWhenNoRecents() {
        XCTAssertEqual(target(from: nil, .down, recents: 0, bookmarks: 3), "b0")
        XCTAssertEqual(target(from: nil, .up, recents: 0, bookmarks: 3), "b2")
    }

    func testUnknownCurrentBehavesLikeNoFocus() {
        XCTAssertEqual(target(from: "zzz", .down, recents: 7), "r0")
        XCTAssertEqual(target(from: "zzz", .up, recents: 7), "r6")
        XCTAssertEqual(target(from: "zzz", .down, recents: 0, bookmarks: 2), "b0")
        XCTAssertNil(target(from: "zzz", .up, recents: 0))
    }

    // MARK: - Moving down inside the grid

    func testDownFromFirstRowKeepsColumn() {
        for count in [12, 13, 14] {
            for column in 0..<columns {
                XCTAssertEqual(
                    target(from: "r\(column)", .down, recents: count),
                    "r\(column + columns)",
                    "recents: \(count), column: \(column)"
                )
            }
        }
    }

    func testDownKeepsColumnAcrossEveryFullRow() {
        // 13 recents = row 0 (0-5), row 1 (6-11), ragged row 2 (12).
        XCTAssertEqual(target(from: "r0", .down, recents: 13), "r6")
        XCTAssertEqual(target(from: "r5", .down, recents: 13), "r11")
        XCTAssertEqual(target(from: "r6", .down, recents: 13), "r12")
        XCTAssertEqual(target(from: "r7", .down, recents: 13), "r12")   // ragged clamp
        XCTAssertEqual(target(from: "r11", .down, recents: 13), "r12")  // ragged clamp
    }

    func testRaggedLastRowClampsToItsLastItem() {
        // 14 recents = two full rows plus r12, r13.
        XCTAssertEqual(target(from: "r6", .down, recents: 14), "r12")
        XCTAssertEqual(target(from: "r7", .down, recents: 14), "r13")
        XCTAssertEqual(target(from: "r8", .down, recents: 14), "r13")
        XCTAssertEqual(target(from: "r11", .down, recents: 14), "r13")

        // 7 recents: only r6 sits below r0.
        for column in 0..<columns {
            XCTAssertEqual(target(from: "r\(column)", .down, recents: 7), "r6", "column: \(column)")
        }
    }

    func testDownFromLastRowGoesToFirstBookmark() {
        XCTAssertEqual(target(from: "r6", .down, recents: 7, bookmarks: 2), "b0")

        for index in 6..<12 {
            XCTAssertEqual(target(from: "r\(index)", .down, recents: 12, bookmarks: 3), "b0", "index: \(index)")
        }
        for index in 12..<14 {
            XCTAssertEqual(target(from: "r\(index)", .down, recents: 14, bookmarks: 1), "b0", "index: \(index)")
        }
    }

    func testDownFromLastRowWithoutBookmarksReturnsNil() {
        for count in [1, 5, 6, 7, 12, 13, 14] {
            XCTAssertNil(target(from: "r\(count - 1)", .down, recents: count), "recents: \(count)")
        }
    }

    // MARK: - Moving up inside the grid

    func testUpFromTopRowReturnsNil() {
        for count in [1, 5, 6, 7, 12, 13, 14] {
            for index in 0..<min(count, columns) {
                XCTAssertNil(target(from: "r\(index)", .up, recents: count), "recents: \(count), index: \(index)")
            }
        }
    }

    func testUpKeepsColumn() {
        for count in [7, 12, 13, 14] {
            for index in columns..<min(count, columns * 2) {
                XCTAssertEqual(
                    target(from: "r\(index)", .up, recents: count),
                    "r\(index - columns)",
                    "recents: \(count), index: \(index)"
                )
            }
        }
        // Ragged row 2 moves straight up to its own column in row 1, and row 2's last item
        // (r13) has no exact column in row 0.
        XCTAssertEqual(target(from: "r12", .up, recents: 14), "r6")
        XCTAssertEqual(target(from: "r13", .up, recents: 14), "r7")
        XCTAssertEqual(target(from: "r12", .up, recents: 13), "r6")
    }

    func testRoundTripDownThenUpReturnsToStart() {
        for count in [12, 13, 14] {
            for index in 0..<columns {
                guard let down = target(from: "r\(index)", .down, recents: count) else {
                    return XCTFail("expected a down target, recents: \(count), index: \(index)")
                }
                XCTAssertEqual(target(from: down, .up, recents: count), "r\(index)")
            }
        }
    }

    // MARK: - Bookmarks

    func testBookmarkUpGoesToLastRecent() {
        for count in [1, 5, 6, 7, 12, 13, 14] {
            XCTAssertEqual(target(from: "b0", .up, recents: count, bookmarks: 2), "r\(count - 1)", "recents: \(count)")
            XCTAssertEqual(target(from: "b1", .up, recents: count, bookmarks: 2), "r\(count - 1)", "recents: \(count)")
        }
    }

    func testBookmarkUpWithoutRecentsReturnsNil() {
        XCTAssertNil(target(from: "b0", .up, recents: 0, bookmarks: 3))
        XCTAssertNil(target(from: "b2", .up, recents: 0, bookmarks: 3))
    }

    func testBookmarkDownReturnsNil() {
        XCTAssertNil(target(from: "b0", .down, recents: 7, bookmarks: 2))
        XCTAssertNil(target(from: "b1", .down, recents: 7, bookmarks: 2))
        XCTAssertNil(target(from: "b0", .down, recents: 0, bookmarks: 1))
    }

    // MARK: - Columns

    func testColumnsBelowOneIsTreatedAsOne() {
        for value in [0, -1, -6] {
            XCTAssertEqual(target(from: nil, .down, recents: 5, columns: value), "r0")
            XCTAssertEqual(target(from: "r0", .down, recents: 5, columns: value), "r1", "columns: \(value)")
            XCTAssertEqual(target(from: "r1", .down, recents: 5, columns: value), "r2", "columns: \(value)")
            XCTAssertEqual(target(from: "r1", .up, recents: 5, columns: value), "r0", "columns: \(value)")
            XCTAssertNil(target(from: "r4", .down, recents: 5, columns: value), "columns: \(value)")
        }
    }

    func testSingleRecentGrid() {
        XCTAssertNil(target(from: "r0", .up, recents: 1))
        XCTAssertNil(target(from: "r0", .down, recents: 1))
        XCTAssertEqual(target(from: "r0", .down, recents: 1, bookmarks: 1), "b0")
        XCTAssertEqual(target(from: "b0", .up, recents: 1, bookmarks: 1), "r0")
    }
}
