# Decision log

Each entry: what was decided, why, and what it would cost to change. Dates are when the decision landed in code.
`OPEN_QUESTIONS.md` is the running log this was consolidated from and has the finer detail.

## Product and scope
| # | Decision | Why | Cost to change |
|---|---|---|---|
| D1 | Build only what the brief needs; pin everything else as a question | Owner's instruction; keeps v1 shippable | — |
| D2 | The whole window is the bookcase; every control is part of the case frame (2026-09-29) | Owner's direction after seeing the first floating-bookcase build | Already done; see history/PHASE_C |
| D3 | Manual arrangement is optional: alphabetical until the first drag, then custom and persisted (2026-09-30) | Owner wanted to be able to arrange, not forced to | Small: `ShelfDocument.arrangement` |
| D4 | Purchase date is a manual field | Steam's Web API cannot provide it; only the logged-in licenses page can | A paste-your-licenses-page importer would be the safe add-on |
| D5 | Peer-to-peer and store details are deferred; seams exist (`ShelfSource`, `forSharing()`, `BackOfBoxContext.storeDetails`) | Not needed for v1; architecture must not preclude them | Transport choice still open (Q9) |

## Architecture
| # | Decision | Why | Cost to change |
|---|---|---|---|
| D6 | 2D SwiftUI shelf; RealityKit only for the opened box | Highest chance of compiling first time, smooth, Apple's forward path; SceneKit is soft-deprecated | Whole-bookcase 3D would be a rewrite of the shelf |
| D7 | `ShelfDocument` (versioned Codable JSON) is the one schema; SwiftData stores it as a blob | Keeps the sharing format and the persistence format identical | Per-game tables only pay off at thousands of entries |
| D8 | All UI and SwiftData on the main actor; actors for Steam client, image cache, AI client; no `@preconcurrency`/`nonisolated(unsafe)` (one `@unchecked Sendable` for `SendableImage`) | Swift 6 strict concurrency without escape hatches | — |
| D9 | No third-party packages except Sparkle (updates) and libzstd (save files) | Fewer moving parts; both are unavoidable for their jobs | — |
| D10 | Procedural textures and a procedural icon; no asset catalogs or downloaded art | Consistency, no licensing, tiny repo | — |
| D11 | Bay layout is a pure `BayLayout` value with tests; frame members are fixed-size, the bay flexes | Resizable window without scaling blur or hit-testing bugs | — |
| D12 | Planks draw in front of boxes and hide 6 du of their base (2026-09-30) | The only cue that reads as "standing on the shelf" with bright real art | — |

## Steam
| # | Decision | Why | Cost to change |
|---|---|---|---|
| D13 | Steam Web API with the user's own key and SteamID64; key in Keychain, `hasAPIKey` mirrored in UserDefaults | Launch never touches the Keychain (prompts) | — |
| D14 | Cover art via `IStoreBrowseService/GetItems` hashed paths first, legacy paths and header art as fallbacks, then a generated cover | Newer games 404 on the legacy path | — |
| D15 | Play opens the game's own `.app` from the install folder; Steam client is the fallback (2026-10-01) | Owner wanted direct launch; on macOS most games run without Steam | Add an "always through Steam" switch if DRM'd games misbehave (Q20) |
| D16 | Installed state from `libraryfolders.vdf` through a read-only sandbox exception for `steamapps/` | One small file lists installs for every library folder | — |

## Distribution
| # | Decision | Why | Cost to change |
|---|---|---|---|
| D17 | Developer ID + hardened runtime + notarization; sandbox kept; Sparkle through its sandboxed installer XPC | Shareable with a friend without warnings; the sandbox stayed because removing it was refused by the safety tooling and the XPC path is Apple-documented | — |
| D18 | Debug builds also signed with Developer ID (2026-10-01) | Ad-hoc signatures change every build, so the Keychain asked for the login password after each rebuild | `CODE_SIGN_IDENTITY="-"` for machines without the certificate |
| D19 | Appcast and zips on public GitHub; `raw.githubusercontent.com` feed | Zero hosting; the repo must be public for the friend's copy to update | Cloudflare/sprucetools alternative (Q19) |
| D20 | Build number = commit count; versions only go up; the release script refuses an existing tag | Sparkle compares build numbers | — |

## Shelf-Keeper notes
| # | Decision | Why | Cost to change |
|---|---|---|---|
| D21 | Per-game personalizer protocol; BG3 first; everything read from the Steam cloud save folder | Only BG3 was in scope; other games add one file each | — |
| D22 | Folder access by explicit one-time grant (security-scoped bookmark in UserDefaults), not a Keychain item and not a blanket entitlement | Owner asked for a permission ask; the bookmark is not a secret; Keychain reads were the prompt problem | — |
| D23 | Save-file readers ported from verified Python references; synthetic fixtures only in the repo | The repo is public; real saves are personal | — |
| D24 | Any AI service: Anthropic native + OpenAI-compatible chat; key-prefix detection; models listed from the service, not hardcoded (2026-10-01) | Owner wanted to paste any key; hardcoded model names go stale | — |
| D25 | Default writer Claude Sonnet 5.5 (2026-10-04) | 14 s and ~4 cents per run versus 40–70 s and ~17 cents on Opus; Opus is a menu pick away | — |
| D26 | The app computes the facts (gaps, reloads, counts, attendance); the prompt forbids the model from counting (2026-10-04) | Sonnet miscounted (7 became 9, 73 minutes became 33); counted facts fix every service | — |
| D27 | Comedy by craft rules, example lines and a discarded `drafts` scratch pad; truth rules on numbers and player-typed words | "Be funnier" does nothing; examples and structure do; the first funny run invented a typo joke and a number | — |
| D28 | A "saves were played in" time zone setting | Save files carry no zone; a travelling Mac shifted every late-night save by two hours | Auto-detect a home zone (Q23) |
