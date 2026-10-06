# ArtGenerator

Path: [`Sources/Images/ArtGenerator.swift`](../../Sources/Images/ArtGenerator.swift) (387 lines)

Everything the app draws procedurally, so it ships no image assets for the shelf: seeded wood and linen textures made with Core Graphics, helpers for average and spine colours, an `ImageRenderer` bridge to turn SwiftUI views into `CGImage`s, the placeholder and header-composite cover designs, and `TextureLibrary`, the main-actor holder of the generated textures. It also defines the project's one `@unchecked Sendable` type, `SendableImage`, and the deterministic `SplitMix64` generator.

## Depends on / used by

- Depends on: [Theme](Theme.md) (`Theme.Metrics`, `Theme.Palette`, `Theme.Fonts`), SwiftUI, CoreGraphics.
- Used by: [ShelfView](ShelfView.md) (`CoverLoader`, textures), [HandleView](HandleView.md), [OpenBoxView](OpenBoxView.md) (render back and spine), [BackOfBoxView](BackOfBoxView.md) (`SplitMix64`, `linen`), [KeeperNotesPanel](KeeperNotesPanel.md), [SettingsView](SettingsView.md) (`TextureLibrary.prepare`), [ImageCache](ImageCache.md) (`SendableImage`), [DemoData](DemoData.md) (`SplitMix64`), [BoxScene](BoxScene.md) (`SendableImage`).

## Types

### `SendableImage`

`struct SendableImage: @unchecked Sendable { let cgImage: CGImage }`. The single documented `@unchecked Sendable` exception: `CGImage` is immutable and thread-safe, so a wrapper lets decoded images cross actor boundaries (cache to UI, background texture generation to the main actor).

### `SplitMix64`

`struct SplitMix64: RandomNumberGenerator`; `init(seed: UInt64)`. `next()` is the standard SplitMix64 step. Helpers: `nextUnit() -> Double` in [0, 1), `double(in: ClosedRange<Double>)`, `int(in: ClosedRange<Int>)` (modulo; slight bias is irrelevant here). Used everywhere determinism matters: textures, demo data, barcodes.

### Colour and wood types

| Type | Definition |
|---|---|
| `RGB` | `typealias RGB = SIMD3<Double>` |
| `WoodGrain` | `enum { horizontal, vertical }`, `Sendable` |
| `WoodPalette` | `struct { base, dark, light: RGB }`, `Sendable`; `static func rgb(hex: UInt32) -> RGB`; presets `plank` (base 5C3A21), `caseWood` (3B2415), `back` (2E1B10) |

### `ArtGenerator` (enum, static functions)

| Signature | Isolation | Behaviour |
|---|---|---|
| `static func woodTexture(size: Int, seed: UInt64, grain: WoodGrain, palette: WoodPalette) -> CGImage` | nonisolated | Seeded, seamless-tiling wood on a `size x size` sRGB context. Steps, all scaled by `k = size/1024`: fill base; 7 soft tone bands (light or dark, alpha 0.04-0.10); 260 sine-wobble grain lines (80% dark) drawn at offsets -s, 0, +s for vertical seamlessness with integer frequencies for horizontal seamlessness; 2 knots (9 elliptical rings plus a dark centre); 30,000 pores. `.vertical` rotates the context 90 degrees about the centre first. |
| `static func linenTexture(size: Int, seed: UInt64) -> CGImage` | nonisolated | Backdrop-coloured fill, faint 2-px weave lines and 20,000 specks; used at 6% opacity on labels and panels. |
| `static func averageColor(of image: CGImage) -> (r: Double, g: Double, b: Double)` | nonisolated | Draws into a 1x1 context and un-premultiplies; returns (0.2,0.2,0.2) if empty. |
| `static func spineColor(from avg:) -> Color` | nonisolated | HSB of the average: hue kept, saturation x 0.8, brightness `v*0.45` clamped to 0.10...0.35 (a dark, muted version of the cover). |
| `@MainActor static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2) -> CGImage?` | main actor | `ImageRenderer` at 2x. Used for back label (600 x 900), spine (200 x 1200), placeholder covers. |
| `@MainActor static func placeholderCover(title:appID:) -> CGImage` | main actor | Renders `PlaceholderCoverView` at 600 x 900 @2x (1200 x 1800 px); falls back to a flat blue-grey image if rendering fails. |
| `@MainActor static func headerCover(title:appID:header:) -> CGImage` | main actor | Renders `HeaderCompositeCoverView` (the landscape store header pinned on a portrait cover); falls back to `placeholderCover`. |
| private `makeContext(width:height:)`, `cg(_:_:)`, `hsb(_:)`, `fallbackImage(width:height:)` | | `makeContext` calls `fatalError` if allocation fails (out of memory has no recovery). |

### Placeholder covers

| Type | Role |
|---|---|
| `CoverPalette` | `struct { top, bottom, accent: Color }`; `static let all` eight palettes; `static func forApp(_ appID: Int) -> CoverPalette` indexes `((appID % 8) + 8) % 8`. The `bottom` colour doubles as the spine colour for placeholder covers. |
| `Sunburst` (private `Shape`) | 12-ray sunburst behind the title. |
| `PlaceholderCoverView` | Gradient, sunburst at 12% accent, three accent rules, title in Baskerville Bold 64 (4 lines, scale to 0.4) and "A STEAM GAME" in Copperplate. |
| `HeaderCompositeCoverView` | Used when only the landscape header could be fetched: 540-pt header with a cream mat and shadow near the top, title below, "A STEAM GAME" footer. |

### `TextureLibrary`

`@MainActor @Observable final class TextureLibrary`; `static let shared`; private init.

| Member | Behaviour |
|---|---|
| `shelfWood`, `caseWood`, `backPanel`, `linen` | `Image?`, nil until prepared. Views use `TiledFill` with a flat-colour fallback until they appear. |
| `func prepare() async` | Idempotent (`shelfWood == nil` and an `isPreparing` guard). Generates four 1024/512-px textures on a detached `userInitiated` task (seeds 1 plank horizontal, 2 case vertical, 3 back vertical, 4 linen) and wraps each as `Image(decorative:scale: 2)`. DEBUG logs the duration. |

## Gotchas

- Texture seeds are fixed, so the wood looks identical on every machine and launch.
- `Image(decorative:scale: 2)` means 1024 px textures tile at 512 pt.
- `render` must run on the main actor; `OpenBoxView` therefore builds back/spine textures on the main actor while the box animates, at a cost of tens of milliseconds.
- Placeholder covers are 1200 x 1800 pixels each; a full page of 16 placeholders holds roughly 140 MB of `CGImage`s (accepted in Phase A, see [OPEN_QUESTIONS](../decisions/OPEN_QUESTIONS.md#implementation-notes-phase-b)).

## See also

[Shelf rendering](../architecture/shelf-rendering.md), [Open box](../architecture/open-box.md), [Design spec](../design/DESIGN.md) (section 3).
