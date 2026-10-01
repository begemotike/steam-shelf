# Shelf-Keeper notes: per-game personalizers (first: Baldur's Gate 3)

Goal: for a game that has a *personalizer*, the opened box gets a **Notes** button. It reads that game's local save
data, sends a compact digest to an AI, and shows (a) several funny observations drawn from the whole save history and
(b) a deeper read of the most recent save about the player's playstyle. A one-line version goes on the back of the box.

Reference implementations (Python, verified against 118 real saves): `tools/bg3/lspk.py`, `tools/bg3/lsf.py`.
Synthetic fixtures (no real save data): `Tests/LarianFixtures.swift`. **Never commit real save data or digests.**

## 1. Access and keys

### 1.1 Steam folder grant — `Sources/Personalizer/SteamFolderAccess.swift`
Saves live under `~/Library/Application Support/Steam/userdata/<id>/<appid>/remote/…`, outside the sandbox.
- `@MainActor enum SteamFolderAccess` with:
  - `static var isGranted: Bool` (a bookmark exists and resolves).
  - `static func requestAccess() -> Bool`: `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`,
    `directoryURL` = the real-home Steam folder — use `getpwuid(getuid())`, as `SteamInstalls.steamappsDirectory` does —
    `prompt = "Grant Access"`, `message = "Steam Shelf reads your save files here to write notes about your games. Choose the Steam folder."`).
    Accept only a folder that contains `userdata` (else show an alert and return false). Create a bookmark with
    `[.withSecurityScope, .securityScopeAllowOnlyReadAccess]` and store it in `UserDefaults` key `steamFolderBookmark`.
  - `static func revoke()`.
  - `nonisolated static func withAccess<T>(_ body: (URL) throws -> T) throws -> T`: resolve the bookmark (refresh if stale),
    `startAccessingSecurityScopedResource`, run, always `stopAccessing…`. Throws `PersonalizerError.noFolderAccess` when absent.
- The bookmark goes in **UserDefaults, not the Keychain**: it is not a secret (it is only usable by this app), this is
  Apple's documented pattern, and Keychain reads are what caused the password prompts.
- Entitlement to add in `project.yml`: `com.apple.security.files.bookmarks.app-scope: true`.

### 1.2 Anthropic API key
Keychain account `anthropic-api-key` via the existing `Keychain` enum; mirror a `hasAIKey` bool in UserDefaults (same
pattern as the Steam key, so launch never touches the Keychain). `AppModel.saveAIKey(_:)`, `forgetAIKey()`.

### 1.3 Settings UI
Turn the Settings window into a `TabView` with two tabs: **Library** (everything that exists today, unchanged) and
**Shelf-Keeper**. The new tab (a grouped `Form`, fields with `.textFieldStyle(.roundedBorder)` like the Library tab):
- *Save file access*: "Granted ✓" + `Revoke`, or `Grant Access…`.
- *Anthropic API key*: `SecureField` + `Save` (Return submits), or "•••• Saved in Keychain" + `Forget`.
  Link: "Get a key at console.anthropic.com".
- Footnote, always visible: "When you ask for notes on a game, a summary of that game's save files (save names, dates,
  party, quests and recent conversations) is sent to Anthropic's API using your key. Nothing is sent until you press
  Write Notes."
- *Games with notes*: a plain list of `Personalizers.all` display names (just "Baldur's Gate 3" for now).

## 2. Larian formats — `Sources/Personalizer/LarianFormats.swift`
Pure Swift, `Sendable`, no UI. Port the Python references exactly.

### 2.1 LZ4 (no Compression.framework — it cannot do linked frame blocks)
- `enum LZ4 { static func decodeBlock(_ src: Data, into dst: inout [UInt8], maxOutput: Int) throws }`: standard LZ4 block
  decoding that **appends to `dst`** and resolves match offsets against everything already in `dst` (this is what makes
  linked frame blocks work). Validate every offset/length; throw `PersonalizerError.corrupt` rather than trapping.
- `static func decodeFrame(_ src: Data) throws -> [UInt8]`: magic `0x184D2204`; FLG (version bits 01; bit5 block
  independence; bit4 block checksum; bit3 content size; bit2 content checksum; bit0 dictID), BD, optional 8-byte content
  size, optional 4-byte dict id, 1 header checksum byte; then blocks: `u32 size` (0 = end mark; high bit set = stored
  uncompressed), data, optional 4-byte block checksum; optional 4-byte content checksum. Feed every block into the same
  growing `dst`.

### 2.2 zstd
Add SwiftPM package `https://github.com/facebook/zstd` (from `1.5.7`, product `libzstd`) to `project.yml` and the app
target. Wrap `ZSTD_decompress` in `enum Zstd { static func decompress(_ data: Data, uncompressedSize: Int) throws -> Data }`
(check `ZSTD_isError`). If the product/module name differs in that Package.swift, use what it actually declares.

### 2.3 LSPK v18 (`.lsv` save package) — see `tools/bg3/lspk.py`
`struct LSPKPackage { init(url: URL) throws; var names: [String]; func data(for name: String) throws -> Data }`
- Use `FileHandle` + `seek`; **never read a whole .lsv** (they are ~17 MB each and there can be hundreds).
- Header (40 bytes): `"LSPK"`, `u32 version` (accept 15…18 layout as v18; throw `unsupported` otherwise is fine),
  `u64 fileListOffset`, `u32 fileListSize`, `u8 flags`, `u8 priority`, 16-byte MD5, `u16 numParts`.
- At `fileListOffset`: `u32 numFiles`, `u32 compressedSize`, then an **LZ4 block** that decodes to `numFiles × 272` bytes.
- Entry (272 bytes): name `[256]` NUL-terminated UTF-8, `u32 offsetLow`, `u16 offsetHigh`, `u8 archivePart`, `u8 flags`
  (low nibble = method: 0 stored, 1 zlib, 2 LZ4 block, 3 zstd), `u32 sizeOnDisk`, `u32 uncompressedSize`.
  Stored entries have `uncompressedSize == 0`. zlib may throw `unsupported` (not used by BG3 saves).

### 2.4 LSF (binary tree) — see `tools/bg3/lsf.py`
`final class LSFNode { let name: String; var attributes: [String: LSFValue]; var children: [LSFNode] }`,
`enum LSFValue: Sendable, Equatable { case string(String), int(Int64), double(Double), bool(Bool), other }`,
`enum LSF { static func parse(_ data: Data, keepOnly rootNames: Set<String>? = nil) throws -> [LSFNode] }`.
- Header: `"LSOF"`, `u32 version` (5…7), engine version (`i64` when version ≥ 5, else `i32`).
- Sizes: version ≥ 6 → ten `u32`: strings(unc, disk), keys(unc, disk), nodes(unc, disk), attributes(unc, disk),
  values(unc, disk). Version 5 → eight (no keys pair). Then `u8 compression` (low nibble: 0 none, 2 LZ4, 3 zstd), `u8`,
  `u16`, `u32 metadataFormat` (1 = long 16-byte nodes/attributes, otherwise short 12-byte).
- A section with `disk == 0 && unc > 0` is stored raw (`unc` bytes). Otherwise read `disk` bytes and decompress:
  the **strings section is an LZ4 block**; keys/nodes/attributes/values are **LZ4 frames** (zstd: plain zstd for all).
- Strings: `u32 bucketCount`; per bucket `u16 count`; per string `u16 length` + UTF-8. Name index = `(bucket << 16) | index`.
- Short nodes (12): `u32 nameIndex, i32 firstAttribute, i32 parent`. Long nodes (16): `u32 nameIndex, i32 parent, i32 nextSibling, i32 firstAttribute`.
- Short attributes (12): `u32 nameIndex, u32 typeAndLength (type = low 6 bits, length = >> 6), i32 nodeIndex`; value
  offsets are the running sum of lengths; a node's attributes are those with its node index, in file order.
  Long attributes (16): `u32 nameIndex, u32 typeAndLength, i32 nextAttribute, u32 offset`.
- Value types needed: 1 `u8`, 2 `i16`, 3 `u16`, 4 `i32`, 5 `u32`, 6 `f32`, 7 `f64`, 19 `bool`, 20–23 & 29–30 NUL-terminated
  UTF-8 string, 24 `u64`, 26/32 `i64`, 27 `i8`; everything else → `.other`.
- `keepOnly`: when given, still build the whole node table (parents are needed) but only **decode attribute values**
  for nodes inside a kept root's subtree. Globals.lsf has ~300k nodes and ~13 MB of values; we need only `Journal`.
- Bounds-check everything; throw `PersonalizerError.corrupt`, never trap.

## 3. Personalizer layer — `Sources/Personalizer/GamePersonalizer.swift`
```swift
struct GameDigest: Sendable, Equatable {
    var history: String        // whole-history section of the prompt (plain text)
    var latest: String         // deep dive on the most recent save (plain text)
    var fingerprint: String    // changes when there is something new to say
    var saveCount: Int
}
protocol GamePersonalizer: Sendable {
    var appID: Int { get }
    var displayName: String { get }
    func digest(steamRoot: URL) throws -> GameDigest?   // nil = no saves found
}
enum Personalizers {
    static let all: [any GamePersonalizer] = [BG3Personalizer()]
    static func forApp(_ appID: Int) -> (any GamePersonalizer)?
}
enum PersonalizerError: Error, Equatable { case noFolderAccess, noSaves, corrupt(String), unsupported(String) }
```

## 4. Baldur's Gate 3 — `Sources/Personalizer/BG3Personalizer.swift` (appID 1086940)
Saves: `<steamRoot>/userdata/*/1086940/remote/_SAVE_Public/Savegames/Story/<folder>/<name>.lsv` (scan every user id).
Folder name is `<Hero>-<digits>__<Save Name>`. Save names made by the game look like `Putrid Bog - 17h 23m`; players
append or replace text (`Goblin Camp CLEARED BABY - 26h 12m`, `killed ethel outside`). Autosaves are `AutoSave_<n>`.

### 4.1 History (every save; read **only** `SaveInfo.json` from each package)
Sort by file modification date. One line per save:
`2024-02-05 21:40 | Corth | "Putrid Bog - 17h 17m new attempt" | 17h17m | L4 Ranger/BeastMaster | with Gale, Karlach, Shadowheart +quasit`
- Playtime parsed from `(\d+)h (\d+)m` in the name when present.
- Party from `Active Party.Characters`: the first character with `Origin == "Generic"` is the hero (class from
  `Classes[0].Main/Sub`, `Level`); companions are origins that are plain names (`Gale`, `Karlach`, `Shadowheart`,
  `Laezel`, `Astarion`, `Wyll`, `Halsin`, `Minthara`, `Jaheira`, `Minsc`, other `Generic`s → "custom character");
  origins containing `_` are summons/followers → append as `+quasit` (QuasitSummon), `+wolf`, `+raven`, else `+summon`.
- Collapse runs of consecutive autosaves by the same hero on the same day into one line: `… | Corth | 5 autosaves | …`.
- Header lines before the list: hero names with save counts, first and last save dates, total saves, and
  "Note: a lower playtime than the previous save by the same hero means the player reloaded an earlier save."
- Cap the list at 250 lines (keep the most recent).

### 4.2 Latest save deep dive (most recently modified .lsv)
From `SaveInfo.json`: difficulty, game version, each party member's class/subclass/level/XP.
From `Globals.lsf` (`LSF.parse(…, keepOnly: ["Journal"])`):
- `Journal/QuestCategories/QuestCategory{QuestID, CategoryID}` → "Completed quests (N): …" and other categories.
- `Journal/Quests/Quests/QuestsProgress{MapKey}` → first descendant `Quest{ObjectiveID}`; list open questlines as
  `Quest → current objective` for objectives not ending in `_COMPLETION` and quests not starting with `HIDDEN_`.
- `Journal/DialogLogs/DialogLog{DLOG_FileName, DLOG_GameDay}` in file order → "Recent conversations, oldest first
  (in-game day): …" with `.lsj` stripped; collapse consecutive repeats as `GLO_SpeakWithDead_Generic ×4`. Also a
  frequency line of the five most common dialog files.
- Dice: every `DialogLogLine` where `RollSkill != 19 || RollAbility != 0` is a roll. Tally by skill and by
  success/failure, active vs passive. Skill ids: 0 Deception, 1 Intimidation, 2 Performance, 3 Persuasion,
  4 Acrobatics, 5 Sleight of Hand, 6 Stealth, 7 Arcana, 8 History, 9 Investigation, 10 Nature, 11 Religion,
  12 Athletics, 13 Animal Handling, 14 Insight, 15 Medicine, 16 Perception, 17 Survival, 18 = raw ability check
  (name it by ability). Ability ids: 1 Strength, 2 Dexterity, 3 Constitution, 4 Intelligence, 5 Wisdom, 6 Charisma.
- In-game day range seen in the dialog log.
Quest/dialog IDs are Larian's internal names (`DEN_IdolTheft`, `UND_MyconidSovereign`); pass them through unchanged —
the model reads them fine. If `Globals.lsf` fails to parse, keep the SaveInfo part and add "Journal unavailable."
`fingerprint` = `"<saveCount>:<latest mtime epoch>"`.

Everything in §4 is pure once given file contents: structure it so the text formatting takes plain structs and is
unit-testable without files.

## 5. AI — `Sources/Personalizer/ShelfKeeperAI.swift`
`actor ShelfKeeperAI { func notes(game: String, digest: GameDigest, key: String) async throws -> KeeperNotes }`
```swift
struct KeeperNotes: Codable, Sendable, Equatable {
    var tagline: String        // ≤ 6 words, for the back of the box under the title
    var blurb: String          // ≤ 160 characters, one line for the back of the box
    var observations: [String] // 4–6, each ≤ 35 words, from the whole history
    var playstyle: String      // 2–3 sentences about the most recent save
}
```
Raw HTTP with `URLSession` (there is no official Swift SDK). Exactly this request:
- `POST https://api.anthropic.com/v1/messages`
- Headers: `content-type: application/json`, `x-api-key: <key>`, `anthropic-version: 2023-06-01`,
  `anthropic-beta: server-side-fallback-2026-07-01`
- Body:
```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 16000,
  "fallbacks": "default",
  "output_config": {
    "effort": "medium",
    "format": { "type": "json_schema", "schema": {
      "type": "object", "additionalProperties": false,
      "required": ["tagline", "blurb", "observations", "playstyle"],
      "properties": {
        "tagline": {"type": "string"}, "blurb": {"type": "string"},
        "observations": {"type": "array", "items": {"type": "string"}},
        "playstyle": {"type": "string"} } } }
  },
  "system": "<system prompt below>",
  "messages": [{"role": "user", "content": "<user prompt below>"}]
}
```
- Do **not** send `thinking`, `temperature`, `top_p` or `top_k` (this model rejects them or runs adaptive by default).
- Timeout 180 s. Response: check `stop_reason` first — `"refusal"` → `KeeperError.refused`; `"max_tokens"` →
  `KeeperError.truncated`. Otherwise concatenate the `text` of every content block with `type == "text"` (skip
  `thinking`, `fallback` and any other block types) and decode it as `KeeperNotes`. Trim, drop empty observations.
- HTTP errors: 401 → `.invalidKey`, 429 → `.rateLimited`, 529/5xx → `.overloaded`, others → `.http(status, message)`
  where `message` is `error.message` from the JSON error body when present. `URLError` → `.network`.
  `KeeperError.userMessage` gives one friendly sentence for each. **Never log the key.**
- Pure, unit-tested helpers: `static func requestBody(game:digest:) throws -> Data` and
  `static func parse(_ data: Data, status: Int) throws -> KeeperNotes`.

System prompt (verbatim):
> You are the Shelf-Keeper, the dry, fond curator of a collector's wooden game shelf. You have been handed a log
> extracted from the owner's own save files for one game, and you write the little notes that go with the box.
> Be funny the way a friend who has watched them play is funny: specific, observant, affectionate, never mean.
> Every claim must come from the log; quote save names, dates, playtimes and counts exactly and do not invent
> events. The log uses the game's internal quest and dialogue names; translate them into what a player would
> recognise, and do not reveal story beyond what the log shows the player has already reached. Plain text only:
> no markdown, no emoji, no lists inside a field.

User prompt:
```
Game: <displayName>

== SAVE HISTORY ==
<digest.history>

== MOST RECENT SAVE ==
<digest.latest>

Write:
- tagline: six words or fewer, for under the title on the back of the box.
- blurb: one sentence, 160 characters or fewer, the single best observation, for the back of the box.
- observations: four to six observations drawn from the whole save history. One or two sentences each. Look for
  patterns over time: long gaps, reloads (playtime going backwards), save names the player typed themselves,
  late-night sessions, who is always or never in the party.
- playstyle: two or three sentences about how this person plays, based on the most recent save's quests,
  conversations and dice rolls.
```

## 6. Model and state
- `BackOfBoxContent` gains two optional fields (older documents must still decode; add a round-trip test):
  `var observations: [String]?` and `var detail: String?` (the playstyle paragraph).
- AI notes are stored as the entry's `blurb`: `BackOfBoxContent(blurb: notes.blurb, tagline: notes.tagline,
  providerID: "anthropic.claude-opus-5-5", inputFingerprint: digest.fingerprint, generatedAt: now,
  observations: notes.observations, detail: notes.playstyle)`. They travel with exported/shared shelves.
- `AppModel.blurbIfNeeded` must **not** replace content whose `providerID` starts with `"anthropic."`.
- `AppModel`: `enum KeeperState: Equatable { case idle, reading, writing, failed(String) }`,
  `var keeperState: [Int: KeeperState]`, `var hasAIKey: Bool`, `var hasSaveAccess: Bool`,
  `func writeNotes(for appID: Int) async`: (1) `reading` — run the personalizer **off the main actor**
  (`Task.detached` inside `SteamFolderAccess.withAccess`); (2) `writing` — call the AI; (3) store and save.
  `func clearNotes(for appID:)` returns the entry to the local template blurb.
  Demo mode and non-local shelves: Notes are read-only (show stored notes if any; no button to write).

## 7. UI — the Notes panel
- `OpenBoxView` toolbar gets a brass **Notes** button (between Edit Label and Close) when
  `Personalizers.forApp(appID) != nil` or the entry already has stored observations.
- It opens `KeeperNotesPanel` (new file `Sources/BackOfBox/KeeperNotesPanel.swift`) in the same slot and style as
  `LabelEditorPanel` (cream parchment, brass clip, slides from the trailing edge, confined to the bay). The two panels
  are mutually exclusive; opening Notes also turns the box to its back (`motion.showBack()`).
- Panel content, top to bottom: title "The Shelf-Keeper's Notes" (Baskerville bold), game title; then by state:
  - no save access → one sentence + `Grant Access…` (calls `SteamFolderAccess.requestAccess()`).
  - no API key → one sentence + `Open Settings`.
  - has notes → tagline (italic), **Observations** as separate paragraphs each led by a small `labelRed` ❦ glyph,
    a thin rule, heading "ON YOUR MOST RECENT SESSION" (small caps, `labelRed`), the playstyle paragraph, then a
    footer "Written <date> · <n> saves read" and buttons `Rewrite` and `Clear`.
  - no notes yet → one sentence ("The Shelf-Keeper has not looked at this one yet.") + `Write Notes`.
  - `reading` → spinner + "Reading your saves…"; `writing` → spinner + "Composing…"; `failed(msg)` → the message
    in `labelRed` + `Try Again`.
  - Scrollable (`ScrollView`) when the text is long. Text is selectable.
- The back-of-box label needs no layout change: it already renders `blurb` and `tagline`. Verify a 160-character
  blurb fits its "FROM THE SHELF-KEEPER" block (allow up to 3 lines with `minimumScaleFactor(0.85)`).

## 8. Debug affordance
Launch argument `--dump-digest <appid>`: after launch, if save access is granted, compute the digest and write it to
`<Caches>/SteamShelf/digest-<appid>.txt`, log the path with `Logger`, and continue normally. No AI call. This is how
the reviewer checks the Swift port against the Python reference on real saves. Debug builds only (`#if DEBUG`).

## 9. Tests (all offline, using `Tests/LarianFixtures.swift`) — new file `Tests/PersonalizerTests.swift`
- LZ4 block vector decodes to `lz4BlockExpected`; corrupt input throws instead of crashing (truncate the vector).
- `LSF.parse` on the plain and the LZ4 fixture give the same tree: roots `Waypoints`, `Journal`; Journal children
  `QuestCategories`, `Quests`, `DialogLogs`; 4 `DialogLog`s; the second `DialogLogLine` overall has
  `RollAbility 6, RollSkill 3, RollIsSuccess true`.
- `LSPKPackage` on the `.lsv` fixture (write it to a temp file): names `meta.lsf`, `SaveInfo.json`, `Globals.lsf`;
  `SaveInfo.json` decodes with save name `Goblin Camp CLEARED - 26h 12m`; `Globals.lsf` parses.
- BG3 digest from the fixture package: history line contains `Goblin Camp CLEARED - 26h 12m`, `26h12m`,
  `L5 Ranger/BeastMaster`, `Gale`, `+quasit`; latest lists `DEN_Conflict` and `DEN_IdolTheft` as completed,
  `UND_MyconidRevenge → UND_MyconidRevenge_KillNere` as open, hides `HIDDEN_WLD_Rewards`, shows
  `GLO_SpeakWithDead_Generic ×2`, and a dice tally with Persuasion 1 passed / 1 failed, Insight 1 passed (passive),
  Strength check 1 passed.
- Autosave collapsing and the reload note with hand-built save records.
- `ShelfKeeperAI.requestBody` contains model `claude-opus-5-5`, `"fallbacks":"default"`, the schema, and no
  `thinking`/`temperature`; `parse` handles: a normal response with a `thinking` block before the `text` block;
  `stop_reason: "refusal"`; status 401 with an error body; malformed JSON text.
- `BackOfBoxContent` without the new fields still decodes; with them round-trips.
