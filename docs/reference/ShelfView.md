# ShelfView

Path: [`Sources/Views/ShelfView.swift`](../../Sources/Views/ShelfView.swift) (816 lines)

The root view and the whole shelf: the window *is* the bookcase. `ShelfView` stacks the case frame and the open-box overlay and owns window-level behaviour (keyboard paging, swipe monitor, export/import presentation, startup task). `CaseFrameView` lays out the crown rail, two stiles, the flexible bay and the base rail. The bay renders back panel, shadows, shelf lights, the current page of boxes and the planks (drawn in front of the boxes). The file also contains the box tile with its drag-and-drop and lighting, the cover loader, and the empty-state card.

## Depends on / used by

- Depends on: [AppModel](AppModel.md), [BayLayout](BayLayout.md), [Pagination](Pagination.md), [Theme](Theme.md), [ArtGenerator](ArtGenerator.md) (`TextureLibrary`, `CoverPalette`, `placeholderCover`, `headerCover`, `spineColor`), [ImageCache](ImageCache.md), [HandleView](HandleView.md), [SwipeMonitor](SwipeMonitor.md), [OpenBoxView](OpenBoxView.md), [SteamShelfApp](SteamShelfApp.md) (`ShelfFile`, `UTType.steamShelf`).
- Used by: [SteamShelfApp](SteamShelfApp.md) (window content), [OpenBoxView](OpenBoxView.md) (`ReadyCover`, `CoverLoader.recent`).

## Top-level types

| Type | Kind | Role |
|---|---|---|
| `DraggedBox` | `struct: Codable, Transferable` | Drag payload `{ appID }`; `CodableRepresentation(contentType: .steamShelfBox)`. |
| `UTType.steamShelfBox` | extension | `UTType(exportedAs: "net.outofajam.steamshelf.box")`, declared in `Info.plist`. |
| `ShelfView` | `View` | Root. |
| `CaseFrameView`, `CrownRail`, `BaseRail`, `StileView` | `View` | Case frame members. |
| `BayView`, `BayContent` (private) | `View` | Bay geometry and content. |
| `LightStrip`, `PlankView` | `View` | Lighting and planks. |
| `PageContainerView`, `ShelfPageView` | `View` | Page push transition and the 4x4 grid. |
| `ReadyCover`, `CoverLoader` | struct / `@MainActor @Observable final class` | Cover resolution per tile. |
| `BoxTile` | `View` | One box with hover, drag, drop, lighting, open. |
| `EmptyShelfCard` | `View` | "This shelf is bare." card. |
| private: `FrameBox`, `TilePressStyle`, `SpineSliverShape`, `TopSliverShape` | | Helpers. |

## `ShelfView`

State: `@Environment(AppModel.self) model`, `@State textures = TextureLibrary.shared`, `@State swipes = SwipeMonitor()`, `@FocusState focused`.

| Aspect | Behaviour |
|---|---|
| Body | `ZStack { CaseFrameView(); OpenBoxView() }` in coordinate space `"shelfSpace"` (box tiles report their frame in it; `OpenBoxView` converts via its own origin). Focusable with the focus ring disabled; minimum size `windowMinW x windowMinH` (820 x 700); `.ignoresSafeArea()` so content runs under the hidden title bar. |
| Focus | `focused = true` on appear and whenever `openedAppID` returns to `nil`. |
| Keys | `onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end])`: ignored while a box is open or when any modifier is held (so Cmd-arrows go to the menu). Left/right page by one; Home/End jump with `Theme.Motion.pageJump`. |
| Export | `.fileExporter(isPresented: $model.isExporting, document: model.exportFile ?? ShelfFile(data: Data()), contentType: .steamShelf, defaultFilename: model.document.title)`; on failure sets `model.fileAlert`; always clears `exportFile`. |
| Import | `.fileImporter(allowedContentTypes: [.steamShelf, .json])`; opens a security scope on the URL, reads the data, calls `model.stageImport`; failures set `fileAlert` ("Couldn't read that file."). |
| Alerts | "Replace this shelf?" (Replace is destructive, calls `confirmImport`) driven by `pendingImport != nil`; generic "Steam Shelf" alert for `fileAlert`. |
| Swipes | `.onAppear` (not in tests mode) starts `SwipeMonitor` for the window titled "Steam Shelf" (falling back to the key window), enabled only when no box is open, calling `model.go(to: pageIndex + step)`. `.onDisappear` stops it. |
| Startup | `.task` (not in tests mode): focus, `await textures.prepare()`, then `await model.onLaunch()`. |

## Case frame

| View | Detail |
|---|---|
| `CaseFrameView` | `VStack { CrownRail; HStack { StileView(.left); BayView; StileView(.right) }; BaseRail }` over one continuous `TiledFill(caseWood)` so frame members have no seams. Minimum width `stileW*2 + 100`. |
| `CrownRail` | Height `crownH` (64). Edge highlights, centred brass **nameplate** (280 x 34, shows `document.title`, two screws), and on the right a **page plate** ("PAGE n OF m" in small-caps Copperplate) plus three round brass knobs: Refresh (spins while `libraryState` is `.loading`, disabled then), Lights (bulb, toggles `lightsOn`), Settings (`openSettings()`). Left clearance of 84 pt for the traffic-light buttons. |
| `BaseRail` | Height `baseH` (44). A `TimelineView` (every 60 s) shows status text in Baskerville: transient message (brass-light), loading message, `warning sign + failure message`, or idle text: `DEMO SHELF . n OF m TITLES SHELVED`, `UPDATED <relative> . n OF m TITLES SHELVED` (`RelativeDateTimeFormatter`, abbreviated; "JUST NOW" under 60 s) or `NOT CONNECTED - OPEN SETTINGS (CMD-,)`. Right side: engraved "STEAM SHELF". |
| `StileView` | `side: HandleSide`, width `stileW` (84). Lit-from-left gradient, a mortise (54 x 160), and a `HandleView` whose label comes from `Pagination.leftHandleLabel`/`rightHandleLabel`; tap calls `model.handleTapped(side)`. The handle is a `.dropDestination(for: DraggedBox.self)` whose `isTargeted` callback calls `model.dragHover(over:active:)` (dwell page flip); the drop closure returns `false` (dropping on a handle does nothing). |

## Bay

`BayView` uses a `GeometryReader` to build `BayLayout(baySize:)` and passes `layout.scale` into the environment as `shelfScale`. `BayContent` stacks, bottom to top:

1. `TiledFill(backPanel)` and a vertical darkening gradient.
2. Per-row shadow under the crown/plank above (26 * scale tall, opacity 1, or 0.25 when lights are on).
3. Per-row `LightStrip` (opacity 0 or 1; the cross-fade is driven by `toggleLights()`'s `Theme.Motion.lights` animation).
4. Side shadows from the stiles (14 pt).
5. `PageContainerView` (clipped).
6. The four `PlankView`s in the *frame* layer (they do not slide with the page), `allowsHitTesting(false)`, drawn **in front of the boxes** so each box's base hides behind the shelf edge.
7. `EmptyShelfCard` when there are no shelved entries.

### `LightStrip`

`width`, `rowHeight`, `@Environment(\.shelfScale) s`. Three layers masked horizontally (35% at the ends, full between 18% and 82%): a warm **wash** (`lampWash` gradient, `.screen` blend, 0.9 of the row height, fading out by about 72%), a **halo** (`lampGlow`, `.plusLighter`, 26*s tall) and the **core line** (`lampCore`, 1.5*s tall with two shadows). Not hit-testable.

### `PlankView`

Wood texture, a multiply gradient, a warm top spill when lights are on, a lighter top surface (7*s tall), a dark front-edge line and bottom line; `.compositingGroup()` and a drop shadow (opacity 0.6 lit, 0.45 unlit).

## Paging

| View | Behaviour |
|---|---|
| `PageContainerView` | `ShelfPageView(pageIndex: model.pageIndex, layout:).id(model.pageIndex)` with `.transition(reduceMotion ? .opacity : .push(from: edge))`, where `edge` is `.trailing` for forward and `.leading` for backward (`model.slideDirection`). Changing the `id` makes SwiftUI treat it as a new view so the push runs. Respects Reduce Motion. |
| `ShelfPageView` | `pageIndex`, `layout`. Slices `shelvedEntries[range]` (empty if the range is out of date during a transition). For each entry: a contact-shadow `Ellipse` (blurred) then `BoxTile` at `layout.boxFrame(row: index/4, col: index%4)`. A `.dropDestination` on the whole page moves the dragged box to the *end* of the shelf (`moveEntry(_, before: nil)`). `.animation(nil, value: layout)` prevents window resizes from animating tile positions. |

## Cover loading

| Member | Behaviour |
|---|---|
| `ReadyCover` | `struct { image: CGImage, spine: Color }`. |
| `CoverLoader` | `@MainActor @Observable final class`; `State { loading, ready(CGImage, spine:) }`; `static var recent: [Int: ReadyCover]` (cap 48), shared with `OpenBoxView` so opening a box can start instantly. Computed `readyImage`, `spine`. |
| `func load(entry: ShelfEntry, model: AppModel) async` | Recent-cache hit returns immediately; otherwise `await Task.yield()`, cancellation checks, `Self.resolve`, `remember`, set state. |
| `static func resolve(entry:model:) async -> ReadyCover` | If the entry has art URLs and the model is not in demo: asks `model.images.cover(for:)`. `.portrait` gives the image with spine colour from `spineColor(from: averageColor(...))`. `.header` gives `ArtGenerator.headerCover` with `CoverPalette.bottom` as spine. Anything else (including no art) gives `placeholderCover` with `CoverPalette.bottom`. |
| `static func remember(_:appID:)` | Inserts, evicting an arbitrary key other than `appID` when at the cap. |

## `BoxTile`

`entry: ShelfEntry`; state `loader` (`CoverLoader`), `hovering`, `dropTargeted`, a non-observed `FrameBox` that records the tile's frame in `shelfSpace`; environment `shelfScale`.

| Aspect | Behaviour |
|---|---|
| Click | A `Button` styled with `TilePressStyle` (scale 0.98). Calls `model.open(entry.appID, from: frameBox.frame)`. Using a real Button gives keyboard/accessibility semantics and a trait of `.isButton`, label = title. |
| Frame tracking | `onGeometryChange(for: CGRect.self)` stores the frame in `frameBox` (read only at click time, so it never triggers view updates) and, if this tile is the opened one, updates `model.openedFromFrame` live so resizing while open still lands the box in its slot. |
| Opened state | While `model.openedAppID == entry.appID` the visual body is hidden and a faint dark slot placeholder shows (the flyer in `OpenBoxView` replaces it). |
| Drag | `.draggable(DraggedBox(appID:)) { dragPreview }`: a cover-sized preview using the loaded cover (or the placeholder). |
| Drop | `.dropDestination(for: DraggedBox.self)` calls `model.moveEntry(dragged.appID, before: entry.appID)`; `isTargeted` sets `dropTargeted`, which shows a 3-pt brass-light insertion mark just left of the box. |
| Hover | Lifts by 3*s, scales 1.03, glow stroke, larger shadow (`Theme.Motion.hover`). |
| Visual parts | `boxBody`: top sliver (`TopSliverShape`, spine colour mixed 15% black), spine sliver (`SpineSliverShape`, parallelogram with 0.375 width rise), cover (placeholder title text until the image arrives, then cross-fades with `Theme.Motion.artFade`), `gloss` (top-left highlights), `litOverlay` (warm top light when lights are on). |
| Loading | `.task(id: entry.appID) { await loader.load(entry:model:) }`. |

## `EmptyShelfCard`

A fixed 420 x 260 lined-paper index card, rotated -2 degrees, with a thumbtack. Text: "This shelf is bare." plus either "You own N games. Tick a few in Settings to put them on display." or "Add your Steam Web API key and SteamID in Settings, then tick the games worth displaying." Buttons: **Open Settings** and, when no library is loaded, **Try the Demo Shelf** (`model.startDemo()`).

## Concurrency and gotchas

- All views are main-actor. `CoverLoader.recent` is a static mutable dictionary; it is `@MainActor`-isolated as part of the class, so there is no data race.
- A tile that disappears mid-load (page change) cancels its `.task`; `load` checks `Task.isCancelled` after each suspension so a stale result is never written.
- Handles are real `Button`s so `NSApp.currentEvent.clickCount` works (double-click jumps) and accessibility exposes "Previous page"/"Next page".
- The page-turn push transition was not verified mid-flight visually ([Phase B notes](../decisions/OPEN_QUESTIONS.md#implementation-notes-phase-b)).

## See also

[Shelf rendering](../architecture/shelf-rendering.md), [Overview](../architecture/overview.md), [Design spec](../design/DESIGN.md).
