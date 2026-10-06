# Theme

Path: [`Sources/Views/Theme.swift`](../../Sources/Views/Theme.swift) (243 lines)

The app's design tokens and a handful of shared chrome views. `Theme` is a namespace of static values: colour palette, font helpers, metrics (every size in points, in "design units" where 1 unit equals 1 pt at scale 1) and animation constants. Below it are the `shelfScale` environment key and reusable pieces (brass plate, engraved text, brass pill button, lined paper, thumbtack, tiled texture fill). [`docs/design/DESIGN.md`](../design/DESIGN.md) is the visual spec these values implement.

## Depends on / used by

- Depends on: SwiftUI.
- Used by: nearly every view and by [ArtGenerator](ArtGenerator.md) (`Theme.Palette.backdropHex`, `Theme.Metrics.cover*`), [BayLayout](BayLayout.md) (`Theme.Metrics.boxH`), [SteamShelfApp](SteamShelfApp.md) (window size), [AppModel](AppModel.md) (`Theme.Motion`).

## `Color` extension

`init(hex: UInt32, alpha: Double = 1)`: sRGB from `0xRRGGBB`.

## `Theme.Palette` (all `static let Color` unless noted)

| Group | Names |
|---|---|
| Walnut | `walnutDark` 3B2415, `walnut` 5C3A21, `walnutLight` 7A4E2D, `walnutHighlight` A87444, `grainLine` 2A170C |
| Back panel | `backPanel` 2E1B10, `backPanelDark` 1C100A |
| Accents | `mahogany` 6B2E1F, `brass` B8893B, `brassLight` F0D48A, `brassDark` 6E4E1C, `brassInk` 3A2A10 |
| Paper | `cream` F3E9D2, `creamShade` E2D3B0, `ink` 2B1D12, `inkSoft` 6B5842, `labelRed` 8C2F1E |
| Stars and progress | `starGold` D9A531, `starEmpty` CDBB94, `achieveGreen` 5F7F3A |
| Backdrop and overlays | `backdrop` 15110E, `backdropEdge` 070504, `hoverGlow` FFE6A8 at 25%, `dimOverlay` black at 70%, `stageSpotlight` 2A1D14 |
| Shelf lights | `lampCore` FFF1D6, `lampGlow` FFC46B, `lampWash` FFB456 (about 2700 K) |
| Raw hex for generators | `walnutHex`, `walnutDarkHex`, `walnutLightHex`, `grainLineHex`, `backPanelHex`, `backdropHex` (`UInt32`) |

## `Theme.Fonts`

Functions returning `Font.custom` for macOS system fonts: `baskerville`, `baskervilleBold`, `baskervilleSemiBold`, `baskervilleItalic`, `copperplate`, `copperplateBold`, `noteworthy` (Noteworthy-Light), `noteworthyBold`. All ship with macOS, so no font files are bundled.

## `Theme.Metrics`

| Group | Values |
|---|---|
| Window | default 1180 x 960; minimum 820 x 700 |
| Case frame | `crownH` 64, `baseH` 44, `stileW` 84, `plinthH` 6, `trafficLightClearance` 84 |
| Box design units | `boxW` 120, `boxH` 180, `spineSliverW` 8, `topSliverH` 4 |
| Handles | body 46 x 150, mortise 54 x 160 |
| Open box | `frontFaceFill` 0.628 (measured fraction of the square stage side the rendered front face fills), `editorPanelW` 340, `notesPanelW` 380 |
| Textures | `coverW/H` 600 x 900, `spineW/H` 200 x 1200, `woodTextureSize` 1024, `linenTextureSize` 512 |

## `Theme.Motion` (`Animation`)

`hover` spring 0.22/0.8, `pageSlide` spring 0.55/0.86, `pageJump` spring 0.42/0.9, `lift` easeOut 0.16, `fly` spring 0.45/0.85, `crossfade` easeInOut 0.15, `panel` spring 0.4/0.85, `artFade` easeIn 0.25, `lights` easeInOut 0.5.

## Environment and shared views

| Item | Role |
|---|---|
| `EnvironmentValues.shelfScale: CGFloat` | Points per design unit inside the bay (`BayLayout.scale`); default 1. Set by `BayView`, read by planks, handles, tiles and light strips so everything scales with the window. |
| `Theme.brassGradient`, `Theme.gloss` | Shared `LinearGradient`s. |
| `TiledFill(image: Image?, fallback: Color)` | Tiles the texture, or shows a flat colour until `TextureLibrary` has generated it. |
| `BrassPlate(cornerRadius:bevel:)` | Brass rounded rectangle with bevel strokes (nameplate, page plate, handle plates). |
| `EngravedText(text:font:color:highlight:offset:)` | Same text offset 1 unit lower in white underneath, giving an engraved look. |
| `BrassPillButtonStyle(height: 30)` | Capsule brass button with press inversion, hover brightening, shadow and a link pointer; used by the open-box toolbar, editors and empty state. |
| `LinedPaper(spacing:marginX:firstLine:)` | Cream paper with ruled blue lines and a red margin line (empty card, note card). |
| `Thumbtack` | 14-pt mahogany radial-gradient pin. |

## Gotchas

- `frontFaceFill = 0.628` is an *empirical* constant: the perspective formula predicts 0.676, but with the camera at z = 0.85 and a 30 degree field of view the front face measured 0.628 of the stage. It must stay in sync with `BoxStageView` camera values in [BoxScene](BoxScene.md) or the flyer will not line up with the 3D front at the cross-fade.
- Fonts are looked up by PostScript name; if a name is missing SwiftUI silently falls back to the system font.

## See also

[Shelf rendering](../architecture/shelf-rendering.md), [Open box](../architecture/open-box.md), [Design spec](../design/DESIGN.md).
