# SteamIDInput

Path: [`Sources/Model/SteamIDInput.swift`](../../Sources/Model/SteamIDInput.swift) (41 lines)

Parses what the user types into the Settings "SteamID or profile URL" field into either a 17-digit SteamID64 or a vanity (custom URL) name. It does no network access; resolving a vanity name is `SteamClient.resolveSteamID`.

## Depends on / used by

- Depends on: nothing.
- Used by: [AppModel](AppModel.md) (`connect()`), [SettingsView](SettingsView.md) (`canConnect` enables the Connect button only for parseable input), [SteamClient](SteamClient.md) (`resolveSteamID(_:key:)` takes it), [Tests](Tests.md) (`CoverURLTests.testSteamIDInput`).

## `SteamIDInput`

`enum SteamIDInput: Equatable, Sendable { case steamID64(String), vanity(String) }`

| Function | Behaviour |
|---|---|
| `static func parse(_ raw: String) -> SteamIDInput?` | Trims whitespace, strips trailing slashes, returns `nil` when empty. A bare SteamID64 returns `.steamID64`. A string starting (case-insensitively) with `https://steamcommunity.com/`, `http://steamcommunity.com/`, `steamcommunity.com/`, or the `www.` variants is parsed by path: `profiles/<id>` yields `.steamID64` if valid, `id/<name>` yields `.vanity` if valid, any other path yields `nil`. Anything else is tried as a bare vanity name. |
| `private static func isSteamID64(_:)` | Exactly 17 ASCII digits starting with `7656119`. |
| `private static func isVanity(_:)` | 2 to 32 characters of ASCII letters, digits, `_` or `-`, and **not all digits**. |

## Gotchas

- All-digit strings that are not valid SteamID64s (for example 16 digits) are rejected rather than treated as vanity names. This was required by acceptance test A3 ([Phase A notes](../decisions/OPEN_QUESTIONS.md#implementation-notes-phase-a)).
- The prefix match is on the original-case string using a lowercased copy for comparison; the returned id/name keeps the user's casing. Query strings or fragments in a pasted URL (for example `?foo`) are not stripped and will make the vanity check fail.

## See also

[Steam](../architecture/steam.md), [App and state](../architecture/app-and-state.md).
