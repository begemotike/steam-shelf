# DemoData

Path: [`Sources/Demo/DemoData.swift`](../../Sources/Demo/DemoData.swift) (82 lines)

Deterministic fake data for the demo shelf: 50 imaginary game titles (appIDs 900001 to 900050), of which the first 40 are shelved. It lets a friend or a reviewer see the whole app, including a 3-page shelf, without a Steam account. A seeded `SplitMix64` generator (seed 42) fixes playtime, achievements, ratings, notes and dates relative to a `now`, so the shelf looks the same on every launch. Demo data is never persisted.

## Depends on / used by

- Depends on: [ShelfDocument](ShelfDocument.md), [LibraryStore](LibraryStore.md) (`OwnedLibraryCache`), [SteamModels](SteamModels.md) (`OwnedGame`), [ArtGenerator](ArtGenerator.md) (`SplitMix64`).
- Used by: [AppModel](AppModel.md) (`startDemo()`), [Tests](Tests.md) (`testAppModelTestsModeAndDemoToggle`: 40 shelved, 3 pages, 50 library games).

## `DemoData`

`enum DemoData` (static only)

| Member | Detail |
|---|---|
| `steamID` | `"76561190000000000"`, a placeholder SteamID64 used only as the owner id of demo data. |
| `titles` | 50 invented titles (Alaska and IT jokes). |
| `private static let notes` | Eight short sample notes; each game has a 40% chance of one. |
| `private static func games(now:) -> (games: [OwnedGame], entries: [ShelfEntry])` | For game *i*: appID `900001 + i`; 30% chance of zero minutes, otherwise `pow(u, 3) * 60000` minutes; achievement total from `[0, 12, 30, 50, 77]`; earned is 0 for unplayed, else random up to total; rating 1-5 with 60% probability; note 40%; purchase date 30% (30 to 1500 days ago); last played 1 to 900 days ago when played; first seen 10 to 1200 days ago. Entries have `isShelved = i < 40`, empty `ArtRefs`, no blurb, `achievementsState` `.ok` or `.none`. |
| `static func library(now: Date = .now) -> OwnedLibraryCache` | Library cache over the 50 games with `firstSeen` from entries and no assets. |
| `static func document(now: Date = .now) -> ShelfDocument` | Fixed UUID `00000000-0000-4000-8000-000000000042`, title `"Demo Shelf"`, owner `Demo`; the 40 shelved entries inserted with `insertSorted` (alphabetical). |

## Gotchas

- Time-dependent values (dates, `fetchedAt`) shift with `now`; the *random choices* are fixed by the seed. Calling `document` and `library` separately re-runs `games(now:)` with slightly different `now` values, so dates can differ by milliseconds between the two (immaterial).
- Demo entries have no art URLs, so `CoverLoader` renders procedural placeholder covers; `CoverLoader.resolve` also skips the network when `model.isDemo`.

## See also

[App and state](../architecture/app-and-state.md) (launch modes), [Overview](../architecture/overview.md).
