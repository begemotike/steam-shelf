# Pagination

Path: [`Sources/Model/Pagination.swift`](../../Sources/Model/Pagination.swift) (45 lines)

Pure arithmetic for a shelf of 16 boxes per page (4 columns by 4 rows). It is a value type constructed from an item count whenever needed (`AppModel.pagination` is computed), so there is no pagination state to keep in sync. Everything clamps rather than traps.

## Depends on / used by

- Depends on: nothing.
- Used by: [AppModel](AppModel.md) (`pagination`, `go(to:)`, `handleTapped`, `dragHover`), [ShelfView](ShelfView.md) (`ShelfPageView`, `StileView`, `CrownRail`), [BayLayout](BayLayout.md) shares the 4x4 constants by duplication (`BayLayout.rows/columns`), [Tests](Tests.md) (`PaginationTests`).

## Types

### `HandleSide`

`enum HandleSide: Sendable { case left, right }`. Which drawer-pull was pressed or hovered; also parameterises `StileView`/`HandleView`.

### `Pagination`

`struct Pagination: Equatable, Sendable`, field `let itemCount: Int`. Constants: `columns = 4`, `rows = 4`, `perPage = 16`.

| Member | Signature | Behaviour |
|---|---|---|
| `pageCount` | `var pageCount: Int` | `max(1, ceil(max(0, itemCount) / 16))`; an empty shelf still has one (empty) page. |
| `clamp` | `func clamp(_ page: Int) -> Int` | `min(max(page, 0), pageCount - 1)`. |
| `range(ofPage:)` | `func range(ofPage page: Int) -> Range<Int>` | Item index range for the (clamped) page; empty for an empty shelf. |
| `page(ofItem:)` | `func page(ofItem index: Int) -> Int` | Negative indices treated as 0. |
| `slot(ofItem:)` | `func slot(ofItem index: Int) -> (page: Int, row: Int, column: Int)` | Row-major within a page. |
| `leftHandleLabel(currentPage:)` | `-> Int?` | 1-based number of the previous page, `nil` on the first page (handle disabled). |
| `rightHandleLabel(currentPage:)` | `-> Int?` | 1-based number of the next page, `nil` on the last page. |
| `target(for:clickCount:currentPage:)` | `-> Int` | Double click (`clickCount >= 2`) goes to the first (left) or last (right) page; a single click moves one page, clamped. |

## Gotchas

- Items are the *shelved* entries only; unticking a game on the last page can reduce `pageCount`, so `AppModel` re-clamps `pageIndex` after every shelf mutation.
- `rows`, `columns` and `perPage` are duplicated in `BayLayout` (`rows`, `columns`) and `Pagination`; `ShelfPageView` computes row/column as `index / Pagination.columns`, `index % Pagination.columns`.

## See also

[Shelf rendering](../architecture/shelf-rendering.md), [App and state](../architecture/app-and-state.md).
