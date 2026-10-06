# ImageCache

Path: [`Sources/Images/ImageCache.swift`](../../Sources/Images/ImageCache.swift) (166 lines)

An actor that turns a `CoverRequest` (appID plus ordered candidate URLs) into a decoded cover image, using memory, then disk, then the network, with a persistent negative cache so games with no art are not retried every launch. Concurrent requests for the same app share one in-flight task. Images are downscaled to at most 1200 px on the long edge when decoded.

## Depends on / used by

- Depends on: [ArtGenerator](ArtGenerator.md) (`SendableImage`), ImageIO, OSLog.
- Used by: [AppModel](AppModel.md) (`images`), [ShelfView](ShelfView.md) (`CoverLoader.resolve`), [SettingsView](SettingsView.md) (`CoverThumb`).

## Types

| Type | Definition |
|---|---|
| `CoverRequest` | `struct: Sendable, Hashable { appID: Int, title: String, portraitURLs: [String], headerURL: String? }` |
| `CoverResult` | `enum: Sendable { portrait(SendableImage), header(SendableImage), none }` |
| `ImageCache` | `actor`; `init(fileManager: FileManager = .default, session: URLSession = .shared)` |

## `ImageCache` members

| Member | Behaviour |
|---|---|
| `func cover(for request: CoverRequest) async -> CoverResult` | Memory hit returns immediately. If a task is already in flight for the appID, awaits it. Otherwise starts `resolve`, stores the task in `inFlight`, awaits, clears it and `remember`s the result. Never throws. |
| `func clearMemory()` | Empties the in-memory dictionary (disk is untouched). Not currently called by the app. |
| `private func resolve(_:) async -> CoverResult` | Order: (1) disk: `<covers>/<appID>.jpg` as portrait, then `<appID>-header.jpg` as header; (2) if the appID has a recent entry in `misses` (within 7 days) return `.none`; (3) network: each portrait URL in order, writing the first success to `<appID>.jpg`; (4) the header URL, written to `<appID>-header.jpg`; (5) otherwise record a miss with `Date()`, persist `misses.json`, return `.none`. `Task.isCancelled` aborts without recording a miss. |
| `private func fetchImageData(_:) async -> Data?` | https only, 20 s timeout, requires HTTP 200 and an `image/*` MIME type; any failure returns `nil` (debug log of the file name). |
| `private func remember(_:for:)` | Memory cap 200 entries (evicts an arbitrary key). `.none` is not memoized. |
| `private static func decode(url:)`, `decode(data:)`, `image(from:)` | ImageIO; if either side exceeds `maxPixel` (1200) creates a thumbnail with transform; else the full image. |
| `private func coversDirectory()` | `<Caches>/SteamShelf/covers/`, created on demand. |
| `missesURL()`, `loadMissesIfNeeded()`, `saveMisses()` | `misses.json` is a `[String: Date]` (appID string to ISO-8601 date), loaded once per process. |

Constants: `missTTL = 7 days`, `memoryCap = 200`, `maxPixel = 1200`.

## Disk layout

```
~/Library/Caches/SteamShelf/covers/      (container path inside the sandbox)
  <appID>.jpg            portrait art (original bytes as downloaded)
  <appID>-header.jpg     landscape header art, used only if no portrait existed
  misses.json            { "<appID>": "<ISO date of last failed attempt>" }
```

Files are the *original* downloads; downscaling happens on every decode. The Caches directory can be purged by the system; everything here is re-fetchable. `AppModel.dumpDigestIfRequested` writes its digest files to the sibling `<Caches>/SteamShelf/`.

## Gotchas

- Disk is checked before the miss list, so a game that later gains art but has a fresh miss entry is still `.none` until the 7-day TTL lapses or the entry is cleared by a manual delete of `misses.json`. A previously cached portrait always wins over the TTL because disk comes first.
- A cached header means the portrait was missing at fetch time; a later portrait is never retried while the header file exists (disk hit returns `.header`).
- `inFlight` dedupe is keyed by appID only: two requests with different URL lists for the same app share the first's result.

## See also

[Steam](../architecture/steam.md), [Shelf rendering](../architecture/shelf-rendering.md).
