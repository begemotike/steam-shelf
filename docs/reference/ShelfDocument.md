# ShelfDocument

Path: [`Sources/Model/ShelfDocument.swift`](../../Sources/Model/ShelfDocument.swift) (155 lines)

`ShelfDocument` is the single schema of the app: everything the user has made (title, owner, which games are on the shelf, in what order, with what rating, note, purchase date, cached Steam stats, art references and any back-of-box text) is one `Codable` value. The same JSON is what SwiftData stores as a blob, what Export writes to a `.steamshelf` file and what a future peer-to-peer transport would send. The file also holds `ShelfDocumentCodec`, which fixes the date strategy and the version check.

## Depends on / used by

- Depends on: [BackOfBoxProvider](BackOfBoxProvider.md) (`BackOfBoxContent` is a field of `ShelfEntry`).
- Used by: [AppModel](AppModel.md), [ShelfStore](ShelfStore.md), [DemoData](DemoData.md), [BackOfBoxProvider](BackOfBoxProvider.md) (`BackOfBoxContext(entry:)`), [BackOfBoxView](BackOfBoxView.md), [KeeperNotesPanel](KeeperNotesPanel.md), [ShelfView](ShelfView.md), [OpenBoxView](OpenBoxView.md), [Tests](Tests.md).

## `ShelfDocument`

`struct ShelfDocument: Codable, Sendable, Equatable`

| Member | Signature | Notes |
|---|---|---|
| `currentVersion` | `static let currentVersion = 1` | The only schema version so far. |
| `version` | `var version: Int` | Defaults to `currentVersion`; `init(from:)` uses `decodeIfPresent` so a missing key reads as current. |
| `id`, `title`, `owner`, `createdAt`, `updatedAt` | `UUID`, `String`, `ShelfOwner`, `Date`, `Date` | `title` defaults to `"<persona>'s Shelf"` or `"My Shelf"`. |
| `entries` | `var entries: [ShelfEntry]` | *All* entries including unticked ones (`isShelved == false`). Array order is the custom arrangement. |
| `arrangement` | `var arrangement: Arrangement = .alphabetical` | `enum Arrangement: String { alphabetical, custom }`. Older documents lack the key and decode as alphabetical. |
| `shelvedEntries` | `var shelvedEntries: [ShelfEntry]` | `entries.filter(\.isShelved)`; the list the UI paginates. |
| `CodingKeys` | private | `version, id, title, owner, createdAt, updatedAt, entries, arrangement`. Unknown keys in a file are ignored by the default decoder. |
| `init(id:title:owner:createdAt:updatedAt:entries:arrangement:)` | memberwise-like | `arrangement` defaults to `.alphabetical`. |
| `init(from decoder:)` | custom | See `version` and `arrangement` above. |
| `forSharing() -> ShelfDocument` | | Copy whose `entries` are only the shelved ones. Used by export. Notes and ratings of unticked games are thus never shared. |
| `static func empty(owner:) -> ShelfDocument` | | New UUID, `now` timestamps, no entries. Title is `"My Shelf"` when the owner name is `"My Shelf"` or empty, else `"<name>'s Shelf"`. |
| `mutating func insertSorted(_:)` | | Inserts before the first existing entry whose title sorts after it using `localizedStandardCompare` (case-insensitive, numeric-aware). |
| `mutating func insert(_:)` | | By arrangement: sorted when alphabetical, appended when custom. |
| `@discardableResult mutating func move(appID:before:) -> Bool` | | Removes the entry and re-inserts it immediately before `targetAppID` (end when `nil` or the target is missing). Sets `arrangement = .custom`. Returns `false` if source equals target or the source does not exist. Note: moves operate on `entries` (including unshelved ones), so "before X" is relative to the full array. |
| `mutating func arrangeAlphabetically()` | | Sorts all entries by title (`localizedStandardCompare`) and sets `.alphabetical`. |

## Value types

| Type | Fields | Notes |
|---|---|---|
| `ShelfOwner` | `steamID64: String?`, `displayName: String`, `avatarURL: String?` | Display name feeds the shelf title and the back-of-box footer. |
| `ShelfEntry` (`Identifiable`, `id == appID`) | `appID`, `title`, `isShelved`, `rating: Int?` (1-5, nil = unrated), `note: String` (max 600 chars, enforced by the editor), `purchaseDate: Date?`, `firstSeenAt: Date`, `stats: CachedSteamStats`, `art: ArtRefs`, `blurb: BackOfBoxContent?` | `title` and `stats` are refreshed from Steam by `AppModel.mergeLibraryIntoEntries`; `rating`, `note`, `purchaseDate` and `blurb` are user/AI data and are never overwritten by refresh. |
| `CachedSteamStats` | `playtimeMinutes`, `lastPlayed`, `hasCommunityStats`, `achievementsEarned?`, `achievementsTotal?`, `achievementsState`, `fetchedAt?` | `fetchedAt` drives the 6 h achievements TTL. |
| `AchievementsState` | `unknown, none, privateProfile, ok` (raw `String`) | `unknown` renders as "Checking the trophy case..." on the label. |
| `ArtRefs` | `portraitURLs: [String]`, `headerURL: String?` | Candidate CDN URLs in preference order, produced by `CoverURLs`. Empty in demo. |
| `DocumentError` | `enum { unsupportedVersion(Int) }` | Thrown by the codec for documents newer than `currentVersion`. |

## `ShelfDocumentCodec`

`enum ShelfDocumentCodec` (static only)

| Function | Behaviour |
|---|---|
| `static func encode(_ doc: ShelfDocument) throws -> Data` | `JSONEncoder` with `.iso8601` dates and `[.prettyPrinted, .sortedKeys]` (stable diffs; readable files). |
| `static func decode(_ data: Data) throws -> ShelfDocument` | First decodes a private `VersionProbe { version }`; if `version > currentVersion` throws `DocumentError.unsupportedVersion(version)` *before* attempting the full decode, so a future shape yields a precise error instead of a decoding error. Then decodes with `.iso8601` dates. |

## Gotchas

- Dates are ISO-8601 *without fractional seconds*, so round trips truncate sub-second precision; tests compare documents built from whole-second dates.
- Adding a field that old builds must ignore is free (unknown keys are ignored). Anything that changes meaning (for example half-star ratings, `Int` 1-10) requires bumping `currentVersion` (see Q6 in [OPEN_QUESTIONS](../decisions/OPEN_QUESTIONS.md)).
- Local timestamps `createdAt`/`updatedAt` are on the document, not on SwiftData's `ShelfRecord`; `ShelfRecord.updatedAt` is a copy used for fetching.

## See also

[App and state](../architecture/app-and-state.md), [Overview](../architecture/overview.md).
