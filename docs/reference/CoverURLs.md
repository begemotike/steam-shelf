# CoverURLs

Path: [`Sources/Steam/CoverURLs.swift`](../../Sources/Steam/CoverURLs.swift) (37 lines)

Builds the candidate image URLs for a game's cover on Steam's CDN. Steam serves art from two kinds of path: *hashed* paths built from the `asset_url_format` template and per-asset file names returned by `IStoreBrowseService/GetItems`, and *unhashed* legacy paths keyed only by appID. Hashed paths are tried first because they exist for games whose art uses hashed names; the unhashed path is the last resort for everyone.

## Depends on / used by

- Depends on: [SteamModels](SteamModels.md) (`StoreAssets`).
- Used by: [AppModel](AppModel.md) (`artRefs`), [SettingsView](SettingsView.md) (`CoverThumb`), [Tests](Tests.md) (`CoverURLTests`).

## `CoverURLs`

`enum CoverURLs` (static, pure)

| Member | Behaviour |
|---|---|
| `assetBase` | `"https://shared.akamai.steamstatic.com/store_item_assets/"` |
| `assetURL(format:asset:) -> String` | `assetBase + format` with the literal token `${FILENAME}` replaced by the asset name. The format carries the app path and a cache-busting query (for example `steam/apps/<id>/${FILENAME}?t=<ts>`); the per-asset file names returned by Steam carry the hash directory (for example `<hash>/library_600x900_2x.jpg`), so the result looks like `steam/apps/<id>/<hash>/library_600x900_2x.jpg?t=<ts>`. |
| `unhashedPortrait2x(appID:) -> String` | `<assetBase>steam/apps/<id>/library_600x900_2x.jpg` |
| `unhashedHeader(appID:) -> String` | `<assetBase>steam/apps/<id>/header.jpg` |
| `portraitCandidates(appID:assets:) -> [String]` | Ordered, de-duplicated: hashed `library_capsule_2x` (when `assets` has a format), hashed `library_capsule` (1x), then the unhashed 2x. With `assets == nil` or without a format, just the unhashed 2x. |
| `header(appID:assets:) -> String` | Hashed header when format and `header` name exist, otherwise the unhashed header. |

## Gotchas

- Because candidates are tried in order by `ImageCache` and the first successful download is written to disk, a hashed 1x capsule can win over the unhashed 2x if the hashed 2x is missing.
- URLs are produced at refresh time and stored on `ShelfEntry.art`, so a refresh updates art references for existing entries (`mergeLibraryIntoEntries`).

## See also

[Steam](../architecture/steam.md).
