import Foundation

enum HandleSide: Sendable { case left, right }

struct Pagination: Equatable, Sendable {
    static let columns = 4, rows = 4, perPage = 16
    let itemCount: Int

    var pageCount: Int { max(1, (max(0, itemCount) + Pagination.perPage - 1) / Pagination.perPage) }

    func clamp(_ page: Int) -> Int { min(max(page, 0), pageCount - 1) }

    func range(ofPage page: Int) -> Range<Int> {
        let p = clamp(page)
        let lower = min(p * Pagination.perPage, max(0, itemCount))
        let upper = min(lower + Pagination.perPage, max(0, itemCount))
        return lower..<upper
    }

    func page(ofItem index: Int) -> Int { max(0, index) / Pagination.perPage }

    func slot(ofItem index: Int) -> (page: Int, row: Int, column: Int) {
        let i = max(0, index)
        let within = i % Pagination.perPage
        return (i / Pagination.perPage, within / Pagination.columns, within % Pagination.columns)
    }

    func leftHandleLabel(currentPage: Int) -> Int? {
        let p = clamp(currentPage)
        return p > 0 ? p : nil   // previous page, 1-based == p
    }

    func rightHandleLabel(currentPage: Int) -> Int? {
        let p = clamp(currentPage)
        return p < pageCount - 1 ? p + 2 : nil   // next page, 1-based
    }

    func target(for side: HandleSide, clickCount: Int, currentPage: Int) -> Int {
        let p = clamp(currentPage)
        if clickCount >= 2 {
            return side == .left ? 0 : pageCount - 1
        }
        return clamp(side == .left ? p - 1 : p + 1)
    }
}
