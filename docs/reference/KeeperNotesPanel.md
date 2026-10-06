# KeeperNotesPanel

Path: [`Sources/BackOfBox/KeeperNotesPanel.swift`](../../Sources/BackOfBox/KeeperNotesPanel.swift) (173 lines)

The Shelf-Keeper's notes panel: the same cream parchment and brass clip as `LabelEditorPanel`, 380 pt wide (the editor is 340), shown beside the open box. Its body is a function of `AppModel` state: a spinner while reading or writing, an error with Try Again, the stored notes, or the reason notes cannot be written yet with a button that fixes it.

## Depends on / used by

- Depends on: [AppModel](AppModel.md) (`keeperState`, `canWriteNotes`, `hasSaveAccess`, `aiReady`, `writeNotes`, `clearNotes`, `requestSaveAccess`), [BackOfBoxProvider](BackOfBoxProvider.md) (`BackOfBoxContent`), [Theme](Theme.md), [ArtGenerator](ArtGenerator.md) (`TextureLibrary`).
- Used by: [OpenBoxView](OpenBoxView.md) (shown when `model.isShowingNotes`).

## `KeeperNotesPanel`

`struct KeeperNotesPanel: View`, `let appID: Int`. State: `@State confirmClear`, environment `openSettings`.

| Property | Meaning |
|---|---|
| `entry` | The entry from `model.document` (re-read each evaluation). |
| `stored` | `entry.blurb` when it `isAIWritten` and has `detail` (a complete notes record), else `nil`. |
| `state` | `model.keeperState(for: appID)`. |

### Body by state (`content`)

| State | Shown |
|---|---|
| `.reading` | Spinner, "Reading your saves..." |
| `.writing` | Spinner, "Composing..." |
| `.failed(message)` | Message in label red; **Try Again**; **Keep Old Notes** (only if `stored != nil`) sets the state back to `.idle`. |
| `.idle` with `stored` | `notes(_:)`: tagline, observations each prefixed by a fleuron, a rule, "ON YOUR MOST RECENT SESSION" and the `detail` paragraph, in a selectable `ScrollView`. |
| `.idle`, no stored, `!canWriteNotes` | "Notes can only be written on your own shelf." |
| `.idle`, no save access | Explanation and **Grant Access...** (`requestSaveAccess`). |
| `.idle`, `!aiReady` | "Choose an AI service in Settings..." and **Open Settings**. |
| `.idle`, everything ready | "The Shelf-Keeper has not looked at this one yet." and **Write Notes**. |

### Footer

With stored notes in `.idle`: text `"Written <date>"` plus `" . N save(s) read"` (from `BackOfBoxContent.savesRead`); **Rewrite** and **Clear** (only when `canWriteNotes`; Clear asks `confirmationDialog("Clear these notes?")`, whose action calls `model.clearNotes`), **Done**. In every other state only **Done**.

Private helpers: `message(_:)`, `working(_:)`, `failure(_:)`, `notes(_:)`, `footerText(_:)`, `clip` (one line each).

## Gotchas

- Stored notes remain visible read-only on shelves where `canWriteNotes` is false (Rewrite/Clear hidden).
- `Keep Old Notes` only resets the transient `keeperState`; it does not modify the document.
- The panel is inside the open-box overlay, so it is shown only while `OpenBoxView.phase == .presented`.

## See also

[Open box](../architecture/open-box.md), [AI writer](../architecture/ai-writer.md), [Personalizer](../architecture/personalizer.md).
