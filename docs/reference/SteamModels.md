# SteamModels

Path: [`Sources/Steam/SteamModels.swift`](../../Sources/Steam/SteamModels.swift) (80 lines)

Plain data-transfer types that mirror the JSON shapes of the Steam endpoints the app uses. Field names deliberately keep Steam's snake_case and lower-case spelling so the synthesized `Decodable` works without `CodingKeys`. Optional fields are optional because Steam omits them for some games.

## Depends on / used by

- Depends on: Foundation.
- Used by: [SteamClient](SteamClient.md) (decoding), [LibraryStore](LibraryStore.md) (`OwnedGame`, `StoreAssets` are persisted inside `OwnedLibraryCache`), [AppModel](AppModel.md), [CoverURLs](CoverURLs.md), [SettingsView](SettingsView.md), [DemoData](DemoData.md), [Tests](Tests.md).

## Types

All are `Sendable`. `Codable` where persisted.

| Type | Fields | Endpoint / notes |
|---|---|---|
| `ResolveVanityEnvelope` (`Decodable`) | `response: R { success: Int, steamid: String?, message: String? }` | `ResolveVanityURL`; `success == 1` means found, 42 means no match. |
| `PlayerSummariesEnvelope` (`Decodable`) | `response: R { players: [PlayerSummary] }` | `GetPlayerSummaries`. |
| `PlayerSummary` (`Codable, Equatable`) | `steamid`, `personaname`, `profileurl?`, `avatarfull?`, `communityvisibilitystate?` | Persisted as JSON in `UserDefaults` (`playerSummary`) so the persona name is known at launch. Contains a display name and avatar URL, i.e. personal data; it is only stored locally. |
| `OwnedGamesEnvelope` (`Decodable`) | `response: R { game_count: Int?, games: [OwnedGame]? }` | `GetOwnedGames`; both absent means private. |
| `OwnedGame` (`Codable, Equatable, Identifiable`) | `appid`, `name?`, `playtime_forever` (minutes), `img_icon_url?`, `has_community_visible_stats?`, `rtime_last_played?` (epoch seconds, 0 = never), `playtime_2weeks?`; computed `id` (appid), `displayName` (`name ?? "App <id>"`), `lastPlayedDate` (nil when missing or 0) | Persisted in the library cache. |
| `PlayerStatsEnvelope` (`Decodable`) | `playerstats: Stats { success: Bool, error: String?, gameName: String?, achievements: [Achievement]? }`, `Achievement { apiname, achieved: Int, unlocktime: Int? }` | `GetPlayerAchievements`. |
| `StoreItemsEnvelope` (`Decodable`) | `response: R { store_items: [StoreItem]? }` | `IStoreBrowseService/GetItems`. |
| `StoreItem` (`Decodable`) | `id`, `success`, `name?`, `assets: StoreAssets?` | Items with `success != 1` are skipped by the parser. |
| `StoreAssets` (`Codable, Equatable`) | `asset_url_format?`, `library_capsule?`, `library_capsule_2x?`, `header?` | The format is a path template containing `${FILENAME}`; the other three are file names (see [CoverURLs](CoverURLs.md)). Persisted in the library cache. |
| `AchievementSummary` (`Equatable`) | `earned: Int`, `total: Int` | Output of `parseAchievements`. |

## Gotchas

- `playtime_forever` is in minutes; `playtime_2weeks` and `img_icon_url` are decoded but not used by the UI.
- `has_community_visible_stats` is optional: `nil` is treated as `false` by `AppModel`, which then never requests achievements for that game.
- Adding a stored field to `OwnedGame` or `StoreAssets` must stay optional, otherwise an existing library cache file stops decoding and is silently discarded.

## See also

[Steam](../architecture/steam.md).
