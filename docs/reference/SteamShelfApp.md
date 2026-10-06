# SteamShelfApp

Path: [`Sources/App/SteamShelfApp.swift`](../../Sources/App/SteamShelfApp.swift) (92 lines)

The `@main` entry point. It decides the launch mode, builds the SwiftData `ModelContainer` and the `AppModel`, declares the single window and the Settings scene, installs menu commands, and defines the `.steamshelf` file type plus the `FileDocument` wrapper used for export and import.

## Depends on / used by

- Depends on: [AppModel](AppModel.md), [ShelfStore](ShelfStore.md) (`ShelfRecord`), [Updater](Updater.md) (`UpdateCommands`, `Updater.shared`), [ShelfView](ShelfView.md), [SettingsView](SettingsView.md), [Theme](Theme.md) (`Theme.Metrics` window sizes).
- Used by: the system (entry point). `ShelfFile` and `UTType.steamShelf` are used by [ShelfView](ShelfView.md) (`fileExporter`/`fileImporter`) and [AppModel](AppModel.md) (`exportFile`).

## Types

### `SteamShelfApp` (`@main struct ... : App`)

| Member | Detail |
|---|---|
| `@State private var appModel: AppModel` | Created in `init` and held for the life of the process. |
| `let container: ModelContainer` | SwiftData container for `ShelfRecord`. |
| `init()` | Mode: `.tests` when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`, else `.normal`. `startDemo = CommandLine.arguments.contains("--demo")`. Container: `ModelContainer(for: ShelfRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: mode != .normal))`; a failure is `fatalError` (the app cannot run without its store). `AppModel(mode:container:startDemo:)`. In `.normal` mode touches `Updater.shared` so Sparkle starts its scheduled checks. |
| `body: some Scene` | `Window("Steam Shelf", id: "shelf")` with `ShelfView().environment(appModel)`; `.windowStyle(.hiddenTitleBar)`, default size from `Theme.Metrics.windowDefaultW/H` (1180 x 960), `.windowResizability(.contentMinSize)`, commands `UpdateCommands()` and `ShelfCommands(model:)`. Second scene: `Settings { SettingsView().environment(appModel) }`. |

Launch-mode notes: `--demo` is deliberately a *normal* launch that merely starts on the demo shelf, so Settings, Leave Demo and the updater all work. Tests mode uses an in-memory store and skips the updater.

### `ShelfCommands: Commands`

Holds `let model: AppModel`. Adds to File (after New Item): Refresh Library (Cmd-R), Export Shelf... (Cmd-Shift-E), Import Shelf... (Cmd-Shift-I). Adds a "Shelf" menu: Next Page (Cmd-Right), Previous Page (Cmd-Left), Shelf Lights On/Off (Cmd-L, label follows `model.lightsOn`), Arrange Alphabetically (disabled unless `model.isCustomArranged`). Plain arrow keys (no modifier) are handled separately by `ShelfView.onKeyPress`.

### `extension UTType`

`static let steamShelf = UTType(exportedAs: "net.outofajam.steamshelf")`. The type is declared in `Info.plist`/`project.yml` (conforms to `public.json`, extension `steamshelf`). The drag type `net.outofajam.steamshelf.box` is declared in the same place and wrapped as `UTType.steamShelfBox` in [ShelfView](ShelfView.md).

### `ShelfFile: FileDocument`

| Member | Detail |
|---|---|
| `readableContentTypes` / `writableContentTypes` | `[UTType.steamShelf]` |
| `let data: Data` | Already-encoded JSON from `ShelfDocumentCodec.encode`. |
| `init(data:)` | Used for export. |
| `init(configuration: ReadConfiguration) throws` | Reads `regularFileContents`, else throws `CocoaError(.fileReadCorruptFile)`. (Import in `ShelfView` reads the URL itself, so this initialiser exists to satisfy the protocol.) |
| `fileWrapper(configuration:)` | Returns a regular-file wrapper around `data`. |

## Gotchas

- The window title is hidden, but `ShelfView` finds its window for swipe handling by title `"Steam Shelf"`; renaming the `Window` breaks `SwipeMonitor` window matching (it then falls back to `NSApp.keyWindow`).
- `ShelfCommands` takes the model by value (it is a reference type), so menu enablement tracks `@Observable` properties.

## See also

[Overview](../architecture/overview.md), [App and state](../architecture/app-and-state.md), [Distribution](../architecture/distribution.md) (file type declarations).
