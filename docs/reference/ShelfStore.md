# ShelfStore

Path: [`Sources/Persistence/ShelfStore.swift`](../../Sources/Persistence/ShelfStore.swift) (68 lines)

Where the `ShelfDocument` is stored. SwiftData holds each shelf as one JSON blob (`ShelfRecord.documentData`) instead of a table per game, so the `ShelfDocument` stays the real schema and the store only ever needs one model type. A small protocol, `ShelfSource`, hides whether the shelf is the local SwiftData record or an in-memory demo (and is the seam for future non-local sources).

## Depends on / used by

- Depends on: [ShelfDocument](ShelfDocument.md) (`ShelfDocumentCodec`), SwiftData.
- Used by: [SteamShelfApp](SteamShelfApp.md) (creates the container for `ShelfRecord`), [AppModel](AppModel.md) (`source`), [Tests](Tests.md).

## Types

| Type | Signature | Notes |
|---|---|---|
| `ShelfRecord` | `@Model final class ShelfRecord` | Fields: `@Attribute(.unique) shelfID: UUID`, `kindRaw: String` (`"local"`), `updatedAt: Date`, `documentData: Data`. Not isolated; only touched on the main context. |
| `ShelfSource` | `@MainActor protocol ShelfSource: AnyObject` | `sourceID: String`, `isEditable: Bool`, `func load() throws -> ShelfDocument?`, `func save(_ document: ShelfDocument) throws`. |
| `LocalShelfSource` | `@MainActor final class` | `sourceID == "local"`, `isEditable == true`. Uses `container.mainContext`. |
| `DemoShelfSource` | `@MainActor final class` | `sourceID == "demo"`, `isEditable == true`. Holds the document in a stored property only; `init(document: ShelfDocument? = nil)`. Saves never reach disk. |

### `LocalShelfSource`

| Member | Behaviour |
|---|---|
| `init(container: ModelContainer)` | Keeps `container.mainContext`. |
| `private func localRecord() throws -> ShelfRecord?` | Fetches with predicate `kindRaw == "local"`, `fetchLimit = 1`. |
| `func load() throws -> ShelfDocument?` | `nil` when there is no record; otherwise `ShelfDocumentCodec.decode(record.documentData)` (may throw `unsupportedVersion` or a decoding error). |
| `func save(_ document: ShelfDocument) throws` | Encodes, then updates the existing record (`shelfID`, `updatedAt`, `documentData`) or inserts a new one, then `context.save()`. |

### `DemoShelfSource`

`load()` returns `stored`; `save(_:)` replaces it. This is what makes "demo data is never saved" true.

## Gotchas

- There is exactly one local record; `kindRaw` exists so a future "peer" source could share the table.
- `AppModel.onLaunch` uses `try? source.load()`, so a decode failure looks like an empty shelf, and the next save overwrites the unreadable blob.
- Tests use `ModelConfiguration(isStoredInMemoryOnly: true)`; so does `.tests` launch mode.

## See also

[App and state](../architecture/app-and-state.md) (persistence section), [Open questions](../decisions/OPEN_QUESTIONS.md) (Q4: blob vs table).
