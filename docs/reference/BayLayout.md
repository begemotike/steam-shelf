# BayLayout

Path: [`Sources/Model/BayLayout.swift`](../../Sources/Model/BayLayout.swift) (59 lines)

Pure geometry for the bay, the flexible area inside the case frame. Given a bay size it computes the box size (2:3 portrait), the gap and side padding, the row height, plank height and a `scale` relative to the 180-point design box, and it can return the frame of any box or plank. Everything is in the bay's own coordinate space. The file imports only `CoreGraphics`; `Theme.Metrics.boxH` is the single outside dependency.

## Depends on / used by

- Depends on: [Theme](Theme.md) (`Theme.Metrics.boxH` for `scale`).
- Used by: [ShelfView](ShelfView.md) (`BayView` builds it from a `GeometryReader`; `BayContent`, `ShelfPageView`), [Tests](Tests.md) (`BayLayoutTests`). `OpenBoxView` does not use it: it derives the bay rect from window size and frame metrics instead.

## `BayLayout`

`struct BayLayout: Equatable, Sendable`

### Constants

| Name | Value | Meaning |
|---|---|---|
| `rows`, `columns` | 4, 4 | Grid size (duplicates `Pagination`). |
| `sidePadMin`, `gapMin` | 28, 14 | Lower bounds in points. |
| `headroomRatio` | 22/180 | Space above a box inside its row, relative to `boxH`. |
| `plankRatio` | 20/180 | Plank height relative to `boxH`. |
| `sidePadRatio` | 56/180 | Preferred side padding relative to `boxH`. |
| `gapMaxRatio` | 0.75 | Gap never exceeds this fraction of `boxW`; extra width goes into side padding. |
| `surfaceRatio` | 8/180 | Visible top surface of the plank (we look slightly down on it). |

### Stored properties

`baySize: CGSize`, and `boxW, boxH, gap, sidePad, rowH, plankH, scale: CGFloat`.

### Computed properties

| Property | Formula |
|---|---|
| `plankSurfaceH` | `boxH * surfaceRatio` |
| `boxRestInset` | `plankSurfaceH * 0.75`: how far the bottom of each box sits below the plank's top edge. Planks draw *in front* of the boxes, so this much of each box's base is hidden behind the shelf edge. |

### `init(baySize:)`

Sizes are clamped to at least 1. `rowH = h / 4`. `byHeight = rowH / (1 + headroomRatio + plankRatio)`. `byWidth = ((w - 2*sidePadMin - 3*gapMin) / 4) * 1.5`. `boxH = max(1, min(byHeight, byWidth))` (height-limited in tall bays, width-limited in narrow ones), `boxW = boxH * 2/3`. `padTarget = max(sidePadMin, boxH * sidePadRatio)`. The natural gap is `(w - 2*padTarget - 4*boxW) / 3`; `gap = min(max(gapMin, natural), max(gapMin, boxW * gapMaxRatio))`. `sidePad` is then whatever centres the row: `(w - 4*boxW - 3*gap) / 2`. `plankH = boxH * plankRatio`, `scale = boxH / Theme.Metrics.boxH`.

For the 700 x 888 design bay this reproduces `boxH` 180, `boxW` 120, gap 36, side padding 56 and scale 1 (asserted in tests). The literal formula in the Phase C spec gave different numbers than the spec's own test; the shipped formula is the one above ([Phase C notes](../decisions/OPEN_QUESTIONS.md#implementation-notes-phase-c)).

### Methods

| Signature | Behaviour |
|---|---|
| `func boxFrame(row: Int, col: Int) -> CGRect` | `x = sidePad + col*(boxW+gap)`, `y = (row+1)*rowH - plankH + boxRestInset - boxH`, size `boxW x boxH`. The box bottom therefore lies `boxRestInset` below the plank's top edge. |
| `func plankFrame(row: Int) -> CGRect` | Full bay width, `y = (row+1)*rowH - plankH`, height `plankH`. The last plank's `maxY` equals the bay height. |
| `func slot(containing point: CGPoint) -> (row: Int, col: Int)?` | Hit test against box frames only (not gaps). Currently unused by the UI. |

## Gotchas

- `Equatable` is used by `ShelfPageView`'s `.animation(nil, value: layout)` so that window resizes never animate tile positions.
- The bay height is the full area between crown and base, so changing `Theme.Metrics.crownH` or `baseH` alters row height but not the formulas.

## See also

[Shelf rendering](../architecture/shelf-rendering.md), [Design spec](../design/DESIGN.md) (section 4 geometry; the formulas in this file supersede the literal numbers there).
