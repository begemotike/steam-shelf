# BackOfBoxView

Path: [`Sources/BackOfBox/BackOfBoxView.swift`](../../Sources/BackOfBox/BackOfBoxView.swift) (433 lines)

All the views that show a game's personal data: the printed paper label on the back of the box (`BackOfBoxView`, a pure display view that is rendered to a 600 x 900 texture by `ImageRenderer`, not shown on screen directly), the spine texture (`SpineView`), the star controls and the interactive 2D editing panel (`LabelEditorPanel`) that slides in beside the open box.

## Depends on / used by

- Depends on: [ShelfDocument](ShelfDocument.md) (`ShelfEntry`, `CachedSteamStats`), [Theme](Theme.md) (palette, fonts, `LinedPaper`, `Thumbtack`, `BrassPillButtonStyle`, `Theme.gloss`, `Theme.brassGradient`), [ArtGenerator](ArtGenerator.md) (`SplitMix64`, `TextureLibrary.shared.linen`), [AppModel](AppModel.md) (editor).
- Used by: [OpenBoxView](OpenBoxView.md) (`renderBack` creates `BackOfBoxView`, `buildTextures` creates `SpineView`, hosts `LabelEditorPanel`).

## Types

### `StarRow`

`struct StarRow: View`, `rating: Int?`, `size: CGFloat = 30`, `spacing: CGFloat = 6`. Non-interactive; filled stars are gold with a brass outline, empty ones `starEmpty`. Used on the printed label.

### `StarRatingControl`

`struct StarRatingControl: View`, `@Binding var rating: Int?`, `size = 26`. Hover previews, click sets, clicking the already-set star clears (sets `nil`). Each star has an accessibility label ("1 star", "2 stars"...) and the button trait.

### `BackOfBoxView`

`struct BackOfBoxView: View` with `entry: ShelfEntry`, `ownerName: String`, `spineColor: Color`. Canvas `Theme.Metrics.coverW x coverH` (600 x 900) with a 544 x 844 cream label (rounded rect, optional 6% linen multiply, double red rule). Sections top to bottom:

| Section | Content |
|---|---|
| `titleBlock` | Title (Baskerville Bold 40, 2 lines, scale to 0.5), optional italic tagline from `entry.blurb?.tagline`, fleuron rule. |
| `ratingRow` | "YOUR VERDICT", `StarRow`, "Not yet rated" when `nil`. |
| `statsGrid` | PURCHASED (date or an em dash with "(add it in Edit Label)"), HOURS PLAYED (`hoursText`: one decimal under 10 h, else rounded), LAST PLAYED (date or "Never"), ON SHELF SINCE (`firstSeenAt`). Dates use `.dateTime.month(.abbreviated).day().year()`. |
| `achievements` | By `AchievementsState`: `.ok` shows "earned / total" and a 480-pt green capsule bar (minimum 16 pt); `.none` "This game keeps no trophies."; `.privateProfile` "Achievements are private on Steam."; `.unknown` "Checking the trophy case...". Fixed 46-pt height. |
| `blurbBox` | "FROM THE SHELF-KEEPER" and `entry.blurb?.blurb` (or "The shelf-keeper is thinking it over..."), 5 lines max, scale 0.7. |
| `noteCard` | `LinedPaper` card with the note in Noteworthy 20 (6 lines, tail truncation) or a placeholder, thumbtack, rotated -1.2 degrees. |
| `footer` | `Barcode` (40 bars with widths from `SplitMix64` seeded by appID), "APP #<id>", "A STEAM SHELF EXHIBIT . <OWNER>". |

Because it is rendered through `ImageRenderer` it must not depend on interaction; it reads `TextureLibrary.shared.linen`, so the texture must be prepared first (the first back render after launch may lack the linen overlay if textures are not ready).

### `Barcode` (private)

40 alternating bars, widths 1-4 times 0.9 pt from a seeded RNG; decorative only.

### `SpineView`

`struct SpineView: View` with `title: String`, `color: Color`. 200 x 1200 canvas: spine colour, a horizontal highlight/shade gradient, the title rotated 90 degrees reading top to bottom (Baskerville Bold 64, one line, scale to 0.4, within a 900-pt run starting 60 pt from the top), a cream "STEAM SHELF" badge near the bottom and a 2-pt dark border.

### `LabelEditorPanel`

`struct LabelEditorPanel: View`, `let appID: Int`, `@Environment(AppModel.self)`. A cream clipboard (forced light colour scheme) with brass clip:

| Control | Action |
|---|---|
| `StarRatingControl` | `model.update(appID) { $0.rating = new }` |
| Purchased | `DatePicker` (field style) bound through `model.update`, "Clear", or "Set date" (sets today) |
| Note | `TextEditor`, `String(new.prefix(600))` enforced on every keystroke, live "n / 600" counter |
| Refresh from Steam | `Task { await model.refreshStats(for: appID, force: true) }`, disabled in demo/tests; caption "Updated <relative>" or "Not refreshed yet" |
| Done | `model.isEditingLabel = false` with `Theme.Motion.panel` |

Private helpers: `field(_:content:)` (caption plus content), `purchaseField(_:)`, `noteField(_:)`, `updatedText(_:)`.

## Gotchas

- Every edit changes `document`, which `OpenBoxView.onChange(of: entry)` observes to schedule a debounced (150 ms) back re-render.
- `LabelEditorPanel` reads the entry fresh from `model.document` on each body evaluation, so it always reflects the stored value even while the printed label is a frame behind.
- Both texture views assume macOS fonts Baskerville, Copperplate and Noteworthy are present (all ship with macOS).

## See also

[Open box](../architecture/open-box.md), [Shelf rendering](../architecture/shelf-rendering.md) (spine colours), [Design spec](../design/DESIGN.md) (section 8).
