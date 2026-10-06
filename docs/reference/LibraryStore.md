# LibraryStore

Path: [`Sources/Persistence/LibraryStore.swift`](../../Sources/Persistence/LibraryStore.swift) (39 lines)

An on-disk JSON cache of the user's owned Steam games, keyed by SteamID64. It is a cache in the sense that it can be rebuilt from the Steam API, but it lives in Application Support (not Caches) because it also holds `firstSeen` dates that cannot be rebuilt: the first time the app saw each game, shown as "On shelf since" on the back of the box.

## Depends on / used by

- Depends on: [SteamModels](SteamModels.md) (`OwnedGame`, `StoreAssets`).
- Used by: [AppModel](AppModel.md) (`onLaunch`, `connect`, `refreshLibrary`, `leaveDemo`), [DemoData](DemoData.md) (builds an `OwnedLibraryCache` in memory, never saved).

## Types

### `OwnedLibraryCache`

`struct OwnedLibraryCache: Codable, Sendable, Equatable`

| Field | Type | Notes |
|---|---|---|
| `steamID64` | `String` | Owner. |
| `fetchedAt` | `Date` | When `GetOwnedGames` last succeeded. |
| `games` | `[OwnedGame]` | Raw API rows (name, playtime, last-played epoch...). |
| `firstSeen` | `[Int: Date]` | First time each appID appeared in a refresh. Never reset. |
| `assets` | `[Int: StoreAssets]` | Hashed art file names from `IStoreBrowseService`, merged across refreshes. |

`func isStale(now: Date = .now) -> Bool`: true when `fetchedAt` is more than 6 hours old. This is the launch refresh rule (Q13).

### `LibraryStore`

`enum LibraryStore` (static functions, not isolated)

| Signature | Behaviour |
|---|---|
| `static func url(for steamID: String) -> URL` | `<Application Support>/SteamShelf/library-<digits>.json`. Creates the directory (falls back to the temporary directory if Application Support cannot be located). The SteamID is filtered to ASCII digits so it can never escape the directory. |
| `static func load(steamID: String) -> OwnedLibraryCache?` | Reads and decodes with `.iso8601` dates; `nil` on any failure (missing file, corrupt JSON). |
| `static func save(_ cache: OwnedLibraryCache) throws` | Encodes with `.iso8601` and writes atomically. |

## Gotchas

- Inside the App Sandbox, "Application Support" is the container's, so the real path is `~/Library/Containers/net.outofajam.SteamShelf/Data/Library/Application Support/SteamShelf/`.
- A cache that fails to decode (for example after a model change) silently looks like "no cache" and triggers a fresh refresh, losing `firstSeen` history.
- The encoder does not set `.sortedKeys`, so file bytes are not stable between saves.

## See also

[App and state](../architecture/app-and-state.md), [Steam](../architecture/steam.md).
