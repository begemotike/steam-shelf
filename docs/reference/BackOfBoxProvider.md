# BackOfBoxProvider

Path: [`Sources/BackOfBox/BackOfBoxProvider.swift`](../../Sources/BackOfBox/BackOfBoxProvider.swift) (116 lines)

Defines what goes into the text on the back of a box and the local, template-based generator for it. `BackOfBoxContent` is the type stored on `ShelfEntry.blurb`; it carries either a template blurb (provider `local.v1`) or Shelf-Keeper notes (provider id starting `ai.` or `anthropic.`). `BackOfBoxContext` is the sanitised input to a provider. The planned `AIBackOfBoxProvider` seam from the original plan was not built as such: AI notes are written by [ShelfKeeperAI](ShelfKeeperAI.md) and stored directly by `AppModel.writeNotes`.

## Depends on / used by

- Depends on: [ShelfDocument](ShelfDocument.md) (`ShelfEntry`).
- Used by: [AppModel](AppModel.md) (`backOfBox`, `blurbIfNeeded`, `writeNotes`), [ShelfDocument](ShelfDocument.md) (field type), [BackOfBoxView](BackOfBoxView.md), [KeeperNotesPanel](KeeperNotesPanel.md), [OpenBoxView](OpenBoxView.md) (`isAIWritten`), [Tests](Tests.md).

## Types

### `StoreDetailsLite`

`struct StoreDetailsLite: Codable, Sendable, Equatable { genres: [String], developer: String?, releaseDate: String? }`. Reserved slot for store details (Q7); never populated (`BackOfBoxContext.storeDetails` is always `nil`).

### `BackOfBoxContext`

`struct BackOfBoxContext: Codable, Sendable, Equatable`

Fields: `appID`, `title`, `playtimeMinutes`, `lastPlayed`, `firstSeenAt`, `purchaseDate`, `achievementsEarned`, `achievementsTotal`, `rating`, `note`, `storeDetails`. `init(entry: ShelfEntry)` copies them from the entry.

| Member | Behaviour |
|---|---|
| `var playtimeBucket: Int` | 0 for 0 minutes or less; 1 for under 2 h; 2 for under 20 h; 3 for under 100 h; 4 for under 500 h; 5 otherwise. |
| `var fingerprint: String` | `"b<bucket>|a<earned>/<total>|r<rating>"` with `-` for nil. Deliberately excludes the note and the exact minutes so typing a note or playing a few more minutes never reshuffles the joke. |

### `BackOfBoxContent`

`struct BackOfBoxContent: Codable, Sendable, Equatable`

| Field | Notes |
|---|---|
| `blurb: String` | One line (template or AI, 160 chars asked of the model). |
| `tagline: String?` | Short title under the game name. |
| `providerID: String` | `"local.v1"`, `"anthropic.<model>"` (older notes) or `"ai.<provider>.<model>"`. |
| `inputFingerprint: String` | Template: context fingerprint. AI notes: `"<saveCount>:<latest mtime epoch>"`. |
| `generatedAt: Date` | Shown in the notes footer. |
| `observations: [String]?` | AI notes only; absent in older documents (decodes as nil). |
| `detail: String?` | AI notes only: the "playstyle" paragraph. |
| `var isAIWritten: Bool` | `providerID.hasPrefix("ai.") \|\| hasPrefix("anthropic.")`. Gates "never replace AI notes with the template" and the Notes UI. |
| `var savesRead: Int?` | For AI notes, the integer before the first `:` in `inputFingerprint`; shown as "N saves read". |

### `BackOfBoxProvider` and `LocalBackOfBoxProvider`

`protocol BackOfBoxProvider: Sendable { var providerID: String { get }; func content(for context: BackOfBoxContext) async throws -> BackOfBoxContent }`.

`struct LocalBackOfBoxProvider: BackOfBoxProvider`, `providerID = "local.v1"`. `variants` holds six buckets of two `(tagline, blurb)` jokes. `content(for:)` picks `options[abs(appID) % options.count]` (stable per game) and appends one extra sentence if the game has achievements: all earned ("Every achievement. Every. Single. One."), at least half ("Trophy case more than half full."), some ("A modest trophy shelf."), none ("Zero achievements. Pure vibes."). Returns a content with `providerID`, the context fingerprint and `Date()`.

## Gotchas

- The doc comment in the source points to `docs/PERSONALIZER.md`; that spec now lives at [history/PERSONALIZER-spec.md](../history/PERSONALIZER-spec.md).
- `BackOfBoxContext` and `BackOfBoxContent` are `Codable` because they are stored inside the document and a future provider could send the context off-device. The local provider sends nothing anywhere.

## See also

[App and state](../architecture/app-and-state.md), [Open box](../architecture/open-box.md), [AI writer](../architecture/ai-writer.md).
