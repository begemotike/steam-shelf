# SteamInstalls

Path: [`Sources/Steam/SteamInstalls.swift`](../../Sources/Steam/SteamInstalls.swift) (127 lines)

Answers two questions about the *local* Steam client: which of the user's games are installed, and which `.app` bundle to open to play one. It reads Steam's `libraryfolders.vdf` and per-game `appmanifest_<id>.acf` files, which lists the library folders (including ones on other volumes) with an `"apps"` block of installed app IDs. The sandbox gets a read-only temporary exception for `~/Library/Application Support/Steam/steamapps/`. If a file cannot be read the answer is "unknown" and the UI falls back to Steam.

## Depends on / used by

- Depends on: AppKit (`NSWorkspace`), Foundation (`NSRegularExpression`, `getpwuid`).
- Used by: [AppModel](AppModel.md) (`refreshInstalls`, `launch`, `launchViaSteam`), [SteamFolderAccess](SteamFolderAccess.md) (`steamappsDirectory` to preselect the open panel), [Tests](Tests.md) (`SteamDecodingTests`: VDF parsing and bundle picking).

## `SteamInstalls`

`enum SteamInstalls` (static; not actor-isolated, synchronous file I/O, called from the main actor)

| Member | Behaviour |
|---|---|
| `static var steamappsDirectory: URL?` | `<real home>/Library/Application Support/Steam/steamapps`. Uses `getpwuid(getuid())` because inside the sandbox `NSHomeDirectory()` is the container, not the user's real home. |
| `static var isSteamAvailable: Bool` | `NSWorkspace.shared.urlForApplication(toOpen: URL("steam://"))` is non-nil. |
| `static func scan() -> Set<Int>?` | Reads `libraryfolders.vdf` as UTF-8 and calls `installedAppIDs(vdf:)`; `nil` when the file cannot be read (no Steam, or no access). |
| `static func installedAppIDs(vdf: String) -> Set<Int>` | Pure line parser. When it sees a trimmed line equal to `"apps"` it enters an apps block, tracks brace depth, and for each key/value line collects the first quoted token if it parses as an `Int`. |
| `static func launchURL(appID: Int) -> URL?` | `steam://rungameid/<appID>`. |
| `static func libraryPaths(vdf: String) -> [String]` | Every `"path"  "value"` pair in the VDF, with `\\` unescaped to `\`. |
| `private static func values(forKey:in:)` | Regex `"key"\s*"([^"]*)"` over the whole text, independent of line layout. |
| `static func installDir(manifest: String) -> String?` | First `"installdir"` value of an appmanifest, e.g. "Portal 2". |
| `static func installFolder(appID: Int) -> URL?` | For each library path from `libraryfolders.vdf`, reads `<lib>/steamapps/appmanifest_<id>.acf`, takes `installdir`, and returns `<lib>/steamapps/common/<installdir>` if that directory exists. First hit wins. Libraries on volumes the sandbox cannot read are skipped (the manifest read fails). |
| `static func appBundle(inInstallFolder folder: URL, maxDepth: Int = 3) -> URL?` | Walks directories (skipping hidden files) to `maxDepth` levels (Paradox games keep theirs in `binaries/`), collecting `.app` bundles without descending into them. Sorts by depth, then a score (0 name equals the folder name after lowercasing and keeping letters/digits, 1 one contains the other, 2 otherwise, 3 names containing "launcher"), then `localizedStandardCompare` on the file name. Returns the first. |
| `private static func normalized(_:)` | Lower-cases and keeps letters and digits. |
| `static func launchBundle(appID: Int) -> URL?` | `installFolder` then `appBundle`. |

## Gotchas

- Installed state counts apps in *all* library folders because the `"apps"` blocks cover every folder; however direct launching needs the manifest, which exists only in readable folders.
- Playing through the game's own bundle means Steam-dependent features (overlay, achievements, cloud saves) work only if the Steam client is running; games that insist on Steam relaunch themselves through it ([Play / Install notes](../decisions/OPEN_QUESTIONS.md#play--install-2026-09-30)).
- The `"apps"` marker is matched on a trimmed line equal to `"apps"`; a VDF that puts the key and brace on the same line would not be recognised (Steam writes them on separate lines).

## See also

[Open box](../architecture/open-box.md) (Play/Install path), [Distribution](../architecture/distribution.md) (the read-only entitlement exception), [Steam](../architecture/steam.md).
