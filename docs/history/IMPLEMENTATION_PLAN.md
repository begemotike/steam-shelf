# Steam Shelf — Implementation Plan

Build strictly from ARCHITECTURE.md (types, files, config) and DESIGN.md (every visual value). RESEARCH.md explains why. If something is ambiguous, pick the simplest option that satisfies the acceptance criteria and add a line to OPEN_QUESTIONS.md — do not stop to ask.

**Global rules**
- Run `make test` after every package; it must pass before moving on. At the end of Phase A and Phase B, run `make` (test + build + path).
- Zero warnings is the goal; zero errors is mandatory. Never silence concurrency diagnostics with `@preconcurrency`, `nonisolated(unsafe)` or `@unchecked Sendable` — the single allowed exception is `SendableImage`.
- No third-party packages. No asset catalogs, no bundled images/fonts.
- Keep file list exactly as ARCHITECTURE §1.
- Never print or log the API key.

---

## Phase A — foundation (must build and pass tests; app runs and shows a plain grid)

### A1. Scaffold
Files: `project.yml`, `Makefile`, `Sources/App/SteamShelfApp.swift` (stub window with `Text("Steam Shelf")`), `Tests/ShelfDocumentTests.swift` (one trivial test), `.gitignore` (`build/`, `*.xcodeproj`, `.DS_Store`). Run `git init`.
Acceptance: `make` succeeds from a clean checkout, prints `Built app: /Users/bege/Develop/steam-shelf/build/Build/Products/Debug/SteamShelf.app`; `codesign -d --entitlements - <app>` shows sandbox + network.client.
Gotchas:
- Makefile recipes need real TAB characters.
- XcodeGen writes `Resources/Info.plist` and the entitlements file from `project.yml`; do not hand-edit them afterwards (they are regenerated).
- Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) + hardened runtime breaks test-bundle injection; hardened runtime is Debug-OFF on purpose.
- If `xcodebuild test` complains about the test host path, confirm `PRODUCT_NAME` is `SteamShelf` (no space).

### A2. Core models + pure logic
Files: `Model/ShelfDocument.swift`, `Model/Pagination.swift`, `Model/SteamIDInput.swift`, `BackOfBox/BackOfBoxProvider.swift` (types only + `LocalBackOfBoxProvider`), `Tests/ShelfDocumentTests.swift`, `Tests/PaginationTests.swift`.
Acceptance (tests):
- ShelfDocument round trip: encode → decode → `==`, including nil/non-nil optionals, a `blurb`, unicode in notes, dates (compare with 1-second tolerance or use whole-second dates in fixtures — ISO8601 drops sub-seconds).
- Decoding a document with `"version": 2` throws `DocumentError.unsupportedVersion(2)`.
- Decoding JSON with an extra unknown key succeeds.
- `forSharing()` drops unshelved entries; `insertSorted` orders "the Witcher", "Zelda-like", "ábc" correctly with `localizedStandardCompare`.
- Pagination: itemCount 0 → pageCount 1, range(0) empty, both labels nil; 16 → 1 page; 17 → 2 pages, range(1) == 16..<17; 40 → 3 pages; `slot(ofItem: 21)` == (1, 1, 1); leftHandleLabel(0) nil, leftHandleLabel(2) == 2; rightHandleLabel(0) == 2, rightHandleLabel(last) nil; target(.right, clickCount: 2, currentPage: 0) == last; target(.left, clickCount: 2, …) == 0; single clicks clamp at ends; clamp(99) == last.
- LocalBackOfBoxProvider is deterministic: same context → same output; different playtime bucket → different blurb.

LocalBackOfBoxProvider content (pick variant by `appID % variants.count`):
| Hours | Taglines / blurbs (write 2 variants each, in this voice) |
|---|---|
| 0 | "Still in the shrink-wrap." / "A pristine monument to good intentions. Mint condition. Never touched. Collectors weep." |
| < 2 | "Tried it once." / "Launched, looked around, alt-tabbed. The relationship is complicated." |
| 2–20 | "A pleasant fling." / "Enough hours to have opinions, not enough to defend them at a party." |
| 20–100 | "A proper commitment." / "The save file has seen things. Weekends were sacrificed. Worth it, probably." |
| 100–500 | "Load-bearing hobby." / "At this point the game plays you. Your chair has a permanent dent." |
| 500+ | "A second mortgage on free time." / "Legend says the owner once touched grass. Unconfirmed." |
Append one achievement sentence when data exists: 100% → "Every achievement. Every. Single. One."; ≥ 50% → "Trophy case more than half full."; > 0 → "A modest trophy shelf."; 0 of N → "Zero achievements. Pure vibes."

### A3. Steam DTOs, URL construction, decoding tests
Files: `Steam/SteamModels.swift`, `Steam/CoverURLs.swift`, `Steam/SteamClient.swift` (the static `parse*` functions + `checkStatus` now; networking in A4), `Tests/SteamDecodingTests.swift`, `Tests/CoverURLTests.swift`.
Embed fixtures as Swift raw string literals (`#"""…"""#`) copied from RESEARCH.md, plus:
- owned games private: `{"response":{}}` → throws `.gameDetailsPrivate`
- owned games zero: `{"response":{"game_count":0}}` → `[]`
- owned game missing optional fields (`name`, `has_community_visible_stats`, `rtime_last_played`) decodes
- achievements: success with 3 items (2 achieved) → (2, 3); success w/o `achievements` → (0, 0); status 403 "Profile is not public" → `.privateProfile`; status 400 "Requested app has no stats" → `.noStats`; status 403 HTML body → `.invalidKey`
- vanity success / `success: 42` → `.vanityNotFound`
- summaries empty players → `.profileNotFound`
- GetItems: the PEAK + Portal 2 + invalid (`success: 15`, `appid: 0`, `id: 999999999`) sample → dict has keys 3527290 and 620 only
- `checkStatus`: 401 & 403 → invalidKey, 429 → rateLimited, 500 → http(500), 200 ok
CoverURL tests:
- `assetURL(format: "steam/apps/3527290/${FILENAME}?t=1790591892", asset: "480bd…/library_600x900_2x.jpg")` == `https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3527290/480bd…/library_600x900_2x.jpg?t=1790591892`
- unhashed portrait/header URLs for 620
- `portraitCandidates` with hashed assets → [hashed 2x, hashed 1x, unhashed 2x]; with bare-filename assets (Portal 2) → de-duplicated; with nil assets → [unhashed 2x]; Dota-style `library_capsule_2x.jpg` filename passes through untouched
- `header` with and without assets.
- SteamIDInput (lives in this file to keep 4 test files): 17-digit id, `/profiles/` URL with and without trailing slash, `/id/name/` URL, bare vanity → expected cases; `"hello world"`, `""`, 16 digits → nil.
Gotcha: `${FILENAME}` in a Swift string literal is fine (no interpolation — `$` is not special), but inside `"\(…)"` be careful; use a plain literal constant `"${FILENAME}"`.

### A4. SteamClient networking
Files: `Steam/SteamClient.swift`.
Implement `get` with `URLComponents(url: apiBase.appending(path: path))`, `queryItems` (+ `format=json`), `URLRequest` timeout 20 s, `session.data(for:)`; map `URLError` → `.network(localizedDescription)`. `storeAssets` builds `input_json` with `JSONSerialization` (or an `Encodable` struct) and chunks ids by 100, merging results; one failed chunk does not fail the rest (log and continue).
Acceptance: compiles under strict concurrency; unit tests still pass (no live network in tests).
Gotcha: `resolveSteamID(.steamID64(id))` returns `id` immediately without a network call.

### A5. Keychain, persistence, library cache
Files: `Persistence/Keychain.swift`, `Persistence/ShelfStore.swift`, `Persistence/LibraryStore.swift`.
Acceptance: `LocalShelfSource.save` then `load` returns the same doc (verify in a test using an in-memory `ModelContainer` — add to `ShelfDocumentTests`). Keychain is not unit-tested (would prompt).
Gotchas:
- SwiftData `@Model` classes are not Sendable; keep all SwiftData access on the main actor (`ShelfSource` is `@MainActor`). Use `container.mainContext`.
- Fetch with `FetchDescriptor<ShelfRecord>(predicate: #Predicate { $0.kindRaw == "local" })` — capture the string in a local `let kind = "local"` first; `#Predicate` cannot reference static members.
- Ad-hoc signed builds change code signature on every rebuild, so macOS may show "SteamShelf wants to use your confidential information stored in 'net.outofajam.SteamShelf' in your keychain" after each rebuild. Expected in Debug; the user clicks "Always Allow". Do not "fix" this with the data-protection keychain (needs a team ID, fails with -34018).
- `[Int: Date]` / `[Int: StoreAssets]` encode as JSON arrays of alternating key/value — fine for this private cache file.

### A6. Image cache + art generator
Files: `Images/ImageCache.swift`, `Images/ArtGenerator.swift` (includes `SendableImage`, `SplitMix64`, `TextureLibrary`, `PlaceholderCoverView`).
PlaceholderCoverView (600×900): palette chosen by `appID % 8` from these (background top → bottom, accent): `#2F4858→#1B2A35, #F6AE2D`; `#6B2E1F→#3A160E, #F3E9D2`; `#33658A→#1D3A50, #F6AE2D`; `#4B3F72→#2A2342, #FFC857`; `#3D5A3A→#22341F, #E9D8A6`; `#7A4E2D→#3B2415, #F0D48A`; `#1F2041→#0F1022, #E26D5C`; `#5E2B4E→#33172A, #F3E9D2`. Layout: gradient background, 3 thin accent horizontal rules at 22%, 24%, 26% height, title Baskerville Bold 64 pt accent color centered at 45% height (max 4 lines, minimumScaleFactor 0.4), a sunburst of 12 accent@12% triangles behind the title, footer "A STEAM GAME" Copperplate 20 pt accent@70% at the bottom. Header composite: same background, header art (460×215) scaled to width 540 at the top 40 pt margin with a 4-pt cream frame and shadow; title below.
Acceptance: app launches (Phase A grid) and shows placeholder covers in demo mode; `TextureLibrary.prepare()` completes < 1 s on Apple Silicon (log elapsed in Debug).
Gotchas:
- `ImageRenderer` is `@MainActor`; call only from main. Set `renderer.scale = 2`. Returns nil if the view has zero size — always wrap in `.frame(width:height:)`.
- CGContext: `CGContext(data: nil, width:, height:, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)`. CoreGraphics origin is bottom-left — irrelevant for noise/grain, but remember it for the vertical-grain rotation.
- In `ImageCache`, `URLSession.data(from:)` for a 404 does not throw — check `(response as? HTTPURLResponse)?.statusCode == 200` and `mimeType?.hasPrefix("image/")`.

### A7. AppModel + Settings UI + demo mode + interim grid
Files: `App/AppModel.swift`, `App/SteamShelfApp.swift`, `Views/SettingsView.swift`, `Views/Theme.swift` (palette/fonts/metrics/motion constants in full now), `Demo/DemoData.swift`, `Views/ShelfView.swift` (interim: a plain `LazyVGrid` of 4 columns of covers for the current page + Prev/Next buttons — replaced in B2).
DemoData: 50 invented titles (no real trademarks), e.g. "Moose Kart Deluxe", "Tundra Tactics", "The Last Ferry to Kodiak", "Spreadsheet Knights", "Goose of War", "Crab Rave Tycoon", "Midnight Sun Racing", "Permafrost Protocol", "Salmon Run 2: Upstream", "Northern Lights Out", "Server Room Survivor", "Ticket Queue Zero", "Password123: The Game", "Aurora Drift", "Big Rig Iditarod", "Bush Pilot Simulator", "Cabin Fever Chronicles", "Denali Dash", "Eagle Eye Accounting", "Fjord Focus", … (fill to 50). Stats: playtime from `SplitMix64(seed: 42)` with a skewed distribution (30% zero, rest `Int(pow(rand, 3) × 60000)` minutes), achievements total 0/12/30/50/77, earned ≤ total, 60% rated, 40% with notes ("Bought it during a sale at 2 a.m.", …), purchaseDate for 30%.
Acceptance:
- `make demo` opens the app with 40 placeholder covers across 3 pages (16/16/8); Prev/Next works.
- Settings (⌘,) shows the demo banner and a 50-row checklist with 40 checked; unchecking removes a cover from the grid immediately; re-checking restores it with its note/rating intact.
- Normal launch without key shows the empty state text (interim) and Settings works: entering key saves to Keychain; Connect with a real key + public profile loads games (manual check by the user — not automatable).
- `make test` passes and does not touch the network or Keychain (verify `AppModel` in `.tests` mode skips `onLaunch`).
Gotchas:
- `@Observable` + `@MainActor` class: initialize all stored properties in `init`; don't use `lazy`.
- `@Environment(\.openSettings)` (macOS 14+) to open Settings from the main window.
- Use `Toggle(isOn: Binding(get: { model.isShelved(id) }, set: { model.setShelved(id, $0) })).toggleStyle(.checkbox)`.
- Debounced save: store `private var saveTask: Task<Void, Never>?`; cancel and recreate; `try? await Task.sleep(for: .milliseconds(500))`; check `Task.isCancelled`.
- `refreshAllStats` throttling: iterate appIDs in chunks of 4 with `withTaskGroup`, awaiting each chunk.

**Phase A exit:** `make` green; `make demo` shows the interim grid with placeholders; Settings checklist works; export of the document is possible via a debug print if needed. Commit.

---

## Phase B — the shelf, the box, the charm

### B1. Theme chrome: backdrop, header, bookcase frame
Files: `Views/ShelfView.swift` (ShelfView, HeaderBar, BookcaseView), `Views/Theme.swift`, `Images/ArtGenerator.swift` (wood + linen algorithms per DESIGN §3).
Acceptance: window shows linen backdrop + vignette, wooden header with brass nameplate, full bookcase (crown, stiles, base, 4 bays with back panel, 4 planks, all shadows per DESIGN §2/§4), scales smoothly while resizing down to 820×700 without clipping; textures tile seamlessly (no visible seams at 1024-px boundaries).
Gotchas: generate textures once in `TextureLibrary.prepare()` from `ShelfView.task`; show flat palette colors until ready (no flash of white). Wrap the scaled bookcase in a fixed-size `ZStack` with `.frame(width: 1100*scale, height: 1000*scale)` — do NOT use `.scaleEffect` on the whole bookcase (blurry text, wrong hit-testing); multiply metrics by `scale` instead.

### B2. Shelf page + box tiles
Files: `Views/ShelfView.swift` (ShelfPageView, BoxTile, CoverLoader, EmptyShelfCard).
Acceptance: 16 boxes per page with spine sliver, top sliver, gloss, drop + contact shadows, hover lift, press, loading placeholder cross-fade, cursor change; last page partially filled leaves empty slots (just back panel); empty state card per DESIGN §11 with working buttons.
Gotchas: `CoverLoader` is created per tile with `@State` and started from `.task(id: entry.appID)` so it cancels on page change. Compute spine color off-main? It's a 1×1 draw — fine on main. Report tile frames with `GeometryReader` in background → `proxy.frame(in: .named("shelfSpace"))`, only read at click time (don't store every frame in state).

### B3. Handles + page slide
Files: `Views/HandleView.swift`, `Views/ShelfView.swift`, `App/AppModel.swift`.
Acceptance: labels show neighbour page numbers; disabled look at ends; single click slides the rows (frame stays still) with a push in the correct direction; double-click on right jumps to last page, on left to first; keyboard ←/→/Home/End and menu ⌘←/⌘→ work; with ≤ 16 games both handles are disabled; removing games in Settings while on the last page clamps the page.
Gotchas: the page container must `.clipped()` to the bay interior so the push doesn't draw over the stiles. Keep the planks drawn in the frame layer (not in the page) so they don't slide — the page layer contains only boxes and their contact shadows. `NSApp.currentEvent` is available inside `onTapGesture` actions on macOS.

### B4. Open-box overlay (2D flight)
Files: `Views/OpenBoxView.swift`, `App/AppModel.swift`.
Acceptance: clicking a tile runs lift → fly → (placeholder stage for now: a 2D image at the target frame); dim overlay; Escape/✕/backdrop click runs the return path and the box lands exactly in its slot; clicking during an animation is ignored; reduce-motion path works.
Gotchas: drive phases with `withAnimation(…) { … } completion: { … }` (macOS 14+) rather than sleeping. Keep the flyer image in `@State` inside OpenBoxView so it survives page re-renders. The tile slot must show the dust outline while `openedAppID == entry.appID`.

### B5. RealityKit box
Files: `Views/BoxScene.swift`, `Views/OpenBoxView.swift`.
Acceptance: after the flight, the cross-fade reveals the 3D box with the same size/position (±3%); drag rotates smoothly at 60 fps (check with a quick FPS log from `SceneEvents.Update` deltaTime in Debug), inertia coasts and stops, pitch springs back, idle bob, Flip button/Space turns to back and returns; spines show the rotated title; top/bottom edges are spine-colored; lighting reads as upper-left key.
Gotchas:
- The `RealityView` make closure is `async` — build textures there with `try await TextureResource(image:options:)`. Build all images (front, back, spine) **before** presenting (during the flight) and pass them in as `SendableImage`.
- Camera: add a `PerspectiveCamera` entity at z = 0.85. **If the view ignores it** (box appears huge/cropped or not at all), remove the camera entity and instead place `root` at `[0, 0, -0.85]` (the default virtual camera sits at the origin looking down −Z); adjust light `look(at:)` targets to the new root position.
- Background: RealityView on macOS should composite transparently over SwiftUI. If it renders an opaque background, keep the stage square and draw a matching radial "spotlight" backdrop (`#2A1D14` center → `dimOverlay` edge) behind the whole overlay so the square is invisible.
- Store the `EventSubscription` in `BoxMotion.subscription`; cancel it in `onDisappear`.
- Planes are single-sided: if a face is invisible, its rotation sign is wrong (it's facing inward) — flip the sign per the ARCHITECTURE table, don't switch to double-sided materials.
- If the back label appears mirrored, the back plane's rotation is wrong (must be π about **Y**, not X).
- Fallback if `SceneEvents.Update` subscription is unavailable/unreliable: wrap the RealityView in `TimelineView(.animation)` and call `motion.step` in the `update:` closure using `context.date` deltas.

### B6. Back label + editor
Files: `BackOfBox/BackOfBoxView.swift`, `Views/BoxScene.swift`, `Views/OpenBoxView.swift`, `App/AppModel.swift`.
Acceptance: back label matches DESIGN §8 in all states (unrated, no purchase date, no achievements, private achievements, loading, long title, long note); Edit Label slides the panel in, the box turns to show its back, editing stars/date/note updates the 3D texture within ~200 ms and persists (quit + relaunch shows the edits); stats refresh on open when stale; blurb from LocalBackOfBoxProvider appears and does not change while typing a note.
Gotchas: render the back to `CGImage` on the main actor, then `await TextureResource(...)` in a `Task`; guard against out-of-order completions with a monotonically increasing `backVersion` (ignore results older than the latest). `ImageRenderer` cannot draw `TextEditor` — keep the editor 2D only.

### B7. Polish & export/import
Files: `App/SteamShelfApp.swift` (commands), `App/AppModel.swift`, `Views/ShelfView.swift`, `Views/SettingsView.swift`.
Acceptance: File ▸ Export Shelf… writes a `.steamshelf` JSON (via `.fileExporter` with a `FileDocument` wrapper or `NSSavePanel`) that re-imports identically; Import replaces the current shelf after a confirmation alert; Refresh button spins while loading; all error messages per DESIGN §9.1; `make` green; no warnings.
Gotcha: for `.fileExporter` define `struct ShelfFile: FileDocument` inside `SteamShelfApp.swift` with `static var readableContentTypes = [UTType(exportedAs: "net.outofajam.steamshelf")]`.

**Phase B exit:** `make` green; `make demo` gives the full experience with zero network; manual run with a real key works end to end. Commit.

---

## Manual verification checklist (for the user, after Phase B)
1. `make demo` — browse 3 pages, double-click handles, open a box, spin it, flip, edit label, close with Escape.
2. `make run` — Settings → paste key → enter vanity URL → Connect → tick ~20 games → covers load (older and newer games; confirm a 2024+ game gets art via the hashed path).
3. Set Steam "Game details" to Private → Refresh Library → the privacy error message appears.
4. Quit and relaunch — shelf, notes, ratings persist; covers load from disk instantly (turn Wi-Fi off to confirm).
