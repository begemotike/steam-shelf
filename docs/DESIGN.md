# Steam Shelf — Visual & Interaction Design

Mood: a walnut bookcase in a dim den, lit by a warm lamp above and to the left of the viewer. Reference points: Delicious Library 1/2 (2005–08), iBooks wooden shelf (2010), iTunes 7 Cover Flow (2006). Rich, glossy, tactile, slightly over-the-top. No Liquid Glass, no SF Symbols in the shelf chrome (SF Symbols are fine inside Settings).

All sizes below are **design units (du)**. On screen, `pt = du × scale`, where `scale = min(availableWidth / 1100, availableHeight / 1000)` for the bookcase block (see §4). Colors are sRGB hex.

---

## 1. Palette (`Theme.Palette`)

| Token | Hex | Use |
|---|---|---|
| `walnutDark` | `#3B2415` | case wood base, grain dark tone |
| `walnut` | `#5C3A21` | shelf plank base |
| `walnutLight` | `#7A4E2D` | grain light tone, handle body |
| `walnutHighlight` | `#A87444` | 1-du top-edge highlight on planks and crown |
| `grainLine` | `#2A170C` | grain strokes |
| `backPanel` | `#2E1B10` | bay back panel base |
| `backPanelDark` | `#1C100A` | bay inner shadow end color |
| `mahogany` | `#6B2E1F` | accents: thumbtack, rule lines on label |
| `brass` | `#B8893B` | handle plates, nameplate, buttons |
| `brassLight` | `#F0D48A` | brass gradient highlight |
| `brassDark` | `#6E4E1C` | brass gradient shadow, plate bevel |
| `brassInk` | `#3A2A10` | engraved text on brass |
| `cream` | `#F3E9D2` | label paper, index card |
| `creamShade` | `#E2D3B0` | paper edge shading, dividers |
| `ink` | `#2B1D12` | label body text |
| `inkSoft` | `#6B5842` | secondary label text |
| `labelRed` | `#8C2F1E` | label double rules, "HOURS" numerals |
| `starGold` | `#D9A531` | filled stars |
| `starEmpty` | `#CDBB94` | empty stars |
| `achieveGreen` | `#5F7F3A` | achievements bar fill |
| `backdrop` | `#15110E` | window background base (linen) |
| `backdropEdge` | `#070504` | vignette edge |
| `hoverGlow` | `#FFE6A8` @ 25% | box hover rim light |
| `dimOverlay` | `#000000` @ 70% | open-box backdrop |

Wood palettes for the generator (`WoodPalette`, RGB 0…1 derived from hex):
- **plank**: base `walnut`, dark `grainLine`, light `walnutLight`
- **case**: base `walnutDark`, dark `#1E1109`, light `#5C3A21`
- **back**: base `backPanel`, dark `#140B06`, light `#452A18`

## 2. Light & shadow

- Single key light: **upper-left, in front of the case, ~45° elevation**. Every drop shadow falls **down and to the right**.
- Box drop shadow on back panel: `color black @ 55%`, `radius 8 du`, `x +3 du`, `y +6 du`.
- Box contact shadow on plank: ellipse `width = boxW × 0.9`, `height 8 du`, centered under the box, 2 du below its bottom edge, `black @ 45%`, blur 4 du.
- Under-plank shadow in each bay (top of bay, cast by plank/crown above): linear gradient `black @ 50% → 0` over 26 du.
- Bay side shadows (inner edges of stiles): linear gradient `black @ 35% → 0` over 14 du.
- Plank front face: vertical gradient `walnutLight (top) → walnutDark (bottom)` multiplied over the wood texture at 40% opacity (`.blendMode(.multiply)`), plus a 1-du top line `walnutHighlight @ 80%`, plus a 2-du bottom line `black @ 40%`.
- Plank drop shadow onto the bay below: `black @ 45%`, radius 6 du, y +4 du.
- Box gloss (shrink-wrap): overlay `LinearGradient(white @ 22% at topLeading → white @ 0 at 0.45 → white @ 6% at bottomTrailing)`, plus a 1-du inner stroke `white @ 18%` on the top and left edges only.

## 3. Procedural textures (`ArtGenerator`, generated once at launch)

All use `SplitMix64(seed:)` so output is deterministic. Generate at 1024×1024 px (linen 512×512), draw with `CGContext` (sRGB, premultipliedLast), wrap as `Image(decorative:scale: 2)` and use `.resizable(resizingMode: .tile)`.

**Wood (horizontal grain; vertical = same algorithm then rotate the context 90°):**
1. Fill `base`.
2. **Tone bands:** 7 horizontal bands at random y, height 60–200 px, filled with `light` or `dark` at alpha 0.04–0.10, edges softened with a vertical linear gradient.
3. **Grain lines:** 260 strokes. For each: `y0 = rand(0…1024)`, `amp = rand(2…14)`, `k1 = randInt(1…4)`, `k2 = randInt(5…9)`, phases `p1, p2 = rand(0…2π)`, width `rand(0.5…2.4)`, color `dark` alpha `rand(0.06…0.24)` (80% of strokes) or `light` alpha `rand(0.04…0.12)` (20%). Path: for `x` in `stride(0…1024, by: 8)`: `y = y0 + amp·sin(2π·k1·x/1024 + p1) + 0.35·amp·sin(2π·k2·x/1024 + p2)`. Integer `k` makes the texture **seamless horizontally**. Draw each stroke also at `y0 − 1024` and `y0 + 1024` for **vertical seamlessness**.
4. **Knots:** 2 knots at random positions (at least 100 px from edges): 9 concentric ellipses, rx 6→40 px, ry = rx × 0.45, stroke `dark` alpha 0.10, width 1.2; center filled `dark` alpha 0.35 rx 5.
5. **Pores:** 30,000 1×1 px dots, random positions, `dark` alpha 0.05 (70%) or `light` alpha 0.04 (30%).

**Linen (backdrop):** fill `backdrop`; 1-px horizontal lines every 2 px `white @ 2.5%`; 1-px vertical lines every 2 px `black @ 6%`; 20,000 noise dots `white @ 3%`. The window adds a radial vignette on top: `RadialGradient(clear at center → backdropEdge @ 85% at 0.75 × max(w,h))`.

## 4. Window & bookcase geometry (`Theme.Metrics`)

Window: default 1180 × 960 pt, min 820 × 700 pt, `.hiddenTitleBar` (traffic lights float over the header).

Vertical stack: `HeaderBar` (fixed 56 pt, not scaled) → bookcase block (fills rest, scaled, centered, 24 pt padding).

Bookcase block design size **1100 × 1000 du**:
```
┌──────────────────────── crown 40 du ─────────────────────────┐
│H │ stile 36 │  bay interior 700 du wide           │ stile 36 │H│
│A │          │  row 0  (height 222 du incl. plank)  │          │A│
│N │          │  row 1                               │          │N│
│D │          │  row 2                               │          │D│
│L │          │  row 3                               │          │L│
│E │          │                                      │          │E│
└──────────────────────── base 48 du ──────────────────────────┘
```
- Handles sit **outside** the stiles: each handle column is 80 du wide (handle body 46 du wide + margins). Case width = 36 + 700 + 36 = 772 du. Total = 80 + 772 + 80 = 932 du; remaining width is margin (centering). Design width reserved 1100 for breathing room.
- Crown: 40 du, `case` wood, vertical gradient overlay `walnutHighlight @ 30% → clear` on the top 8 du, a 2-du dark groove line 12 du from the bottom.
- Base: 48 du, `case` wood, a 6-du plinth step (darker by 20%) at the bottom.
- Rows: 4 × 222 du = 888 du. Each row = 22 du headroom + 180 du box + 20 du plank front face. Total case height = 40 + 888 + 48 = 976 du.
- **Box on shelf:** 120 × 180 du (2:3). Spine sliver 8 du (see §5). Columns: 4 boxes + 3 gaps of 36 du = 588 du, centered in the 700-du bay → 56 du side inset each side. Boxes sit with their bottom edge on the plank top (plank top = bottom of the 180-du slot).
- Back panel: fills the bay interior behind the rows, `back` wood (vertical grain), with the shadows from §2.
- Planks: 700 du wide, 20 du front face, drawn over the back panel.

## 5. Box on the shelf (`BoxTile`)

- Front: cover image, `aspectRatio(2/3, contentMode: .fill)`, clipped to `RoundedRectangle(cornerRadius: 2 du)`.
- **Spine sliver** (fakes the box depth under the key light from the left): an 8-du strip on the box's **left** edge, fill = spine color (§5.1), with `LinearGradient(white @ 12% → black @ 25%)` left→right, transformed with `.projectionEffect` / skew so its top edge rises 3 du toward the back (`CGAffineTransform(a: 1, b: -0.375, c: 0, d: 1, tx: 0, ty: 0)` applied to an 8-du-wide rect gives 3 du rise). Place it immediately left of the cover, overlapping by 0.
- **Top edge sliver:** 4 du tall strip above the cover, spine color darkened 15%, skewed to the right by 8 du (the box top seen from slightly above). Keep it subtle.
- Gloss overlay and drop/contact shadows per §2.
- Placeholder while loading: cream box (`creamShade`) with the title in Baskerville 13 du, `inkSoft`, centered, multi-line, and a gloss overlay. Cross-fade to the art over 0.25 s.
- **Hover:** scale 1.03, lifts 3 du up (`offset y −3`), drop shadow radius 12 du / y +9, rim light `.overlay(RoundedRectangle.stroke(hoverGlow, lineWidth: 1.5 du))`, cursor `NSCursor.pointingHand`. Animation `.spring(response: 0.22, dampingFraction: 0.8)`.
- **Press:** scale 0.98 for the press duration.
- **While opened:** the slot shows an empty "dust outline": `RoundedRectangle.stroke(black @ 25%, lineWidth 1 du)` with `black @ 12%` fill.
- Accessibility: `.accessibilityLabel(title)`, `.accessibilityAddTraits(.isButton)`.

### 5.1 Spine color
`ArtGenerator.averageColor` (draw cover into a 1×1 px RGBA context, read the pixel) → convert to HSB → `saturation × 0.8`, `brightness × 0.45` clamped to [0.10, 0.35] → `Color`. Placeholder covers use their palette's dark color.

## 6. Handles (`HandleView`)

Anatomy (design units, centered vertically on the case, 20 du outside the stile):
- **Body:** vertical capsule 46 × 150 du, `walnutLight` filled with `plank` wood texture, overlay `LinearGradient` left→right `white @ 18% → clear @ 0.4 → black @ 35%` for roundness (mirror for the right-hand handle so the highlight is always on the light's side — left side lit on both). Drop shadow `black @ 55%`, radius 6 du, x +3, y +5.
- **Mounting posts:** two brass discs 12 du Ø at top and bottom (inset 16 du from the capsule ends), `RadialGradient(brassLight → brass → brassDark)`, 1-du `brassDark` stroke, with a 5-du slot line (screw) at a jaunty −20°.
- **Number plate:** brass rounded rect 36 × 30 du, corner radius 4 du, centered on the body. Fill `LinearGradient(brassLight top → brass 0.45 → brassDark bottom)`, 1-du inner bevel `white @ 45%` top-left and `black @ 35%` bottom-right.
- **Engraving:** page number in **Copperplate Bold 18 du**, color `brassInk`, with an engraved look = the same text 1 du lower in `white @ 40%` underneath. Above the plate, an engraved chevron `‹` / `›` (Copperplate 16 du) directly on the wood in `black @ 45%` with a `white @ 15%` 1-du-lower copy.
- **Hover:** plate brightness +8% (`.brightness(0.08)`), the whole handle slides 2 du outward, cursor `pointingHand`, tooltip via `.help("Page 3 — double-click for last page")` / `.help("Page 1 — double-click for first page")`.
- **Pressed:** scale 0.97, drop shadow radius 3 du y +2.
- **Disabled** (no previous/next page): opacity 0.35, plate blank (no number), no hover, `.allowsHitTesting(false)`.
- Labels: left handle shows `pagination.leftHandleLabel` (the 1-based previous page), right shows `rightHandleLabel` (the 1-based next page).

### 6.1 Page slide
- Single click: `withAnimation(.spring(response: 0.55, dampingFraction: 0.86))` changing `pageIndex`; `ShelfPageView` is keyed `.id(pageIndex)` with `.transition(.push(from: direction == .forward ? .trailing : .leading))`. Only the boxes/rows slide; the case frame, back panel, planks and handles stay put (the page view is clipped to the bay interior).
- Double-click jump: same transition but `.spring(response: 0.42, dampingFraction: 0.9)` (a quick whoosh), direction = toward the destination.
- Keyboard: ← / → (when no box open) and ⌘← / ⌘→ menu items; Home/End jump first/last.
- Header shows "Page 2 of 5" in cream Baskerville 13 pt small caps.

## 7. Opened box

### 7.1 Phase timeline (`OpenPhase`)
| Phase | Duration | What happens |
|---|---|---|
| `lifting` | 0.16 s ease-out | 2D copy of the tile (the "flyer", same image + shadow) is placed at the tile's frame in shelfSpace, scales 1.0 → 1.08, shadow radius 8 → 18 du. The real tile shows the dust outline. |
| `flying` | 0.45 s `.spring(response: 0.45, dampingFraction: 0.85)` | Flyer moves/scales to the **target frame**: centered in the stage, height = `0.676 × stageSide`, width = height × 2/3. `dimOverlay` fades 0 → 0.70. |
| crossfade | 0.15 s | RealityView (already built during `flying`) fades 0 → 1; flyer fades 1 → 0. |
| `presented` | idle | Idle bob: `y = 0.006 m × sin(2π t / 3.2 s)`, yaw drift `±2.5° × sin(2π t / 7 s)` — both only while not dragging and |velocity| < 0.05. Toolbar fades in (0.2 s). |
| `returning` | 0.25 s spring back to yaw 0 / pitch 0 → crossfade to flyer 0.12 s → flyer flies back 0.38 s spring → drop 0.12 s (scale 1.08 → 1.0) | `dimOverlay` fades to 0 during the flight. `openedAppID = nil` at the end. |

`stageSide = min(overlayWidth − 360 pt (editor room), overlayHeight − 120 pt)`, centered horizontally in the space left of the editor panel when the panel is open, otherwise centered in the window. The 0.676 factor = front face (0.30 m) at camera distance 0.85 − 0.022 m with vertical FOV 30° (`0.30 / (2 × 0.828 × tan 15°)`). The implementer should eyeball-check that the flyer and the 3D front match at crossfade; if not, adjust the constant in `Theme.Metrics.frontFaceFill` only.

### 7.2 Interaction
- **Drag anywhere in the stage** rotates: `yaw += Δx × 0.012 rad/pt`, `pitch += Δy × 0.008 rad/pt`, pitch clamped to ±0.45 rad (±26°). Yaw unbounded.
- **Inertia:** on release, `yawVelocity = velocity.width × 0.012` rad/s (and pitch likewise ×0.008). Each frame: `angle += v·dt`, `v *= pow(0.04, dt)` (loses 96% per second). Stop when |v| < 0.05.
- **Pitch return:** when not dragging, pitch springs to 0 with `pitch += (0 − pitch) × min(1, dt × 4)`.
- **Flip** (toolbar button or Space): sets `targetYaw` to the nearest multiple of 2π + π (or back to front); spring `yaw += (target − yaw) × min(1, dt × 8)` until within 0.002 rad.
- **Close:** Escape, the ✕ button, or a click on the dim backdrop outside the stage.
- ← / → while open: rotate by ±π/2 via `targetYaw`.

### 7.3 3D box
- Dimensions 0.20 × 0.30 × 0.044 m (depth = 22% of width — a chunky collector's-edition box, enough spine for the title).
- Front: cover image (portrait art, header composite, or placeholder). `PhysicallyBasedMaterial`, roughness 0.35, metallic 0 (glossy shrink-wrap).
- Back: `BackOfBoxView` rendered at 600×900 pt @2x. Roughness 0.6 (matte paper label).
- Left/right: `SpineView` rendered 200×1200 pt @2x (aspect ≈ 0.044/0.30 ≈ 1:6.8 — the texture 1:6 is stretched slightly, acceptable). Roughness 0.5.
- Top/bottom: flat spine color, roughness 0.7.
- Lights: key `DirectionalLight` 2800 lx from (−0.5, 0.7, 1.0); fill 900 lx from (0.8, −0.1, 0.6). If covers look washed out or too dark, tune only these two numbers.

### 7.4 Toolbar (bottom-center of the stage, 24 pt below the box)
Three brass pill buttons (height 30 pt, horizontal padding 14 pt, Baskerville SemiBold 13 pt, `brassInk` text, brass gradient fill, 1-pt `brassDark` stroke, shadow `black @ 50%` r 4 y 2): **Flip** · **Edit Label** · **Close**. Hover: brightness +0.06. Pressed: gradient inverted. When `source.isEditable == false`, hide Edit Label.

### 7.5 Spine (`SpineView`, 200 × 1200 pt)
Spine color fill with a vertical `LinearGradient(white @ 10% → clear → black @ 20%)` left→right. Title rotated 90° clockwise (reads top-to-bottom, the US convention), Baskerville Bold 64 pt, `cream`, `lineLimit(1)`, `minimumScaleFactor(0.4)`, centered, 60 pt margins top/bottom. At the bottom: a 120-pt tall cream badge with "STEAM SHELF" in Copperplate 22 pt `ink`, rotated likewise. 2-pt `black @ 25%` border.

## 8. Back of box (`BackOfBoxView`, 600 × 900 pt)

Aesthetic: a pasted-on vintage paper label (1950s cereal box meets a record sleeve), on a dark base the color of the spine.

Structure (top to bottom; label inset 28 pt from the box edges, so label = 544 × 844):
1. **Base:** spine color fill (visible as a 28-pt border) with the gloss overlay.
2. **Label paper:** `cream` rounded rect r 6, inner shadow `black @ 18%` r 3, subtle paper grain = `linen` texture at 6% multiply. Double rule inside, inset 12 pt: outer 2 pt `labelRed`, gap 3 pt, inner 0.75 pt `labelRed`.
3. **Title block** (inside rules, 24 pt padding): title in **Baskerville Bold 40 pt** `ink`, max 2 lines, `minimumScaleFactor(0.5)`, centered. Under it the `tagline` (from `BackOfBoxContent`) in Baskerville Italic 18 pt `inkSoft`, centered. Then a flourish divider: 1-pt `labelRed` line with a centered ❦ (Baskerville 18 pt).
4. **Rating row:** "YOUR VERDICT" Copperplate 14 pt `inkSoft` letter-spaced 2, then 5 stars (`StarRow`, `Image(systemName: "star.fill")` — SF Symbols render correctly through ImageRenderer) at 30 pt: filled `starGold` with 1-pt `brassDark` stroke, empty `starEmpty`. Unrated: stars all empty and "Not yet rated" Baskerville Italic 14 pt.
5. **Stats grid** (2 × 2, each cell = small caps caption Copperplate 13 pt `inkSoft` + value Baskerville SemiBold 24 pt `ink`):
   - PURCHASED → `purchaseDate` formatted `.dateTime.month(.abbreviated).day().year()`, or "—" with caption note "(add it in Edit Label)" in 11 pt italic.
   - HOURS PLAYED → `playtimeMinutes / 60` with one decimal if < 10 h, else integer, followed by " hrs"; the numerals in `labelRed`.
   - LAST PLAYED → date or "Never" (a badge of shame).
   - ON SHELF SINCE → `firstSeenAt`.
6. **Achievements bar:** caption "ACHIEVEMENTS" + right-aligned "23 / 50". Bar 480 × 16 pt, capsule, track `creamShade` with inner shadow, fill `achieveGreen` gradient (lighter top), width = earned/total. States: `.none` → "This game keeps no trophies." italic; `.privateProfile` → "Achievements are private on Steam." italic; `.unknown` → "Checking the trophy case…" italic.
7. **Blurb box:** "FROM THE SHELF-KEEPER" Copperplate 13 pt `labelRed`, then `blurb` in Baskerville 18 pt `ink`, line spacing 3, max 5 lines, `minimumScaleFactor(0.7)`. 
8. **Note card:** a slightly rotated (−1.2°) lined index card 460 × 170 pt pinned with a `mahogany` thumbtack (a 14-pt circle with radial highlight). Lines every 26 pt in `#9CB8D8 @ 50%` with a single `#D98080` margin line. Note text in **Noteworthy 20 pt** `ink` (Noteworthy ships with macOS), max 6 lines, truncated. Empty note → "Scribble a note in Edit Label…" in Noteworthy `inkSoft @ 60%`.
9. **Footer:** barcode-ish stripe (render 40 random-width bars from the appID seed, 36 pt tall, `ink`) at bottom-left, "APP #620" Copperplate 12 pt beneath; bottom-right: "A STEAM SHELF EXHIBIT · <OWNER NAME>" Copperplate 11 pt `inkSoft`.

### 8.1 Label editor panel (`LabelEditorPanel`, 2D, interactive)
- Slides in from the right edge (`.move(edge: .trailing)` + opacity, `.spring(response: 0.4, dampingFraction: 0.85)`), 340 pt wide, full overlay height minus 40 pt, 20 pt from the right edge, corner radius 10.
- Styled as a cream paper sheet on a clipboard: `cream` fill, `linen` texture at 5%, a brass clip at top center (60 × 22 pt brass gradient rounded rect with two rivets). Shadow `black @ 60%` r 16 y 8.
- Opening the panel sets `targetYaw` to show the back.
- Contents (24 pt padding, 18 pt spacing, Baskerville for captions, system font for inputs):
  1. Title (Baskerville Bold 20).
  2. "Your Verdict" → `StarRatingControl` (5 stars 26 pt, click to set, click the same star again to clear, hover preview).
  3. "Purchased" → `DatePicker(.field style, displayedComponents: .date)` bound to an optional (show a "Set date" button when nil and a small "Clear" button when set).
  4. "Note" → `TextEditor` 160 pt tall with a cream background, `ink` text, Noteworthy 16 pt, counter "123 / 600".
  5. "Refresh from Steam" small bordered button + "Updated 5 min ago".
  6. "Done" brass pill (closes panel).
- Every change → `AppModel.update` → back texture re-render debounced 150 ms, persist debounced 500 ms.

## 9. Settings window (`SettingsView`, 640 × 760 pt)

Standard macOS look (this is the "control room", not the den) with two light touches of theme: a 64-pt tall header strip with `case` wood texture and a brass nameplate "Steam Shelf Settings" (Copperplate 16 pt), and brass-tinted accent (`.tint(Theme.Palette.brass)`).

**Section 1 — Steam Account** (`Form` `.grouped` style):
- "Web API Key" `SecureField` + "Save" button; when saved show "••••••••  Saved in Keychain" + "Forget" button. Link: "Get a key at steamcommunity.com/dev/apikey" (`Link`).
- "SteamID or profile URL" `TextField` (placeholder "76561198… or https://steamcommunity.com/id/yourname").
- "Connect" button (`.borderedProminent`), disabled while loading or when inputs invalid (`SteamIDInput.parse == nil`).
- Status row: loading → `ProgressView().controlSize(.small)` + message; success → avatar 28 pt circle (`AsyncImage` is fine here) + persona name + "312 games · refreshed 5 min ago"; failure → `labelRed` text from the copy table below + a "Help" disclosure explaining the privacy setting.

**Section 2 — Games on Your Shelf**:
- Toolbar row: search `TextField` with magnifier, `Picker` segmented [All | Played | On Shelf], sort `Menu` [Name | Hours Played | Last Played].
- `List` of `GameRow`: `Toggle` (`.checkbox` style) · 24 × 36 pt cover thumbnail (from ImageCache; placeholder is a cream rect) · title (13 pt) · secondary line "123.4 hrs · last played Mar 3, 2025" (11 pt secondary).
- Footer: "37 on shelf · 312 owned" · "Select None" · "Select All Shown" (acts on the filtered list; confirm via alert if > 200).
- "Refresh Library" button + "Refresh Achievements" button at the bottom.
- In demo mode: a cream banner at top "Demo shelf — 40 imaginary games. Connect a Steam account to use your own." with "Leave Demo" button (switches back to local source).

### 9.1 Error copy table (`SteamError.userMessage`)
| Error | Message |
|---|---|
| missingKey | "Add your Steam Web API key first." |
| invalidKey | "Steam rejected that API key. Double-check it at steamcommunity.com/dev/apikey." |
| badSteamIDInput | "That doesn't look like a SteamID64 or a steamcommunity.com profile link." |
| vanityNotFound | "No Steam profile uses that custom URL." |
| profileNotFound | "Steam doesn't know that SteamID." |
| gameDetailsPrivate | "Your game list is private. In Steam: Profile → Edit Profile → Privacy Settings → set Game details to Public." |
| privateProfile | "Achievements are private for this profile." |
| noStats | "This game has no achievements." |
| rateLimited | "Steam asked us to slow down. Try again in a few minutes." |
| http(n) | "Steam returned an error (HTTP n)." |
| network(msg) | "Couldn't reach Steam: msg" |
| decoding / steam(msg) | "Steam sent something unexpected. (msg)" |

## 10. Header bar (`HeaderBar`, 56 pt)

`case` wood texture with a bottom 2-pt `black @ 50%` line and a 1-pt `walnutHighlight @ 40%` line above it. Leading 80 pt left clear for traffic lights. Center: brass nameplate (rounded rect 280 × 34, brass gradient, bevel as §6) with `document.title` engraved in Copperplate Bold 16 pt. Trailing: "Page 2 of 5" (cream Baskerville 13 pt small caps), then two 30-pt round brass buttons with engraved SF Symbols (`arrow.clockwise`, `gearshape.fill`) in `brassInk`. Gear → `@Environment(\.openSettings)`. Refresh → `refreshLibrary()` (spins while loading).

## 11. Empty state (`EmptyShelfCard`)

Show the full bookcase (empty bays look great on their own) and pin a cream index card to the back panel of rows 1–2, centered: 420 × 260 du, rotated −2°, `mahogany` thumbtack top center, shadow `black @ 55%` r 10 y 6. Lined like the note card.
- Heading (Baskerville Bold 26): "This shelf is bare."
- Body (Noteworthy 17): "Add your Steam Web API key and SteamID in Settings, then tick the games worth displaying."
- Buttons (brass pills): **Open Settings** · **Try the Demo Shelf**.
Variant when connected but nothing ticked: body "You own 312 games. Tick a few in Settings to put them on display." with only **Open Settings**.

## 12. Fonts (`Theme.Fonts`) — all ship with macOS
| Role | Font |
|---|---|
| Titles / label body | `Font.custom("Baskerville", size:)`, `"Baskerville-Bold"`, `"Baskerville-SemiBold"`, `"Baskerville-Italic"` |
| Engraving / captions | `"Copperplate"`, `"Copperplate-Bold"` |
| Handwriting | `"Noteworthy-Light"`, `"Noteworthy-Bold"` |
Scale shelf-space fonts by `scale`; texture-space fonts (back/spine) are fixed pt at the 600×900 canvas.

## 13. Motion constants (`Theme.Motion`)
`hover = .spring(response: 0.22, dampingFraction: 0.8)` · `pageSlide = .spring(response: 0.55, dampingFraction: 0.86)` · `pageJump = .spring(response: 0.42, dampingFraction: 0.9)` · `lift = .easeOut(duration: 0.16)` · `fly = .spring(response: 0.45, dampingFraction: 0.85)` · `crossfade = .easeInOut(duration: 0.15)` · `panel = .spring(response: 0.4, dampingFraction: 0.85)` · `artFade = .easeIn(duration: 0.25)`.
Respect `@Environment(\.accessibilityReduceMotion)`: when true, page changes use `.opacity` transition and open/close uses crossfade only (no flight, no bob).
