import XCTest
@testable import SteamShelf

final class BayLayoutTests: XCTestCase {
    private let sizes = [CGSize(width: 700, height: 888), CGSize(width: 1600, height: 600),
                         CGSize(width: 652, height: 592), CGSize(width: 1012, height: 852)]

    func testDesignBayReproducesOldProportions() {
        let l = BayLayout(baySize: CGSize(width: 700, height: 888))
        XCTAssertEqual(l.boxH, 180, accuracy: 1)
        XCTAssertEqual(l.boxW, 120, accuracy: 1)
        XCTAssertEqual(l.gap, 36, accuracy: 1)
        XCTAssertEqual(l.sidePad, 56, accuracy: 1)
        XCTAssertEqual(l.scale, 1, accuracy: 0.01)
    }

    func testVeryWideBayKeepsAspectAndStretchesGap() {
        let l = BayLayout(baySize: CGSize(width: 1600, height: 600))
        XCTAssertEqual(l.boxW / l.boxH, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertGreaterThan(l.gap, 100)
        XCTAssertEqual(l.boxH, 150 / (1 + BayLayout.headroomRatio + BayLayout.plankRatio), accuracy: 0.5)
    }

    func testNarrowBayShrinksBoxes() {
        let l = BayLayout(baySize: CGSize(width: 652, height: 592))
        XCTAssertLessThan(l.boxH, l.rowH)
        XCTAssertGreaterThanOrEqual(l.gap, BayLayout.gapMin)
        XCTAssertGreaterThanOrEqual(l.sidePad, BayLayout.sidePadMin - 0.001)
        // A very narrow bay is width-limited: gap pins to gapMin.
        let tight = BayLayout(baySize: CGSize(width: 400, height: 900))
        XCTAssertEqual(tight.gap, BayLayout.gapMin, accuracy: 0.001)
        XCTAssertEqual(tight.sidePad, BayLayout.sidePadMin, accuracy: 0.001)
    }

    func testBoxBottomsSitOnPlankTops() {
        for size in sizes {
            let l = BayLayout(baySize: size)
            for row in 0..<BayLayout.rows {
                for col in 0..<BayLayout.columns {
                    XCTAssertEqual(l.boxFrame(row: row, col: col).maxY, l.plankFrame(row: row).minY, accuracy: 0.001)
                }
                XCTAssertEqual(l.plankFrame(row: row).width, size.width, accuracy: 0.001)
            }
            XCTAssertEqual(l.plankFrame(row: 3).maxY, size.height, accuracy: 0.001)
        }
    }

    func testAdjacentColumnsDoNotOverlapAndFitInside() {
        for size in sizes {
            let l = BayLayout(baySize: size)
            for col in 0..<(BayLayout.columns - 1) {
                let a = l.boxFrame(row: 0, col: col), b = l.boxFrame(row: 0, col: col + 1)
                XCTAssertGreaterThanOrEqual(b.minX - a.maxX, BayLayout.gapMin - 0.001)
            }
            XCTAssertGreaterThanOrEqual(l.boxFrame(row: 0, col: 0).minX, 0)
            XCTAssertLessThanOrEqual(l.boxFrame(row: 0, col: 3).maxX, size.width + 0.001)
            XCTAssertGreaterThan(l.boxFrame(row: 0, col: 0).minY, 0)
        }
    }

    func testSlotHitTesting() {
        let l = BayLayout(baySize: CGSize(width: 1012, height: 852))
        let f = l.boxFrame(row: 2, col: 1)
        let hit = l.slot(containing: CGPoint(x: f.midX, y: f.midY))
        XCTAssertEqual(hit?.row, 2); XCTAssertEqual(hit?.col, 1)
        XCTAssertNil(l.slot(containing: CGPoint(x: -5, y: -5)))
    }
}
