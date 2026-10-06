# HandleView

Path: [`Sources/Views/HandleView.swift`](../../Sources/Views/HandleView.swift) (108 lines)

The wooden drawer-pull on each stile that turns pages: a capsule of shelf-wood texture with two brass posts, an engraved chevron and a brass plate showing the destination page number. It is a real `Button`, so single and double clicks, hover and accessibility all behave natively. When there is no page in that direction the label is `nil`, and the handle dims and ignores hits.

## Depends on / used by

- Depends on: [Pagination](Pagination.md) (`HandleSide`), [Theme](Theme.md) (palette, fonts, `BrassPlate`, `EngravedText`, `TiledFill`, `shelfScale`), [ArtGenerator](ArtGenerator.md) (`TextureLibrary.shelfWood`).
- Used by: [ShelfView](ShelfView.md) (`StileView`).

## Types

### `HandleView`

`struct HandleView: View` with `side: HandleSide`, `label: Int?` (1-based destination page), `action: () -> Void`; state `hovering`.

| Aspect | Behaviour |
|---|---|
| Button | `Button(action:)` with label `HandleArt(... pressed: false)` and `HandlePressStyle`, which re-renders the art with `pressed: configuration.isPressed`. |
| Enabled | `label != nil`. Disabled handles use `.allowsHitTesting(false)` and no pointer style. |
| Help / a11y | Tooltip "Page N - double-click for first page" (left) or "... last page" (right); empty when disabled. Accessibility label "Previous page" / "Next page". |

### `HandleArt` (private)

Draws at `handleBodyW x handleBodyH` (46 x 150) times `shelfScale`: textured capsule with highlight/shade gradient and shadow (smaller when pressed), two brass screw posts at +-(h/2 - 22*s), engraved chevron (`\u{2039}` or `\u{203A}`) at y = -34*s, number plate (36 x 30) at y = 6*s. Hover nudges the handle 2*s outward and brightens the plate; pressed scales to 0.97; disabled opacity 0.35.

### `HandlePressStyle` (private)

`ButtonStyle` that delegates to `HandleArt` so pressed state can alter the shadow and scale.

## Gotchas

- The click count is read in `AppModel.handleTapped` from `NSApp.currentEvent`, not from this view; the view only calls `action`.
- The `StileView` that hosts the handle attaches `.dropDestination` so dragging a box over a handle dwell-flips pages ([Shelf rendering](../architecture/shelf-rendering.md)).

## See also

[Shelf rendering](../architecture/shelf-rendering.md).
