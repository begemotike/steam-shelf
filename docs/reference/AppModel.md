# AppModel

Path: [`Sources/App/AppModel.swift`](../../Sources/App/AppModel.swift) (770 lines)

`AppModel` is the single `@MainActor @Observable` object that owns every piece of live application state: the `ShelfDocument`, the cached Steam library, navigation (current page, open box), configuration mirrored from `UserDefaults`/Keychain, and the async workflows that mutate them (connect, refresh, launch a game, write Shelf-Keeper notes). Views read it through the SwiftUI environment and call its methods; they never touch the network, Keychain or persistence directly. The file also defines the small value enums the model exposes (`LaunchMode`, `LoadState`, `SlideDirection`), `KeeperText` (user-facing copy for Shelf-Keeper failures) and two DEBUG-only helpers (`DebugNotes`, `dumpDigestIfRequested`).

## Depends on / used by

- Depends on: [ShelfDocument](ShelfDocument.md), [ShelfStore](ShelfStore.md) (`ShelfSource`, `LocalShelfSource`, `DemoShelfSource`), [LibraryStore](LibraryStore.md), [Keychain](Keychain.md), [SteamClient](SteamClient.md), [SteamInstalls](SteamInstalls.md), [SteamIDInput](SteamIDInput.md), [CoverURLs](CoverURLs.md), [ImageCache](ImageCache.md), [BackOfBoxProvider](BackOfBoxProvider.md), [DemoData](DemoData.md), [Pagination](Pagination.md), [AIProvider](AIProvider.md), [ShelfKeeperAI](ShelfKeeperAI.md), [GamePersonalizer](GamePersonalizer.md), [SteamFolderAccess](SteamFolderAccess.md), [Theme](Theme.md) (`Theme.Motion`).
- Used by: [SteamShelfApp](SteamShelfApp.md) (creates it, menu commands), [ShelfView](ShelfView.md), [OpenBoxView](OpenBoxView.md), [BackOfBoxView](BackOfBoxView.md) (`LabelEditorPanel`), [KeeperNotesPanel](KeeperNotesPanel.md), [SettingsView](SettingsView.md), [HandleView](HandleView.md) (via `ShelfView`'s stiles), and the tests ([Tests](Tests.md)).

## Top-level types

| Type | Kind | Notes |
|---|---|---|
| `LaunchMode` | `enum { normal, tests }`, `Sendable` | `tests` is chosen when `XCTestConfigurationFilePath` is in the environment. In `tests` mode nothing is written to `UserDefaults`, the Keychain is never touched, saves are not scheduled, and the source is an in-memory `DemoShelfSource`. |
| `LoadState` | `enum { idle, loading(String), failed(String) }`, `Equatable, Sendable` | Used for `libraryState` (shown in the base rail and Settings) and `modelsState` (model picker). The payload is user-visible copy. |
| `SlideDirection` | `enum { forward, backward }`, `Sendable` | Read by `PageContainerView` to pick the edge of the `.push` transition. |
| `AppModel` | `@MainActor @Observable final class` | Described below. |
| `AppModel.KeeperState` | `enum { idle, reading, writing, failed(String) }` | Per-game state of a Shelf-Keeper run, held in `keeperState[appID]`. |
| `AppModel.InstallState` | `enum { installed, notInstalled, unknown }` | Result of `installState(for:)`. |
| `KeeperText` | `enum` (static members) | `noAccess`, `noKey` strings and `message(for:)` which maps `KeeperError`/`PersonalizerError`/other errors to copy. |
| `DebugNotes` (`#if DEBUG`) | `enum` | `sample`: a canned `BackOfBoxContent` used by `--demo-notes`. |

## Persisted keys (`DefaultsKey`, private)

`steamIDInput`, `resolvedSteamID`, `hasAPIKey`, `hasAIKey` (legacy Anthropic-only flag from before multi-service support; still read at init and still written), `aiKeyProviders`, `aiConfig`, `saveTimeZone`, `playerSummary`, `shelfLights`. All are in `UserDefaults.standard`; secrets are never among them (the `has*` keys are boolean mirrors so launch never reads the Keychain).

## Published state

Everything below is a stored property of the `@Observable` class, so SwiftUI tracks reads per property.

### Configuration

| Property | Type | Behaviour |
|---|---|---|
| `mode` | `let LaunchMode` | Fixed at init. |
| `steamIDInput` | `String` | `didSet` writes `UserDefaults` in `.normal` mode. Bound to the Settings text field. |
| `resolvedSteamID` | `String?` | SteamID64 after a successful `connect()`; persisted. |
| `hasAPIKey` | `Bool` | Mirror of "Steam Web API key exists in Keychain". Initialised from defaults, not Keychain. |
| `aiKeyProviders` | `private(set) Set<String>` | Provider ids that have a key in the Keychain (mirror). Legacy `hasAIKey` migrates in as `"anthropic"`. |
| `aiConfig` | `AIConfig` | Chosen service, base URL and model; `didSet` persists JSON and, when provider or base URL changed, clears `availableModels` and `modelsState`. |
| `saveTimeZoneID` | `String?` | Zone the saves were played in; `nil` means this Mac's current zone. |
| `saveTimeZone` | `TimeZone` (computed) | `saveTimeZoneID` resolved, falling back to `.current`. |
| `availableModels` / `modelsState` | `private(set) [String]` / `private(set) LoadState` | Output of `loadModels()`. |
| `hasAIKey` | `Bool` (computed) | `aiKeyProviders.contains(aiConfig.providerID)`. |
| `aiReady` | `Bool` (computed) | A key exists (or the preset needs none), a model is chosen and the base URL validates. |
| `hasSaveAccess` | `Bool` | Whether the security-scoped Steam folder bookmark resolves. |
| `playerSummary` | `PlayerSummary?` | Cached persona/avatar; persisted as JSON. |

### Data

| Property | Type | Behaviour |
|---|---|---|
| `source` | `private(set) any ShelfSource` | `LocalShelfSource` (SwiftData) or `DemoShelfSource` (memory). `isDemo` is `source.sourceID == "demo"`. |
| `document` | `private(set) ShelfDocument` | The one schema (see [ShelfDocument](ShelfDocument.md)). Mutated only through model methods. |
| `library` | `private(set) OwnedLibraryCache?` | Owned games, first-seen dates and store art asset names. |
| `libraryState` | `LoadState` | Progress/failure of connect and refresh flows. |

### Navigation, open box, lights, status, files

| Property | Notes |
|---|---|
| `pageIndex`, `slideDirection`, `pagination` | `pagination` is computed from `document.shelvedEntries.count`. |
| `openedAppID`, `openedFromFrame`, `isEditingLabel`, `isShowingNotes` | Open-box state. `openedFromFrame` is a rect in the `shelfSpace` coordinate space, kept live by the opened tile. |
| `keeperState` | `[Int: KeeperState]`, keyed by appID. |
| `lightsOn` | Persisted (`shelfLights`); in tests mode always `false`. `toggleLights()` animates with `Theme.Motion.lights`. |
| `installedAppIDs`, `steamAvailable` | `private(set)`; `nil` installed set means "unknown". |
| `transientStatus` | One-line message in the base rail, auto-cleared. |
| `isExporting`, `exportFile`, `isImporting`, `pendingImport`, `fileAlert` | Flags driving `fileExporter`/`fileImporter`/alerts in `ShelfView`. |
| `steam`, `images`, `backOfBox` | Services (`SteamClient` actor, `ImageCache` actor, `any BackOfBoxProvider`). |

## Initialiser

`init(mode: LaunchMode, container: ModelContainer, startDemo: Bool = false)`. Builds services, then branches. `.normal`: reads every persisted value from `UserDefaults`, `hasSaveAccess = SteamFolderAccess.isGranted`, `source = LocalShelfSource(container:)`. `.tests`: all defaults, `source = DemoShelfSource()`. In both cases `document` starts as `ShelfDocument.empty(owner:)` (owner SteamID read from defaults, name "My Shelf"). If `startDemo` it calls `startDemo()`. Note `--demo` therefore replaces the document and library before the first frame; `onLaunch()` then returns early because `isDemo`.

## Methods

Signatures are copied from source. Isolation is `@MainActor` for all of them (class-level) unless noted.

### Lifecycle

| Signature | What it does |
|---|---|
| `func onLaunch() async` | Called once from `ShelfView`'s `.task` after textures are prepared. DEBUG: runs `dumpDigestIfRequested()` first. Returns immediately in tests mode or demo. Otherwise loads the stored document (`try? source.load()`; a failed decode is treated as "no shelf", see failure modes), loads the library cache for `resolvedSteamID`, clamps `pageIndex`, and if a key and SteamID exist and the cache is missing or older than 6 h, runs `refreshLibrary(manual: false)`. |

### Account and AI configuration

| Signature | What it does |
|---|---|
| `func saveAPIKey(_ key: String)` | Trims, stores in Keychain under `Keychain.apiKeyAccount`, sets `hasAPIKey` and its defaults mirror, clears a previous `.failed` library state. Keychain failure sets `libraryState = .failed("Couldn't save the key in your Keychain.")`. No-op in tests mode or for an empty key. |
| `func forgetAPIKey()` | Deletes the Steam key and clears the mirror. |
| `func saveAIKey(_ key: String)` | Trims; if `AIProviders.detect(fromKey:)` recognises the prefix and it differs from the current service, switches `aiConfig` to that preset first. Saves under `Keychain.aiKeyAccount(for:)`, updates `aiKeyProviders`, persists, then kicks off `loadModels()`. A failure is only logged. |
| `func selectAIProvider(_ id: String)` | Replaces `aiConfig` with the preset's defaults (model reset to the preset's default or empty); loads the model list when a key exists or none is needed. |
| `func loadModels() async` | `GET <base>/models` through `ShelfKeeperAI.models`. Ignores a result if the provider or base URL changed while waiting. Errors become `modelsState = .failed(copy)`. |
| `func forgetAIKey()` | Deletes the current service's key, removes it from the mirror, clears `availableModels`. |
| `func requestSaveAccess()` / `func revokeSaveAccess()` | Wrap `SteamFolderAccess.requestAccess()` (modal folder picker) / `revoke()` and update `hasSaveAccess`. |

### Steam library

| Signature | What it does |
|---|---|
| `func connect() async` | Parses `steamIDInput` (`SteamIDInput.parse`), resolves vanity names, fetches the player summary, persists it, loads any cached library, updates `document.owner` and (when the title is the default `"My Shelf"` or ends in `'s Shelf`) retitles the shelf to `"<persona>'s Shelf"`, schedules a save, then `refreshLibrary(manual: true)`. Errors go through the private `fail(_:)` which maps `SteamError` to `userMessage`. Guards: tests mode, demo. |
| `func refreshLibrary(manual: Bool = true) async` | `ownedGames` then `storeAssets`. `manual == true` re-fetches art for every game; `false` only for games without cached assets. A failed assets call is swallowed (`try?`), so covers fall back to unhashed CDN paths. Builds a fresh `OwnedLibraryCache` (preserving `firstSeen`), saves it via `LibraryStore` (error ignored) and calls the private `mergeLibraryIntoEntries`. |
| `func refreshStats(for appID: Int, force: Bool = false) async` | Achievements for one shelved game. If the game lacks community stats: marks `.none` and returns. Skips if fetched less than 6 h ago unless `force`. Maps `SteamError.privateProfile` and `.noStats` to entry states; any other error is logged at debug level only. |
| `func refreshAllStats() async` | Settings button. Takes shelved appIDs in chunks of four, running `refreshStats(force: true)` for each chunk in a `TaskGroup`; progress shows as `.loading("Refreshing achievements…")`. |

### Selection

| Signature | What it does |
|---|---|
| `func isShelved(_ appID: Int) -> Bool` | Entry exists and `isShelved`. |
| `func setShelved(_ appID: Int, _ on: Bool)` | Ticks/unticks. Unticking keeps the entry (`isShelved = false`) so notes and rating survive. Ticking an unknown game creates an entry from the library cache and inserts it via `ShelfDocument.insert` (sorted, or appended on a custom shelf). |
| `func setAllShelved(_ on: Bool, appIDs: [Int])` | Bulk version; one save scheduled. |

### Local Steam client and launch

| Signature | What it does |
|---|---|
| `func installState(for appID: Int) -> InstallState` | `.unknown` when `installedAppIDs` is `nil`. |
| `func refreshInstalls()` | Reads `SteamInstalls.isSteamAvailable` and `SteamInstalls.scan()`. Cheap; called when a box opens. No-op in tests mode. DEBUG logs a direct-launch probe. |
| `var canLaunchGames: Bool` | `.normal`, not demo, a Steam client handles `steam://`, and the source is `"local"`. |
| `func launch(_ appID: Int)` | If the game is not known to be uninstalled and a bundle is found (`SteamInstalls.launchBundle`), opens it with `NSWorkspace.openApplication`; on error falls back to `steam://rungameid/<id>` (`launchViaSteam`). Otherwise goes straight to Steam. Sets a transient status either way. |
| `func showTransient(_ message: String, seconds: Double = 5)` | Sets `transientStatus`, cancels the previous timer, clears after `seconds`. |

### Arrangement and paging

| Signature | What it does |
|---|---|
| `var isCustomArranged: Bool` | `document.arrangement == .custom`. |
| `func moveEntry(_ appID: Int, before targetAppID: Int?)` | Drag-and-drop. Delegates to `ShelfDocument.move`; no-op when nothing changed. |
| `func arrangeAlphabetically()` | Only when custom; re-sorts. Menu: Shelf ▸ Arrange Alphabetically. |
| `func dragHover(over side: HandleSide, active: Bool)` | While a drag hovers a handle for 450 ms, flips one page (single-click semantics). Cancels any pending dwell first. |
| `func go(to page: Int, animation: Animation = Theme.Motion.pageSlide)` | Clamps, sets `slideDirection` in the same transaction, animates `pageIndex`. Synchronous so tests can call it. |
| `func handleTapped(_ side: HandleSide)` | Reads `NSApp.currentEvent?.clickCount`; double-click jumps to first/last page with `pageJump` animation. |

### Entry edits and open/close

| Signature | What it does |
|---|---|
| `func update(_ appID: Int, _ mutate: (inout ShelfEntry) -> Void)` | The one choke point for editing an entry: applies the closure, bumps `document.updatedAt`, schedules a save. |
| `func open(_ appID: Int, from frame: CGRect)` | Ignored when a box is already open. |
| `func close()` | Clears `openedAppID`, `isEditingLabel`, `isShowingNotes` immediately. UI closes go through `OpenBoxView.beginClose()` which animates first. |

### Demo

| Signature | What it does |
|---|---|
| `func startDemo()` | Cancels pending save, builds `DemoData.document()`, swaps in a `DemoShelfSource` holding it, installs `DemoData.library()`, resets to page 0 and closes any box. DEBUG: `--demo-notes` seeds the first entry with `DebugNotes.sample`. |
| `func leaveDemo()` | Reloads the local shelf (or an empty one), the real library cache, page 0. No-op in tests mode. |

### Export / import

| Signature | What it does |
|---|---|
| `func exportData() throws -> Data` | `ShelfDocumentCodec.encode(document.forSharing())` (only shelved entries). |
| `func beginExport()` | Wraps the data in a `ShelfFile` and sets `isExporting`; on error sets `fileAlert`. |
| `func beginImport()` | Sets `isImporting` (shows the open panel). |
| `func stageImport(_ data: Data)` | Decodes to validate; stores `pendingImport` for the confirmation alert. Unsupported version and generic decode failure produce distinct `fileAlert` copy. |
| `func confirmImport()` / `func importDocument(_ data: Data) throws` | Replaces `document` (not `source`; the imported document keeps its own `id`), clamps the page, schedules a save. |

### Back-of-box and Shelf-Keeper

| Signature | What it does |
|---|---|
| `func blurbIfNeeded(for appID: Int) async` | Called after a box finishes opening. Never replaces AI-written notes. Otherwise regenerates the template blurb only when its fingerprint (playtime bucket, achievements, rating) changed. Errors are swallowed. |
| `var canWriteNotes: Bool` | `.normal`, not demo, source is `"local"`. |
| `func keeperState(for appID: Int) -> KeeperState` | Defaults to `.idle`. |
| `func writeNotes(for appID: Int) async` | Full pipeline: guards (`canWriteNotes`, a personalizer exists for the appID, not already `.reading/.writing`, save access, `aiReady`, key present), sets `.reading`, builds the digest on a detached `userInitiated` task inside `SteamFolderAccess.withAccess`, sets `.writing`, calls `keeperAI.notes`, stores a `BackOfBoxContent` (providerID `config.contentProviderID`, fingerprint from the digest, `observations`, `detail = playstyle`) via `update`. Cancellation returns to `.idle`; other errors become `.failed(KeeperText.message(for:))`. |
| `func clearNotes(for appID: Int)` | Removes the blurb and re-runs `blurbIfNeeded` to restore the template. |

### Private helpers (one line each)

`ownerFromState()` builds a `ShelfOwner` from persona; `persistAIKeyProviders()` writes the provider list and the legacy `hasAIKey` flag; `requireKey()` reads the Steam key from Keychain or throws `SteamError.missingKey`; `fail(_:)` maps errors to `libraryState`; `mergeLibraryIntoEntries(_:)` updates title/playtime/lastPlayed/community-stats flag/art refs of existing entries only; `artRefs(appID:assets:)` builds `ArtRefs` via `CoverURLs`; `applyShelved` / `finishShelfMutation` implement `setShelved`; `launchViaSteam` opens the `steam://` URL; `scheduleSave()` is the debounced save.

### The debounced save

`scheduleSave()` returns immediately in tests mode. Otherwise it cancels the previous `saveTask` and starts a new one that sleeps 500 ms and then calls `source.save(document)` with the document as it is *at that moment*. Failures are logged (`Save failed`) and not shown to the user. There is no flush on quit, so edits made in the last half second before termination can be lost.

## DEBUG-only members

| Member | Trigger | Effect |
|---|---|---|
| `DebugNotes.sample` | `--demo-notes` with the demo | Seeds notes on the first shelved demo entry so the Notes panel can be viewed without an API call. |
| `dumpDigestIfRequested()` | `--dump-digest <appid>` | Builds the personalizer digest for that app and writes it to `<Caches>/SteamShelf/digest-<appid>.txt`; no AI call. Requires save access. Used to compare the Swift port with the Python references. |
| Direct-launch probe log | any DEBUG launch | `refreshInstalls()` logs which bundle would be launched for the first installed app. |

## Gotchas

- `hasAPIKey` and `aiKeyProviders` are *mirrors*. If the Keychain item is deleted outside the app the UI still says "Saved in Keychain" until a call fails (`SteamError.missingKey`).
- `launch(_:)` treats `.unknown` install state as installed: it tries to find a bundle and falls back to Steam.
- `refreshAllStats` child tasks call back into the main-actor model, so only the network waits overlap.
- `importDocument` does not touch the Keychain or library; an imported shelf from another person keeps `owner` of the exporter, and `canWriteNotes` stays true because the source is still `"local"` (the guard is on source, not on document ownership).

## See also

[App and state](../architecture/app-and-state.md), [Overview](../architecture/overview.md), [Shelf rendering](../architecture/shelf-rendering.md) (paging and drag), [Open box](../architecture/open-box.md) (launch path), [Steam](../architecture/steam.md) (refresh), [AI writer](../architecture/ai-writer.md) (`writeNotes`).
