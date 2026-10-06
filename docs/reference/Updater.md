# Updater

Path: [`Sources/App/Updater.swift`](../../Sources/App/Updater.swift) (23 lines)

A thin wrapper around Sparkle 2's standard updater, plus the menu item. Automatic checks run once a day because `Info.plist` sets `SUScheduledCheckInterval` to 86400 and `SUEnableAutomaticChecks` to true; the feed URL and EdDSA public key are also in `Info.plist` (see [Distribution](../architecture/distribution.md)).

## Depends on / used by

- Depends on: Sparkle (`SPUStandardUpdaterController`).
- Used by: [SteamShelfApp](SteamShelfApp.md) (touches `Updater.shared` in `.normal` mode so the updater starts, and installs `UpdateCommands`).

## Types

| Type | Signature | Notes |
|---|---|---|
| `Updater` | `@MainActor final class Updater` | `static let shared`. Private init creates `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`, which starts scheduled checking immediately. |
| `Updater.checkForUpdates()` | `func checkForUpdates()` | Calls `controller.checkForUpdates(nil)`; Sparkle shows its own UI. |
| `UpdateCommands` | `struct UpdateCommands: Commands` | `CommandGroup(after: .appInfo)` adding "Check for Updates...". |

## Gotchas

- Because the instance is created lazily, tests mode never starts Sparkle (the app only touches `Updater.shared` when `mode == .normal`). The menu item would create it on first click.
- Sparkle runs inside the App Sandbox using its installer XPC service; the matching entitlements are described in [Distribution](../architecture/distribution.md).

## See also

[Distribution](../architecture/distribution.md), [Overview](../architecture/overview.md).
