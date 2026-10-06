# SteamClient

Path: [`Sources/Steam/SteamClient.swift`](../../Sources/Steam/SteamClient.swift) (212 lines)

An `actor` that talks to the Steam Web API (`https://api.steampowered.com`) and the Steam store browse service. Each public method issues one GET (or a series of them for store assets), then hands the bytes to a *pure static parser* that is covered by offline unit tests. It also defines `SteamError`, the single error type for everything Steam, with user-facing copy.

## Depends on / used by

- Depends on: [SteamModels](SteamModels.md) (envelopes and DTOs), [SteamIDInput](SteamIDInput.md), Foundation, OSLog.
- Used by: [AppModel](AppModel.md) (`steam`), [Tests](Tests.md) (`SteamDecodingTests` call the static parsers directly).

## `SteamError`

`enum SteamError: Error, Equatable, Sendable`

Cases: `missingKey`, `invalidKey`, `badSteamIDInput`, `vanityNotFound`, `profileNotFound`, `gameDetailsPrivate`, `privateProfile`, `noStats`, `rateLimited`, `http(Int)`, `network(String)`, `decoding(String)`, `steam(String)`.

`var userMessage: String` gives the copy shown in the UI:

| Case | Message |
|---|---|
| `missingKey` | "Add your Steam Web API key first." |
| `invalidKey` | "Steam rejected that API key. Double-check it at steamcommunity.com/dev/apikey." |
| `badSteamIDInput` | "That doesn't look like a SteamID64 or a steamcommunity.com profile link." |
| `vanityNotFound` | "No Steam profile uses that custom URL." |
| `profileNotFound` | "Steam doesn't know that SteamID." |
| `gameDetailsPrivate` | "Your game list is private. In Steam: Profile -> Edit Profile -> Privacy Settings -> set Game details to Public." |
| `privateProfile` | "Achievements are private for this profile." |
| `noStats` | "This game has no achievements." |
| `rateLimited` | "Steam asked us to slow down. Try again in a few minutes." |
| `http(n)` | "Steam returned an error (HTTP n)." |
| `network(msg)` | "Couldn't reach Steam: msg" |
| `decoding(msg)`, `steam(msg)` | "Steam sent something unexpected. (msg)" |

(The arrows in the real strings are the Unicode right arrow.)

## `SteamClient`

`actor SteamClient`; `static let apiBase = URL(string: "https://api.steampowered.com")!`; `init(session: URLSession = .shared)`. All requests add `format=json` and use a 20 s timeout.

### Public API

| Signature | Endpoint and parameters | Parser / mapping |
|---|---|---|
| `func resolveSteamID(_ input: SteamIDInput, key: String) async throws -> String` | `.steamID64`: returns the id with no request. `.vanity`: `GET ISteamUser/ResolveVanityURL/v1/` with `key`, `vanityurl`, `url_type=1` | `checkStatus`, then `parseVanity`: `success == 1` and a `steamid` present, else `vanityNotFound`. |
| `func playerSummary(steamID: String, key: String) async throws -> PlayerSummary` | `GET ISteamUser/GetPlayerSummaries/v2/` with `key`, `steamids` | `checkStatus`, `parseSummaries`: first player, else `profileNotFound`. |
| `func ownedGames(steamID: String, key: String) async throws -> [OwnedGame]` | `GET IPlayerService/GetOwnedGames/v1/` with `key`, `steamid`, `include_appinfo=1`, `include_played_free_games=1` | `checkStatus`, `parseOwnedGames`: when both `games` and `game_count` are absent the response is empty, which is how Steam signals a private game list, so it throws `gameDetailsPrivate`. A present `game_count: 0` returns `[]`. |
| `func achievements(appID: Int, steamID: String, key: String) async throws -> AchievementSummary` | `GET ISteamUserStats/GetPlayerAchievements/v1/` with `key`, `steamid`, `appid`, `l=english` | `parseAchievements(data, status:)`: parses the body *before* checking status because 400/403 bodies are JSON. `success: false` with "not public" in the error text gives `privateProfile`; "no stats" gives `noStats`; else `steam(message)`. Then `checkStatus`. Counts entries with `achieved == 1`. |
| `func storeAssets(appIDs: [Int]) async throws -> [Int: StoreAssets]` | `GET IStoreBrowseService/GetItems/v1/` with `input_json` (see below), chunks of 100 appIDs (de-duplicated and sorted) | Per chunk: `checkStatus`, `parseStoreItems` (items with `success == 1` and `assets`). Chunk failures are logged and skipped; only if *every* chunk fails does it throw the last error. |

`input_json` is built by the static `storeItemsInputJSON(appIDs:)`: `{"context":{"country_code":"US","language":"english"},"data_request":{"include_assets":true},"ids":[{"appid":N},...]}` with sorted keys.

### Networking and parsing helpers

| Signature | Behaviour |
|---|---|
| `private func get(_ path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse)` | Builds the URL, appends `format=json`. Maps `URLError` and anything else to `SteamError.network(localizedDescription)`; rethrows `SteamError` and `CancellationError` unchanged. |
| `static func storeItemsInputJSON(appIDs:) throws -> String` | See above. |
| `static func parseVanity/parseSummaries/parseOwnedGames/parseAchievements/parseStoreItems` | Pure, `Data` in, DTO out, as described in the table. A malformed envelope throws `SteamError.decoding("<TypeName>")` via the private generic `decode`. |
| `static func checkStatus(_ status: Int) throws` | 2xx fine; 401 and 403 give `invalidKey`; 429 gives `rateLimited`; anything else `http(status)`. |

## Isolation

`SteamClient` is an actor, so its mutable state (only the `URLSession` reference) is isolated; all result types are `Sendable` value types. The static parsers are nonisolated and can be called from tests without `await`.

## Gotchas

- The API key travels as a URL query parameter (`key=...`), as Steam requires. The code never logs a URL or key; the logger prints only `SteamError` descriptions, and the text shown to the user for network failures is the `URLError`'s localized description.
- A 403 on `GetPlayerAchievements` with a JSON body is *not* an invalid key; it is parsed first (private profile). An HTML 403 body falls through to `checkStatus` and becomes `invalidKey` (test `html403`).
- Steam's `GetOwnedGames` returns HTTP 200 with an empty `response` object for a private profile, so privacy is detected structurally.

## See also

[Steam](../architecture/steam.md), [App and state](../architecture/app-and-state.md).
