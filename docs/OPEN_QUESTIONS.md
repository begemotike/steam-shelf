# Steam Shelf — Open Questions (defaults already chosen)

Each item is built with the **default** shown. Revisit any time; none block v1.

| # | Question | v1 default | Why / what changing it costs |
|---|---|---|---|
| Q1 | Steam doesn't expose purchase dates through the Web API (only the logged-in licenses page does). Do you want a way to fill them in automatically? | Manual date field, empty by default. The back of the box also shows "Last played" and "On shelf since". | Auto-fill would mean either an embedded Steam login web view that scrapes `store.steampowered.com/account/licenses/` (fragile, and your Steam session would live in the app) or a paste-your-licenses-page importer. The importer is the safer add-on if you want it. |
| Q2 | Should games be reorderable on the shelf by dragging? | Alphabetical order (case-insensitive), fixed. The document already stores an explicit order, so drag-to-reorder can be added without changing the format. | About half a day: drag-and-drop between slots plus page-edge auto-flip. |
| Q3 | Is the engine choice right: 2D SwiftUI shelf + a RealityKit box only when one is open? | Yes. | Going full 3D (the whole bookcase in RealityKit) would allow real camera moves but costs a lot of effort and risks frame drops with 16 textured boxes, all to get a look SwiftUI already does well. SceneKit was ruled out because Apple has soft-deprecated it. |
| Q4 | SwiftData stores each shelf as one JSON blob (`ShelfRecord.documentData`) instead of a table per game. OK? | Yes, blob. The `ShelfDocument` is the real schema, and this keeps that schema in one place. | Per-game tables would only pay off with thousands of entries or cross-shelf queries. If SwiftData feels like overkill, a plain JSON file in Application Support would do the same job in fewer lines. |
| Q5 | When you untick a game, should its notes and rating be kept? | Kept (`isShelved = false`) and restored if you tick it again. Shared shelves leave unticked games out (`forSharing()`). | Deleting them outright would be simpler but loses notes if you misclick. |
| Q6 | Star rating: whole stars or half stars? | Whole stars, 1–5, and blank means unrated. | Half stars need a finer control and an `Int` from 1 to 10. That's a document version bump. |
| Q7 | Fetch store details (genres, developer, release date) from `appdetails`? | Not in v1. The slot is reserved in `BackOfBoxContext.storeDetails` for the AI blurbs. | The endpoint takes one app per call and allows roughly 200 calls per 5 minutes, so it has to be fetched lazily and cached. It makes most sense to add it together with the AI provider. |
| Q8 | Which AI vendor and model should write the future blurbs, and where does its key live? | Not built. The seam is `AIBackOfBoxProvider` behind `BackOfBoxProvider`, with the key in Keychain under account `ai-api-key`. | Decide when you build it. Claude via the Anthropic API fits naturally. |
| Q9 | Which P2P transport: MultipeerConnectivity (LAN/nearby), iCloud/CloudKit sharing, or a small relay (for example a Cloudflare Worker)? | Not built. The payload is `ShelfDocumentCodec.encode(doc.forSharing())`, which carries cover art as public CDN URLs and needs no key on the viewer's side. | Multipeer only works on the same network. CloudKit needs a paid team ID and signing. A relay needs hosting, which you already have on Workers. |
| Q10 | Code signing: ad-hoc (`-`) or your Apple Developer team? | Ad-hoc. It builds headlessly with no account, but after each rebuild macOS asks again for Keychain access ("Always Allow"). | Setting `DEVELOPMENT_TEAM` in project.yml removes the Keychain prompts and enables notarized distribution. It's also required for CloudKit (Q9). |
| Q11 | Should the shelf title be your Steam persona name or custom text? | "<Persona>'s Shelf" when connected, "My Shelf" otherwise. The title is stored in the document. | Adding a rename field in Settings is trivial. |
| Q12 | App icon? | None in v1 (generic app icon). | A procedurally drawn icon (a walnut box with a brass plate) could be rendered once and saved into an asset catalog later. |
| Q13 | Refresh cadence: library refreshes automatically on launch if older than 6 h, and achievements refresh when you open a box if older than 6 h. Right numbers? | Yes. | Lower means fresher numbers but more API calls. The daily limit is 100k, so this is comfortable either way. |
| Q14 | Should free-to-play games you have played appear in the checklist? | Yes (`include_played_free_games=1`). | Turning it off hides F2P titles from the checklist. |
| Q15 | Box depth: a chunky collector's box (22% of width) or a slim DVD-case look (~10%)? | Chunky at 22%, so there's room for a readable spine title. | Changing `BoxBuilder.depth` and the spine texture aspect is one constant each. |
| Q16 | If your own API key can't see your own private game list: is setting Game details to Public acceptable? | Show the fix-it message (see DESIGN §9.1). | Research couldn't test this live without a key. If your own key does bypass privacy, nothing changes. |
| Q17 | Demo mode: launch with `--demo` or the "Try the Demo Shelf" button. Demo data is never saved. Keep it in release builds? | Keep it. It's a nice first-run experience. | Remove the button and keep only the flag. |
| Q18 | Minimum macOS 15.0: fine for anyone you'd share with? | Yes, since it's the minimum for RealityView on macOS. | Going lower would mean replacing the 3D box. |

## Implementation notes (Phase A)
- `SteamIDInput.parse` rejects all-digit strings that are not valid 17-digit SteamID64s (e.g. 16 digits), even though they match the vanity regex; required by the A3 acceptance list.
- `hasAPIKey` is mirrored in UserDefaults so launch never reads the Keychain (avoids a prompt after every ad-hoc rebuild); the Keychain is read only on Connect/Refresh.
- Export/Import menu items are deferred to B7; `exportData`/`importDocument` exist on AppModel. Added `AppModel.leaveDemo()` and a `manual:` parameter on `refreshLibrary` (default true).
- Interim ShelfView also shows a "Try the Demo Shelf" button in the empty state.

## Implementation notes (Phase B)
- RealityKit on macOS 26 honoured the explicit `PerspectiveCamera` (no root-at-z fallback needed) and composites transparently over SwiftUI (no backdrop fallback needed). `SceneEvents.Update` fires reliably (no `TimelineView` fallback). Face rotations from the ARCHITECTURE table were correct as written.
- Measured: with the camera at z = 0.85 and FOV 30, the rendered front face fills 0.628 of the (square) stage side, not the 0.676 the formula predicts. `Theme.Metrics.frontFaceFill` was set to 0.628 so the flyer and the 3D front match at the cross-fade. The `BoxBuilder.makeBox` front material also carries a clearcoat of 0.6 for the shrink-wrap look.
- `BoxBuilder` is `@MainActor` (RealityKit entity APIs are main-actor isolated in the macOS 26 SDK). `BoxStageView` takes an extra `backVersion` (drives back-texture swaps) and `onReady` (signals the RealityView finished building so the cross-fade can start).
- Phase timings in `OpenBoxView` use `Task.sleep` for the fixed durations (0.16 / 0.45 / 0.15 s etc.) instead of animation completion handlers: a completion that never fires (no value change) would leave the overlay stuck; a generation counter cancels stale sequences.
- `AppModel.close()` still sets `openedAppID = nil` instantly; Escape / Close / backdrop click go through `OpenBoxView.beginClose()` which animates the return and calls `model.close()` at the end. `openedFromFrame` is kept live by the opened tile so resizing while open still lands the box in its slot.
- Handles are real `Button`s (press style via `ButtonStyle`) so `NSApp.currentEvent.clickCount` works and accessibility exposes them as "Previous/Next page".
- Slide direction: `go(to:)` stays synchronous (tests rely on it); the `.push` transition reads `slideDirection` in the same transaction. Not verified mid-flight visually (see report).
- Export/Import are driven by flags on `AppModel` (`isExporting`, `isImporting`, `pendingImport`, `fileAlert`) and presented from `ShelfView` (`fileExporter`, `fileImporter`, confirmation alert). Import validates the file before asking to replace the shelf.
- Textures for the back label render at 600x900 @2x on the main actor (~tens of ms); placeholder covers are 1200x1800 so a full page of 16 placeholder tiles holds ~140 MB of CGImages (Phase A decision, unchanged).

## Implementation notes (Phase C)
- `BayLayout` gap/side padding: PHASE_C's literal formula gives gap 54.7 / sidePad 28 for the 700x888 design bay, contradicting its own test (gap 36, boxH 180). Implemented as: preferred sidePad = max(28, boxH*56/180); gap = max(14, remaining width / 3) so the design bay reproduces 56/36 and wider bays stretch the gap (sidePad stays put).
- `BayLayout.slot(containing:)` matches box frames only (not the gaps between them); it is not yet used by the UI.
- Bay rect for the open-box overlay is derived from the window size and the frame metrics (no plumbing from BayView).
- With the editor open at the minimum window (820x700) the stage is only ~252 pt square (bay width minus 400); accepted per the §C.6 formula.
- `EmptyShelfCard` is now fixed 420x260 (no scale effect); it fits the smallest bay (652x592).
- Status line "UPDATED n MIN AGO" uses an abbreviated `RelativeDateTimeFormatter` (shows "JUST NOW" under 60 s).
- Knob and handle press states keep their existing behaviour; the refresh knob's recess does not spin (only the brass disc's parent rotates the whole control, including the recess, which is circular so it is invisible).

## Distribution notes (Sparkle + signing, 2026-09-29)
- Q10 resolved for Release: `Developer ID Application: Michael Miller (9JHK4XRFW5)`, hardened runtime, timestamped. Debug stays ad-hoc so `make` needs no certificate (and still shows the Keychain prompt after rebuilds).
- Sparkle 2.10 (SPM) runs inside the App Sandbox using the documented installer XPC service: `SUEnableInstallerLauncherService` plus the `-spks`/`-spki` mach-lookup exceptions. Verified: the Release archive launches sandboxed with Sparkle and no XPC errors.
- EdDSA key pair generated with Sparkle's `generate_keys`; the private key lives in the login keychain ("Private key for signing Sparkle updates"), the public key is in project.yml (`SUPublicEDKey`). Back up the private key with `generate_keys -x file` if this Mac is ever replaced; losing it orphans every installed copy.
- Feed: `https://raw.githubusercontent.com/begemotike/steam-shelf/main/appcast.xml`; zips attached to GitHub releases. The repo must be public for the friend's copy to reach the feed and downloads. raw.githubusercontent caches for up to ~5 minutes.
- Build number = `git rev-list --count HEAD`, so it only rises. Never re-release the same version.
- Q19: switch the feed to sprucetools.com / Cloudflare instead of GitHub raw? Default: GitHub, zero extra hosting.
