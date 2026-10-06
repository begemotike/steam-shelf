# GamePersonalizer

Path: [`Sources/Personalizer/GamePersonalizer.swift`](../../Sources/Personalizer/GamePersonalizer.swift) (24 lines)

The seam that makes Shelf-Keeper notes game-specific. A `GamePersonalizer` knows one game: given the user's Steam folder it reads that game's local save files and returns a `GameDigest`, two plain-text halves (whole-history and latest-save deep dive) that go into the AI prompt, plus a fingerprint and save count. The registry `Personalizers` lists the available personalizers; today only Baldur's Gate 3 exists.

## Depends on / used by

- Depends on: Foundation.
- Used by: [BG3Personalizer](BG3Personalizer.md) (conforms), [AppModel](AppModel.md) (`writeNotes`, `dumpDigestIfRequested`), [OpenBoxView](OpenBoxView.md) (`showsNotesButton`), [SettingsView](SettingsView.md) ("Games with notes"), [ShelfKeeperAI](ShelfKeeperAI.md) (consumes `GameDigest`), [Tests](Tests.md).

## Types

### `PersonalizerError`

`enum PersonalizerError: Error, Equatable { noFolderAccess, noSaves, corrupt(String), unsupported(String) }`. `corrupt` carries a developer-facing reason that is *not* shown to the user (the UI copy for `corrupt` and `unsupported` is "The save files couldn't be read."; see `KeeperText.message(for:)`).

### `GameDigest`

`struct GameDigest: Sendable, Equatable`

| Field | Meaning |
|---|---|
| `history: String` | Whole-history section of the prompt (plain text). |
| `latest: String` | Deep dive on the most recent save (plain text). |
| `fingerprint: String` | Changes when there is something new to say; stored as `BackOfBoxContent.inputFingerprint`. For BG3: `"<saveCount>:<latest mtime epoch seconds>"`. |
| `saveCount: Int` | Number of readable saves. |

### `GamePersonalizer`

`protocol GamePersonalizer: Sendable`: `var appID: Int`, `var displayName: String`, and `func digest(steamRoot: URL, timeZone: TimeZone) throws -> GameDigest?`. Returns `nil` when no saves are found. **Synchronous; call off the main actor** (it does file I/O and decompression). `timeZone` is where the saves were played: file dates carry no zone, so using the Mac's current zone would shift every clock time when the Mac travels.

### `Personalizers`

`enum Personalizers { static let all: [any GamePersonalizer] = [BG3Personalizer()]; static func forApp(_ appID: Int) -> (any GamePersonalizer)? }`.

## Gotchas

- Adding a game means writing a conforming type and appending it to `all`; the Notes button, Settings list and `writeNotes` pick it up automatically.
- The prompt text is the same for all games (`ShelfKeeperAI` takes only `game` name and the two digest strings), so a new personalizer must produce text in the same two-section shape, including a "counted for you" figures block.

## See also

[Personalizer](../architecture/personalizer.md), [AI writer](../architecture/ai-writer.md).
