# Phase C — The window *is* the bookcase

Direction from the user (2026-09-29): "the whole window is the bookshelf, and any buttons etc. are built into the
top, bottom, and sides of the shelf." This supersedes DESIGN §4 (bookcase floating on linen), §6 (handles 20 du
outside the stiles) and §10 (separate header bar). Everything else in DESIGN.md still applies (palette, textures,
shadows, tiles, box, back label, editor, settings, empty state, motion).

## C.0 Concept
No backdrop, no floating case, no separate header. The wooden case frame fills the window edge to edge:
a **crown rail** across the top (holding the nameplate, page indicator, refresh + settings knobs, and the traffic
lights), a **stile** down each side (each holding one inlaid page handle), a **base rail** along the bottom
(status line + maker's mark), and the **bay** (back panel, 4 planks, boxes) filling everything in between.
Frame members have fixed point sizes; the bay flexes with the window. Boxes stay 2:3 and are sized to fit the bay.

## C.1 Geometry (`Theme.Metrics`, replace the bookcase constants)
- `crownH = 64`, `baseH = 44`, `stileW = 84`, `plinthH = 6`, `trafficLightClearance = 84` (left side of the crown).
- Window: `defaultSize 1180×960`, `minSize 820×700`, `.windowStyle(.hiddenTitleBar)`, content `ignoresSafeArea()` so the
  case wood runs under the title bar area; traffic lights float over the crown's left end.
- Bay rect = window minus crown/base/stiles. Bay layout is a **pure value type** `BayLayout` (new file
  `Sources/Model/BayLayout.swift`, unit-tested in `Tests/BayLayoutTests.swift`):
  ```swift
  struct BayLayout: Equatable {
      static let rows = 4, columns = 4
      static let sidePadMin: CGFloat = 28, gapMin: CGFloat = 14
      static let headroomRatio: CGFloat = 22/180, plankRatio: CGFloat = 20/180   // relative to boxH (DESIGN 222-row = 22 headroom + 180 box + 20 plank)
      let baySize: CGSize
      let boxW, boxH, gap, sidePad, rowH, plankH, scale: CGFloat   // scale = boxH / 180 (feeds the existing shelfScale environment)
      init(baySize: CGSize)          // rowH = baySize.height / 4; boxH = min(rowH / (1 + headroomRatio + plankRatio), ((baySize.width - 2*sidePadMin - 3*gapMin) / 4) * 1.5); boxW = boxH*2/3; gap = max(gapMin, (baySize.width - 2*sidePadMin - 4*boxW)/3); sidePad = (baySize.width - 4*boxW - 3*gap)/2; plankH = boxH*plankRatio
      func boxFrame(row: Int, col: Int) -> CGRect   // origin x = sidePad + col*(boxW+gap); bottom of box sits exactly on plank top: y = (row+1)*rowH - plankH - boxH
      func plankFrame(row: Int) -> CGRect           // full bay width, height plankH, y = (row+1)*rowH - plankH
      func slot(containing point: CGPoint) -> (row: Int, col: Int)?
  }
  ```
  Tests: 700×888 bay reproduces the old proportions (boxH 180±1, gap 36±1); a very wide bay (1600×600) keeps boxes
  2:3 and stretches `gap`; a narrow bay (652×592) yields boxH < rowH and gap == gapMin or larger; box bottoms
  equal plank tops for every row; frames of adjacent columns do not overlap.
- Everything inside tiles keeps using `shelfScale` (= `layout.scale`) for slivers, shadows, radii, fonts.

## C.2 Crown rail (replaces `HeaderBar`)
Full-width strip, `crownH` tall, case wood texture. Top 1 pt `walnutHighlight @ 80%`, bottom: 2 pt `black @ 55%` then
1 pt `white @ 6%` (the underside edge). Contents, vertically centered:
- Left: `trafficLightClearance` of empty wood.
- Center: brass nameplate 280×34 (existing `BrassPlate` + `EngravedText`), **inlaid**: no drop shadow; instead a
  1 pt `black @ 45%` rim on top/left and 1 pt `white @ 15%` on bottom/right, and two tiny brass screw heads
  (existing `Thumbtack`-style circles, 6 pt) at the plate's left and right ends.
- Right cluster (16 pt from the right edge, 10 pt spacing): page plate then two knobs.
  - **Page plate**: small brass plate 92×26, engraved `"PAGE 2 OF 3"` Copperplate 11 pt small caps, monospaced digits.
  - **Knobs** (refresh, settings): the existing 30 pt round brass buttons, but inlaid: sit in a 34 pt dark recess
    (`black @ 35%` circle with 1 pt inner highlight at the bottom) instead of casting a drop shadow. Refresh spins while
    loading (existing behaviour). Tooltips unchanged.

## C.3 Stiles + inlaid handles (replaces DESIGN §6 placement)
Each stile is `stileW` wide, case wood, with the stile shading gradient from `CaseView.stile` (lit from the left).
The handle (existing `HandleView` body, 46×150) is **mounted flush on the stile**, centered vertically in the bay's
height, centered horizontally in the stile:
- Behind it a **mortise**: rounded rect (r 8) 54×160, `black @ 40%`, with an inner shadow (`black @ 60%` 2 pt top/left
  inset stroke) so the handle looks set into the wood.
- Handle body keeps its brass number plate (neighbour page number), hover glow, pressed state, disabled dimming.
- Click / double-click behaviour unchanged (`model.handleTapped(side)`). With ≤ 16 games both handles show no number and
  are disabled.
- The existing `handleOffset`/`handleColumnW` constants and `BookcaseView.handleColumn` go away.

## C.4 Base rail
Full-width strip `baseH` tall, case wood; top edge: 1 pt `black @ 35%` + 10 pt `black @ 35% → 0` gradient (the bay's
shadow on the base). Bottom `plinthH` band `black @ 20%`.
- Left, 20 pt in: **status line**, Baskerville 12 small caps, `cream @ 85%`, monospaced digits, one line:
  demo → `"DEMO SHELF · 40 OF 50 TITLES SHELVED"`; loading → the loading message; failed → the error message in
  `Theme.Palette.brassLight` prefixed with `⚠`; idle with a library → `"UPDATED 3 MIN AGO · 20 OF 312 TITLES SHELVED"`
  (relative time via `RelativeDateTimeFormatter`, refreshed by a 60 s `TimelineView(.periodic)`); idle without a
  library → `"NOT CONNECTED — OPEN SETTINGS (⌘,)"`.
- Right, 20 pt in: maker's mark `"STEAM SHELF"` engraved (`EngravedText`) Copperplate 11, `brass @ 70%`.

## C.5 Bay
`BayView` now takes the flexible rect from a `GeometryReader` and a `BayLayout`. Back panel texture, gradient, under-plank
shadows, stile side shadows, planks (frame layer, full width at `plankFrame(row)`), `PageContainerView` (clipped),
empty-state card centered — all as before but positioned from `BayLayout`. `ShelfPageView` positions every tile with
`layout.boxFrame(row:col:)` and the contact shadow ellipse relative to it. No `.scaleEffect` anywhere.
Resizing the window must not animate tile positions (wrap layout-dependent changes in `Transaction(animation: nil)`
or use `.animation(nil, value: layout)`); the page push animation still works.

## C.6 Open-box overlay
- Dim covers the **whole window** (frame included) as now.
- The stage is centered in the **bay rect**, not the window: `stageSide = min(bayW - (editing ? editorPanelW + 60 : 80), bayH - 100)`.
- `LabelEditorPanel` is confined to the bay: leading edge ≥ bay minX, top = bay minY + 16, bottom = bay maxY − 16,
  trailing = bay maxX − 16. It must never cover the crown or base.
- Toolbar stays 24 pt under the box.
- The flyer's start/end frames still come from the tile's frame in `shelfSpace`; verify the box lands back exactly in
  its slot after a window resize while open (recompute `openedFromFrame` on close from the tile's current frame, or
  simply re-read the tile frame via the same `GeometryReader` path).

## C.7 Work packages
1. **C1 Layout core** — `BayLayout` + tests; `ShelfView` becomes `VStack(crown, HStack(stileL, bay, stileR), base)`
   filling the window; delete `BackdropView`, `BookcaseView`, the `bookcaseW/H/caseW/caseH/handleColumnW/handleOffset`
   metrics and the outer case shadow. Tiles laid out from `BayLayout`. Acceptance: `make test` green; demo shows the
   full-bleed case at 1180×960 and boxes stay 2:3 at 820×700 and at 1600×900.
2. **C2 Fixtures** — crown rail contents (§C.2), inlaid handles (§C.3), base rail (§C.4). Acceptance: screenshots at
   three sizes; all buttons/handles clickable; traffic lights do not overlap the nameplate at min width.
3. **C3 Overlay** — §C.6. Acceptance: open a box at 1180×960 and at 820×700; editor panel stays inside the bay;
   Escape returns the box to its slot.
4. **C4 Docs + commit** — update ARCHITECTURE §1 file list (add `Model/BayLayout.swift`, `Tests/BayLayoutTests.swift`;
   `HeaderBar` removed), add a note at the top of DESIGN §4/§6/§10 pointing here, update OPEN_QUESTIONS, commit.
