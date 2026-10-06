# Keychain

Path: [`Sources/Persistence/Keychain.swift`](../../Sources/Persistence/Keychain.swift) (46 lines)

A minimal generic-password wrapper over Security.framework. The app stores two kinds of secret and nothing else in it: the Steam Web API key and one AI key per service. All items share the service name `net.outofajam.SteamShelf` and differ by account name.

## Depends on / used by

- Depends on: Security.framework.
- Used by: [AppModel](AppModel.md) (`saveAPIKey`, `forgetAPIKey`, `saveAIKey`, `forgetAIKey`, `loadModels`, `writeNotes`, `requireKey`).

## Types

| Type | Signature | Notes |
|---|---|---|
| `KeychainError` | `enum { case status(OSStatus) }` | Thrown by `save`. |
| `Keychain` | `enum` with static members | No instances. Not actor-isolated; the functions are synchronous and thread-safe at the Security level. |

### Accounts

| Name | Value |
|---|---|
| `service` | `"net.outofajam.SteamShelf"` |
| `apiKeyAccount` | `"steam-web-api-key"` |
| `aiKeyAccount` | `"anthropic-api-key"` (the original single-key account) |
| `aiKeyAccount(for providerID: String) -> String` | `"anthropic-api-key"` for `"anthropic"` (so keys saved before multi-service support carry over), otherwise `"ai-key-<providerID>"`. |

### Functions

| Signature | Behaviour |
|---|---|
| `static func save(_ value: String, account: String) throws` | Delete-then-add. Item class `kSecClassGenericPassword`, accessibility `kSecAttrAccessibleAfterFirstUnlock`. Throws `KeychainError.status` if `SecItemAdd` fails. Uses the file-based login keychain: the data-protection keychain needs a team-ID-backed entitlement. |
| `static func read(account: String) -> String?` | `SecItemCopyMatching` with `kSecMatchLimitOne`; returns `nil` for any failure. |
| `static func delete(account: String)` | `SecItemDelete`, result ignored. |
| `private static func baseQuery(account:)` | The shared class/service/account dictionary. |

## Gotchas

- The login keychain ties item access to the app's code-signing identity. With ad-hoc signing every rebuild changed the identity and macOS prompted for access; that is why Debug builds are now signed with the same Developer ID as Release ([Distribution](../architecture/distribution.md)). `AppModel` also mirrors "has key" booleans in `UserDefaults` so launch never reads the Keychain.
- `read` returns `nil` both for "no item" and for a denied access prompt; callers cannot tell the difference.

## See also

[App and state](../architecture/app-and-state.md), [Distribution](../architecture/distribution.md), [AI writer](../architecture/ai-writer.md).
