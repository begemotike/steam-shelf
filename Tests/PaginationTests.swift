import XCTest
@testable import SteamShelf

final class PaginationTests: XCTestCase {
    func testEmpty() {
        let p = Pagination(itemCount: 0)
        XCTAssertEqual(p.pageCount, 1)
        XCTAssertTrue(p.range(ofPage: 0).isEmpty)
        XCTAssertNil(p.leftHandleLabel(currentPage: 0))
        XCTAssertNil(p.rightHandleLabel(currentPage: 0))
    }

    func testPageCounts() {
        XCTAssertEqual(Pagination(itemCount: 16).pageCount, 1)
        let p17 = Pagination(itemCount: 17)
        XCTAssertEqual(p17.pageCount, 2)
        XCTAssertEqual(p17.range(ofPage: 1), 16..<17)
        XCTAssertEqual(Pagination(itemCount: 40).pageCount, 3)
    }

    func testSlot() {
        let s = Pagination(itemCount: 40).slot(ofItem: 21)
        XCTAssertEqual(s.page, 1); XCTAssertEqual(s.row, 1); XCTAssertEqual(s.column, 1)
    }

    func testHandleLabels() {
        let p = Pagination(itemCount: 40)
        XCTAssertNil(p.leftHandleLabel(currentPage: 0))
        XCTAssertEqual(p.leftHandleLabel(currentPage: 2), 2)
        XCTAssertEqual(p.rightHandleLabel(currentPage: 0), 2)
        XCTAssertNil(p.rightHandleLabel(currentPage: 2))
    }

    func testTargets() {
        let p = Pagination(itemCount: 40)
        XCTAssertEqual(p.target(for: .right, clickCount: 2, currentPage: 0), 2)
        XCTAssertEqual(p.target(for: .left, clickCount: 2, currentPage: 2), 0)
        XCTAssertEqual(p.target(for: .left, clickCount: 1, currentPage: 0), 0)
        XCTAssertEqual(p.target(for: .right, clickCount: 1, currentPage: 2), 2)
        XCTAssertEqual(p.target(for: .right, clickCount: 1, currentPage: 0), 1)
        XCTAssertEqual(p.clamp(99), 2)
        XCTAssertEqual(p.clamp(-3), 0)
    }
}
