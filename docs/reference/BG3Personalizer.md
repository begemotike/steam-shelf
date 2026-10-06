# BG3Personalizer

Path: [`Sources/Personalizer/BG3Personalizer.swift`](../../Sources/Personalizer/BG3Personalizer.swift) (441 lines)

The Baldur's Gate 3 personalizer (Steam appID 1086940). It finds the game's `.lsv` save packages inside the user's Steam folder, reads `SaveInfo.json` from every save to build a *history* (one line per save, autosave runs collapsed, plus a block of figures the app counts so the model does not have to), and reads `Globals.lsf` from the most recent save for a *latest-save deep dive* (party, quests, dialog log, dice rolls). Text formatting is pure: it takes plain structs, so it is unit-testable without files. File reading and LSF extraction are at the bottom of the file.

## Depends on / used by

- Depends on: [LarianFormats](LarianFormats.md) (`LSPKPackage`, `LSF`, `LSFNode`), [GamePersonalizer](GamePersonalizer.md) (`GamePersonalizer`, `GameDigest`, `PersonalizerError`).
- Used by: [GamePersonalizer](GamePersonalizer.md) (`Personalizers.all`), [Tests](Tests.md) (`BG3PersonalizerTests`).

## Data types (all `Sendable, Equatable` value types)

| Type | Fields | Notes |
|---|---|---|
| `BG3Member` | `origin: String`, `mainClass?`, `subClass?`, `level?`, `xp?` | One party member from `SaveInfo.json`. `origin` is `"Generic"` for the hero and custom characters, a name like `"Gale"` for companions, and a string containing `_` (for example a summon id) for summons. |
| `BG3SaveInfo` | `saveName?`, `difficulty?`, `gameVersion?`, `currentLevel?`, `members` | `static func parse(_ data: Data) throws -> BG3SaveInfo`: reads keys `Save Name`, `Difficulty` (string or array joined with ", "), `Game Version`, `Current Level`, and `Active Party.Characters[]` (`Origin`, `Classes[0].Main/.Sub`, `Level`, `Experience Points (Total)`). Throws `corrupt("SaveInfo.json is not an object")` if the root is not a dictionary. |
| `BG3SaveRecord` | `modified: Date`, `hero`, `saveName`, `members` | One save as the history needs it. |
| `BG3Journal` | `categories`, `progress`, `dialogs`, `rolls` (+ nested `Roll`, `Dialog`, `Category`, `Progress`) | Sendable extract of the LSF journal. |

### `BG3SaveRecord` computed properties

| Property | Definition |
|---|---|
| `isAutosave` | `saveName.hasPrefix("AutoSave_")` |
| `playtime` | `"17h17m"` from `"... - 17h 17m ..."` (regex `(\d+)h (\d+)m`), else `nil` |
| `playtimeMinutes` | `h*60 + m` of the same match |
| `location` | `"Putrid Bog"` from `^(.+?) - \d+h \d+m` (nil for autosaves and free-form names) |
| `isPlayerNamed` | not an autosave, and the name is not exactly `"<Place> - 17h 23m"`: the player typed something |
| `companionNames` | member origins excluding `"Generic"`, names containing `_` (summons) and empty |
| `heroMember` | first `Generic` member |
| `classText` | `"L4 Ranger/BeastMaster"`-style text for the hero, or `"-"` |
| `partyText` | `"solo"` or `"with Gale, Karlach"`, a second `Generic` member listed as `custom character`, summons appended as `+quasit`, `+wolf`, `+raven` or `+summon` (de-duplicated) |

## `BG3Format` (enum, pure static functions)

| Member | Behaviour |
|---|---|
| `maxHistoryLines = 250` | Only the most recent 250 history lines are kept (with a note). |
| `stamp(_ date: Date, timeZone: TimeZone) -> String` | `yyyy-MM-dd HH:mm` in the given zone, `en_US_POSIX` locale. |
| `day(_:timeZone:)` | The date part of `stamp`. |
| `history(_ unsorted: [BG3SaveRecord], timeZone: TimeZone = .current) -> String` | Sorts by modification date; `"No saves."` if empty. Header lines: `Heroes: Name (n saves), ...` ordered by count; `First save: ...; last save: ...`; `Total saves: n`; `All clock times are in <zone id>, the zone the owner says the saves were played in.`; the reload note; `Columns: date | hero | save name | playtime | hero class | party`. Then, after an optional "(Showing only the most recent 250 lines.)", the **COUNTED FOR YOU** block (`patterns`) and `FULL LIST:`. Each list line is `stamp | hero | name | playtime or - | classText | partyText`. **Autosave collapsing**: a run of consecutive autosaves by the same hero on the same calendar day becomes one line `"N autosaves"` using the *last* autosave's time/class/party; a run of one is shown normally. |
| `patterns(_ records:timeZone:) -> [String]` | The counted facts; see the table below. |
| `skillNames`, `abilityNames` | Dictionaries of the game's numeric ids: skills 0 to 17 (Deception, Intimidation, Performance, Persuasion, Acrobatics, Sleight of Hand, Stealth, Arcana, History, Investigation, Nature, Religion, Athletics, Animal Handling, Insight, Medicine, Perception, Survival) and abilities 1 to 6 (Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma). |
| `rollName(skill:ability:) -> String` | Skill 18 is a raw ability check: `"<Ability> check"` or `"Raw ability check"`; otherwise the skill name or `"Skill <n>"`. |
| `latest(info:hero:saveName:journal:) -> String` | See "Latest save" below. |
| `fingerprint(saveCount:latest:) -> String` | `"<count>:<epoch seconds>"`. |

### The COUNTED FOR YOU patterns

All computed per hero (heroes in order of first appearance) unless noted. Each is a separate line:

| Pattern text (shape) | Rule |
|---|---|
| `Gap: <hero> went N days between "<a>" (<date>) and "<b>" (<date>)` with `; playtime advanced <span> across that gap` when both have playtime and it did not decrease | Consecutive saves of the same hero whose calendar days differ by 30 or more |
| `Reload: <hero> saved "<a>" at HH:mm on <date>, then "<b>" <span> of real time later with <span> less playtime.` | Consecutive saves where playtime *decreased* |
| `Saves by place for <hero>: Place n, ...` (top 5, ties by name) | Count of `location` per hero |
| `Party attendance for <hero> (out of N saves): Name n, ...` | Companions present per save (set per save) |
| `The quasit first appears in "<save>" (<date>) and is in k of <hero>'s N saves.` | Saves whose `partyText` contains `+quasit` |
| `Saves made between midnight and 5 a.m.: k of N. The latest in the night was "<save>" at HH:mm.` | Hour 0 to 4 in the chosen zone; "latest" is the largest minutes-past-midnight |
| `Save names the player typed themselves (k): "<name>" (<stamp>); ...` | `isPlayerNamed`, last 30 only |
| `Autosaves: k of N saves.` | Always present |

Spans are `"<h>h <m>m"` at 60 minutes or more, else `"<m> minutes"`.

### Latest save (`latest`)

Lines in order: `Save: "<name>" (hero: <hero>)`, `Difficulty`, `Game version`, `Current area`, one `Party member:` line per member (hero marked, extra `Generic` members shown as "custom character", class/sub, level, XP). If the journal is `nil`: `Journal unavailable.` and stop. Otherwise: `Completed quests (n): ...`; one `Quest category <name> (n): ...` line per other category (quests with the `HIDDEN_` prefix are hidden everywhere); `Open questlines (n): <quest> -> <objective>; ...` (objectives not ending `_COMPLETION`); `In-game days seen in the dialog log: lo to hi`; `Recent conversations, oldest first (in-game day): ...` (consecutive repeats merged into `name xN (day a-b)`, last 40 runs, `.lsj` suffix stripped); `Most frequent dialogs: name xN, ...` (top 5); and `Dice rolls (N total): <Name> p passed / f failed[ (passive)]; ...` sorted by roll count, active before passive, then name.

## `BG3Journal.extract(from:)`

`static func extract(from roots: [LSFNode]) -> BG3Journal?` reads the `Journal` root: `QuestCategories/QuestCategory` (`QuestID`, `CategoryID`); `Quests` descendants named `QuestsProgress` (`MapKey`, with the first descendant `Quest` that has an `ObjectiveID`); `DialogLogs/DialogLog` (`DLOG_FileName`, `DLOG_GameDay`) and each `DialogLogLine` descendant's roll fields (`RollSkill`, `RollAbility`, `RollIsPassive`, `RollIsSuccess`; lines with skill 19 and ability 0 are not rolls). Returns `nil` when there is no `Journal` root. It is the bridge from the non-Sendable `LSFNode` tree to Sendable values.

## `BG3Personalizer`

`struct BG3Personalizer: GamePersonalizer` with `appID = 1086940`, `displayName = "Baldur's Gate 3"`.

| Signature | Behaviour |
|---|---|
| `static func parseFolder(_ name: String) -> (hero: String, saveName: String)` | Folder names look like `<Hero>-<digits>__<Save Name>`; regex `^(.*)-(\d+)__(.*)$`; otherwise both are the whole name. |
| `func digest(steamRoot: URL, timeZone: TimeZone = .current) throws -> GameDigest?` | For every user folder under `<steamRoot>/userdata`, looks in `<user>/1086940/remote/_SAVE_Public/Savegames/Story/<folder>/` for `*.lsv` files, taking the file modification date as the save time. Returns `nil` if `userdata` is unreadable or nothing is found. Sorts by date. For each package: `LSPKPackage(url:)`, `data(for: "SaveInfo.json")`, `BG3SaveInfo.parse`; packages that cannot be read are *skipped*. Save name is `SaveInfo.json`'s "Save Name" falling back to the folder's suffix. If none were readable throws `corrupt("no readable saves")`. Then, for the *latest readable* save only, reads `Globals.lsf` and parses it with `keepOnly: ["Journal"]`; failure leaves `journal == nil` ("Journal unavailable."). Returns `GameDigest(history:latest:fingerprint:saveCount:)`. Synchronous; the caller runs it on a detached task inside `SteamFolderAccess.withAccess`. |

## Gotchas

- Clock times depend on `timeZone`: the same saves seen from Honolulu are not "after midnight". The digest states the zone it used.
- Only `SaveInfo.json` is read from historical saves (cheap); `Globals.lsf` (hundreds of thousands of nodes in a late game) is read once, for the latest save, and only the `Journal` subtree is materialised.
- The latest save is the latest *by file modification date* among readable packages, which can differ from the save with the highest playtime after a reload.
- `isPlayerNamed` is heuristic: a typed name that happens to match the game's own pattern is not counted.

## See also

[Personalizer](../architecture/personalizer.md), [AI writer](../architecture/ai-writer.md), [tools/bg3 references](tools-bg3.md), [Tests](Tests.md) (`LarianFixtures`), [Original spec](../history/PERSONALIZER-spec.md).
