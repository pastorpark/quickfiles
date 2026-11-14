import XCTest
@testable import QuickFilesCore

final class MovePlannerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func makeDirectory(_ path: String) -> URL {
        let url = tempDirectory.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFile(_ path: String) -> URL {
        let url = tempDirectory.appendingPathComponent(path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))
        return url
    }

    @discardableResult
    private func makeSymlink(_ path: String, to destination: URL) -> URL {
        let url = tempDirectory.appendingPathComponent(path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
        return url
    }

    private func paths(_ urls: [URL]) -> [String] {
        urls.map { $0.standardizedFileURL.path }
    }

    // MARK: - Basic planning

    func testEmptyInputProducesEmptyPlan() {
        let destination = makeDirectory("D")

        let plan = MovePlanner.plan([], to: destination)

        XCTAssertEqual(plan, MovePlan(toMove: [], skipped: [], carried: []))
    }

    func testFileInDestinationIsSkippedAndFileElsewhereMoves() {
        let destination = makeDirectory("D")
        let inside = makeFile("D/notes.txt")
        let outside = makeFile("E/notes.txt")

        let plan = MovePlanner.plan([inside, outside], to: destination)

        XCTAssertEqual(paths(plan.toMove), paths([outside]))
        XCTAssertEqual(paths(plan.skipped), paths([inside]))
        XCTAssertTrue(plan.carried.isEmpty)
    }

    func testDuplicateURLsCollapseKeepingFirstOccurrence() {
        let destination = makeDirectory("D")
        let first = makeFile("E/first.txt")
        let second = makeFile("E/second.txt")

        let plan = MovePlanner.plan([first, second, first], to: destination)

        XCTAssertEqual(paths(plan.toMove), paths([first, second]))
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertTrue(plan.carried.isEmpty)
    }

    // MARK: - Folders

    func testChildOfSkippedFolderIsStillMoved() {
        let destination = makeDirectory("D")
        let folder = makeDirectory("D/A")
        let child = makeFile("D/A/file.txt")

        let plan = MovePlanner.plan([folder, child], to: destination)

        XCTAssertEqual(paths(plan.skipped), paths([folder]))
        XCTAssertEqual(paths(plan.toMove), paths([child]))
        XCTAssertTrue(plan.carried.isEmpty)
    }

    func testChildOfMovingFolderIsCarried() throws {
        let destination = makeDirectory("Y")
        let folder = makeDirectory("X/A")
        let child = makeFile("X/A/f.txt")
        let nestedChild = makeFile("X/A/B/g.txt")

        let plan = MovePlanner.plan([folder, child, nestedChild], to: destination)

        XCTAssertEqual(paths(plan.toMove), paths([folder]))
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertEqual(Set(paths(plan.carried)), Set(paths([child, nestedChild])))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFolderEqualToDestinationIsSkipped() {
        let folder = makeDirectory("X/A")

        let plan = MovePlanner.plan([folder], to: folder)

        XCTAssertTrue(plan.toMove.isEmpty)
        XCTAssertEqual(paths(plan.skipped), paths([folder]))
        XCTAssertTrue(plan.carried.isEmpty)
    }

    func testFolderContainingDestinationIsSkipped() {
        let folder = makeDirectory("X/A")
        let destination = makeDirectory("X/A/sub")

        let plan = MovePlanner.plan([folder], to: destination)

        XCTAssertTrue(plan.toMove.isEmpty)
        XCTAssertEqual(paths(plan.skipped), paths([folder]))
        XCTAssertTrue(plan.carried.isEmpty)
    }

    // MARK: - Symlinks

    func testSymlinkedFolderAndItsChildAreBothMoved() {
        let destination = makeDirectory("Y")
        let real = makeDirectory("X/real")
        let throughLink = makeFile("X/real/f.txt")
        let link = makeSymlink("X/link", to: real)
        let linkedChild = link.appendingPathComponent("f.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedChild.path))

        let plan = MovePlanner.plan([link, linkedChild], to: destination)

        XCTAssertEqual(Set(paths(plan.toMove)), Set(paths([link, linkedChild])))
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertTrue(plan.carried.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: throughLink.path))
    }
}
