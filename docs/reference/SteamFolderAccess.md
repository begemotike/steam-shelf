# SteamFolderAccess

Path: [`Sources/Personalizer/SteamFolderAccess.swift`](../../Sources/Personalizer/SteamFolderAccess.swift) (65 lines)

Handles the user's one-time grant of the Steam folder. Save files live under `~/Library/Application Support/Steam/userdata/`, which the App Sandbox does not allow reading. The app asks the user to choose the Steam folder in an open panel and stores a read-only **security-scoped bookmark** in `UserDefaults` (key `steamFolderBookmark`). The bookmark is not a secret (only this app can resolve it), this is Apple's documented pattern, and Keychain reads are what cause password prompts.

## Depends on / used by

- Depends on: [GamePersonalizer](GamePersonalizer.md) (`PersonalizerError.noFolderAccess`), [SteamInstalls](SteamInstalls.md) (`steamappsDirectory` to preselect the panel), AppKit, OSLog.
- Used by: [AppModel](AppModel.md) (`hasSaveAccess`, `requestSaveAccess`, `revokeSaveAccess`, `writeNotes`, `dumpDigestIfRequested`).

## `SteamFolderAccess`

`@MainActor enum SteamFolderAccess` (static members). Bookmark options: `.withSecurityScope` and `.securityScopeAllowOnlyReadAccess`.

| Signature | Isolation | Behaviour |
|---|---|---|
| `static var isGranted: Bool` | main actor | A bookmark exists and resolves. |
| `static func requestAccess() -> Bool` | main actor | Runs an `NSOpenPanel` (directories only, single selection, prompt "Grant Access", explanatory message, initial directory `.../Application Support/Steam`). Requires the chosen folder to contain a `userdata` directory; otherwise shows an alert "That doesn't look like the Steam folder" and returns `false`. Creates and stores bookmark data; `false` on failure (logged). |
| `static func revoke()` | main actor | Removes the bookmark from `UserDefaults`. |
| `nonisolated static func withAccess<T>(_ body: (URL) throws -> T) throws -> T` | nonisolated | Resolves the bookmark, calls `startAccessingSecurityScopedResource()` (throws `noFolderAccess` if either step fails), `defer`s the matching stop, refreshes a stale bookmark in place, and runs `body` with the Steam root URL. Safe to call from a detached task, which is how `AppModel.writeNotes` uses it. |
| `nonisolated private static func resolve() -> (url: URL, stale: Bool)?` | nonisolated | Resolves the bookmark with `.withSecurityScope`. |

## Entitlements

Needs `com.apple.security.files.user-selected.read-write` (the open panel) and `com.apple.security.files.bookmarks.app-scope` (persisting the grant). See [Distribution](../architecture/distribution.md).

## Gotchas

- `NSOpenPanel.runModal()` blocks the main thread while it is up; acceptable for a one-time grant.
- The scope is open only for the duration of `body`; callers must finish all file reads inside the closure (the BG3 digest does).
- The grant is for the *Steam folder*, not just `userdata`, so a user can choose a Steam folder on another volume.

## See also

[Personalizer](../architecture/personalizer.md), [Distribution](../architecture/distribution.md), [App and state](../architecture/app-and-state.md).
