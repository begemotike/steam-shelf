# SettingsView

Path: [`Sources/Views/SettingsView.swift`](../../Sources/Views/SettingsView.swift) (457 lines)

The Settings window (Cmd-comma), 640 x 760 pt, two tabs. **Library**: Steam Web API key, SteamID or profile URL, Connect, status, the checklist of owned games with search, filter and sort, and refresh buttons. **Shelf-Keeper**: Steam folder access, the save time zone, the AI service/key/model, and the list of games that support notes. The window uses standard SwiftUI form chrome with a brass tint and a wooden header strip.

## Depends on / used by

- Depends on: [AppModel](AppModel.md), [SteamIDInput](SteamIDInput.md), [AIProvider](AIProvider.md) (`AIProviders.all`), [GamePersonalizer](GamePersonalizer.md) (`Personalizers.all`), [ImageCache](ImageCache.md) and [CoverURLs](CoverURLs.md) (cover thumbnails), [ArtGenerator](ArtGenerator.md) (`TextureLibrary`, `CoverPalette`), [Theme](Theme.md).
- Used by: [SteamShelfApp](SteamShelfApp.md) (`Settings` scene). `AccountSection`, `LibraryChecklist` and `GameRow` are internal and unit-test-visible but only used here.

## Types

| Type | Visibility | Role |
|---|---|---|
| `SettingsView` | internal | `TabView` with `LibrarySettingsTab` ("Library", `books.vertical`) and `ShelfKeeperSettingsTab` ("Shelf-Keeper", `text.book.closed`); frame 640 x 760; tint brass; `.task` prepares textures (not in tests mode). |
| `LibrarySettingsTab` | private | `SettingsHeader`, a `DemoBanner` if demo, `AccountSection`, divider, `LibraryChecklist`. |
| `ShelfKeeperSettingsTab` | private | The `Form` described below. |
| `SettingsHeader` | private | 64-pt wooden strip with a brass "Steam Shelf Settings" plate. |
| `DemoBanner` | private | Cream banner "Demo shelf - 40 imaginary games..." and **Leave Demo** (`model.leaveDemo()`). |
| `AccountSection` | internal | Steam account form. |
| `StatusRow` | private | Loading spinner, failure message with a "Help" disclosure (privacy instructions), or persona avatar/name and "N games . refreshed <relative>". |
| `GameFilter`, `GameSort` | private enums | `All/Played/On Shelf`; `Name/Hours Played/Last Played`. |
| `LibraryChecklist` | internal | Searchable list of owned games. |
| `GameRow` | internal | One checkbox row. |
| `CoverThumb` | private | 24 x 36 cover thumbnail. |

## `AccountSection`

`@Bindable model`; `@State keyDraft`. If `hasAPIKey`: "Saved in Keychain" and **Forget**. Otherwise a `SecureField` ("32-character key") with **Save** (disabled for empty draft or non-normal mode; clears the draft after saving). A link to `steamcommunity.com/dev/apikey`. A text field for the SteamID/URL (submit connects). **Connect** is enabled when not busy, not demo, a key exists and `SteamIDInput.parse` succeeds (`canConnect`). In demo it says to leave the demo first; without a key it says to save the key first and shows `StatusRow`. The section has a fixed height of 250 and disabled scrolling.

## `LibraryChecklist`

State: `search`, `filter`, `sort`, `confirmSelectAll`. `shown` applies search (`localizedCaseInsensitiveContains` on `displayName`), filter (played = playtime above 0; on shelf = `model.isShelved`) and sort (name with `localizedStandardCompare`, hours descending, last played descending). Bottom bar: "N on shelf . M owned", **Select None** (all library games), **Select All Shown** (asks for confirmation above 200 games), **Refresh Library**, **Refresh Achievements** (`refreshAllStats`), disabled in demo, tests mode or without a resolved SteamID. Rows are `GameRow` (checkbox bound to `isShelved`/`setShelved`, cover thumbnail, name, "x.x hrs . last played <date>" or "never played").

`CoverThumb` requests the portrait through `model.images.cover(for:)` with `CoverURLs.portraitCandidates` and no header fallback (so list rows never trigger the header download); falls back to the placeholder palette colour; does nothing in demo or tests.

## `ShelfKeeperSettingsTab`

| Section | Controls |
|---|---|
| Save file access | "Steam folder": **Grant Access...** or "Granted" and **Revoke** (`requestSaveAccess`/`revokeSaveAccess`). Footnote explaining macOS keeps the Steam folder private until chosen. Picker "Saves were played in" bound to `saveTimeZoneID`: "This Mac's time zone (<id>)" (tag `nil`) or any `TimeZone.knownTimeZoneIdentifiers`. Footnote that save files carry no time zone. |
| AI service | Picker over `AIProviders.all` (`selectAIProvider`); for presets with `editableBaseURL` an "Address" text field (submit reloads models) and a red hint when the address fails validation ("Use an https address (plain http works only for this Mac)."); key row ("Saved in Keychain"/**Forget**, or a `SecureField` "Paste a key from any service" with **Save**; the label reads "API Key (optional)" for services that need none); "Model" text field, a **Choose...** menu of `availableModels`, and a refresh button (`loadModels`); `modelsState` status text; a "Get a key for <service>" link when the preset has a `keyURL`; and a privacy footnote stating a summary of the game's saves is sent to the chosen service with the user's key, and that nothing is sent until **Write Notes** is pressed. |
| Games with notes | One row per `Personalizers.all` display name. |

`saveKey()` calls `model.saveAIKey(keyDraft)` and clears the draft. Everything is disabled when `mode != .normal`.

## Gotchas

- Pasting a key can switch the service (prefix detection happens in `AppModel.saveAIKey`) before the key is stored, so the picker may change after pressing Save.
- The Settings window is a separate scene; it shares the same `AppModel` through the environment, so changes (shelving a game) appear on the shelf immediately.

## See also

[App and state](../architecture/app-and-state.md), [AI writer](../architecture/ai-writer.md), [Personalizer](../architecture/personalizer.md), [Steam](../architecture/steam.md).
