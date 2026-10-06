# Tests

Path: [`Tests/`](../../Tests) (7 files, about 1,030 lines), target `SteamShelfTests` (bundle unit tests hosted inside the app, `TEST_HOST`/`BUNDLE_LOADER` set in `project.yml`).

All tests are XCTest, **offline and deterministic**: no network, no Keychain, no real save files. Tests that touch the model use `LaunchMode.tests` with an in-memory SwiftData container. Anything involving real services is covered only by pure functions (`parse...`, `make...Request`). Run with `make test` (regenerates the Xcode project with XcodeGen first). Because the test host is the app, the Debug configuration has hardened runtime off so the test bundle can be injected.

## Depends on / used by

- Depends on: the whole `SteamShelf` module via `@testable import`.
- Used by: `make test`, `make` (default target runs tests then builds), CI-style runs under `build/ci` (not in git).

## Test files

### `BayLayoutTests.swift` (71 lines, `BayLayoutTests`)

Subject: [BayLayout](BayLayout.md). Bay sizes used: 700x888, 1600x600, 652x592, 1012x852.

| Test | Asserts |
|---|---|
| `testDesignBayReproducesOldProportions` | 700x888 gives boxH 180, boxW 120, gap 36, side pad 56, scale 1 |
| `testVeryWideBayKeepsAspectAndCapsGap` | 2:3 aspect kept, gap capped at `0.75 * boxW`, side padding above 100, height-limited box |
| `testNarrowBayShrinksBoxes` | box smaller than the row, gaps and padding at least their minimums; a 400-wide bay pins gap and padding to the minimums |
| `testBoxBottomsSitOnPlankTops` | each box's `maxY` equals the plank's `minY + boxRestInset`, inset less than the plank surface, planks span the bay, last plank ends at the bay bottom |
| `testAdjacentColumnsDoNotOverlapAndFitInside` | gap at least `gapMin`, row stays inside the bay |
| `testSlotHitTesting` | `slot(containing:)` finds a box centre; outside returns nil |

### `CoverURLTests.swift` (63 lines, `CoverURLTests`)

Subjects: [CoverURLs](CoverURLs.md) and [SteamIDInput](SteamIDInput.md). Hashed asset URL construction, unhashed fallbacks, candidate ordering (hashed 2x, hashed 1x, unhashed 2x; only unhashed when no format), header choice, and `SteamIDInput.parse` for SteamID64, profile URLs with and without trailing slash, vanity URLs and bare vanity names, rejecting `"hello world"`, empty, and a 16-digit number.

### `PaginationTests.swift` (44 lines, `PaginationTests`)

Subject: [Pagination](Pagination.md). Empty shelf (1 page, empty range, nil labels), page counts for 16/17/40 items, `slot(ofItem:)`, handle labels, targets for single and double clicks, `clamp`.

### `ShelfDocumentTests.swift` (153 lines, `ShelfDocumentTests`)

Subjects: [ShelfDocument](ShelfDocument.md), [BackOfBoxProvider](BackOfBoxProvider.md) (`LocalBackOfBoxProvider`), [ShelfStore](ShelfStore.md), [AppModel](AppModel.md) tests mode. Shared fixtures use whole-second dates because ISO-8601 drops sub-seconds.

| Test | Asserts |
|---|---|
| `testRoundTrip` | encode then decode equals the document |
| `testUnsupportedVersionThrows` | version 2 yields `DocumentError.unsupportedVersion(2)` |
| `testUnknownKeysIgnored` | extra JSON keys decode fine |
| `testForSharingDropsUnshelved` | only shelved entries are shared |
| `testMoveMakesArrangementCustomAndInsertAppends` | move semantics, append on custom, `arrangeAlphabetically`, sorted insert |
| `testArrangementRoundTripsAndDefaultsForOldDocuments` | missing `arrangement` key decodes as alphabetical |
| `testInsertSortedOrdering` | locale-aware ordering ("abc" with accent, "the Witcher", "Zelda-like") |
| `testLocalBackOfBoxDeterministicAndBucketed` | same input gives same blurb; a different playtime bucket changes blurb and fingerprint |
| `testLocalShelfSourceSaveThenLoad` | SwiftData blob round trip and update |
| `testAppModelTestsModeAndDemoToggle` | tests-mode `onLaunch` is a no-op; demo has 40 shelved, 3 pages, 50 library games; unticking keeps rating and note and re-ticking restores them; page clamps after emptying the shelf |

### `SteamDecodingTests.swift` (184 lines, `SteamDecodingTests`)

Subjects: [SteamClient](SteamClient.md) parsers, [SteamInstalls](SteamInstalls.md), [CoverURLs](CoverURLs.md) inputs. Fixtures are inline JSON (Steam responses, private profile, no-stats, HTML 403, store items with a failed item).

| Test | Asserts |
|---|---|
| `testVanity`, `testSummaries`, `testOwnedGames` | success paths and errors (`vanityNotFound`, `profileNotFound`, `gameDetailsPrivate`; `game_count: 0` is an empty library; missing name becomes "App 7") |
| `testAchievements` | 2 of 3 earned; none; private profile; no stats; HTML 403 maps to `invalidKey` |
| `testStoreItems`, `testStoreItemsInputJSON` | only `success == 1` items; request JSON contains the appid and `include_assets` |
| `testCheckStatus` | 401/403 invalid key, 429 rate limited, 500 `http(500)`, 200 ok |
| `testResolveSteamID64DoesNotTouchNetwork` | a SteamID64 resolves locally |
| `testLibraryFoldersInstalledAppIDs` | `"apps"` block parsing across several library folders; empty file; `steam://rungameid/620` |
| `testLibraryPathsInstallDirAndBundlePicking` | `path` values, `installdir`, bundle selection (shallowest and best-named; launcher last; none for a bare folder) using temporary directories |

### `PersonalizerTests.swift` (503 lines)

Five classes. Fixtures come from [`LarianFixtures.swift`](../../Tests/LarianFixtures.swift).

| Class | Subject | Highlights |
|---|---|---|
| `LarianFormatsTests` | [LarianFormats](LarianFormats.md) | LZ4 block vector; truncated and invalid LZ4 (bad offset, output cap) throws `PersonalizerError`; LZ4 frame and zstd reject garbage; LSF plain and LZ4 fixtures decode to identical trees (journal structure, roll attributes); `keepOnly: ["Journal"]`; truncated LSF throws; LSPK fixture lists `meta.lsf`, `SaveInfo.json`, `Globals.lsf`; truncated package throws |
| `BG3PersonalizerTests` | [BG3Personalizer](BG3Personalizer.md) | counted patterns (reload, 328-day gap with playtime advance, saves by place, party attendance, midnight-5 a.m. count in UTC but not Honolulu, typed names, autosaves); a full digest from a synthetic Steam root; no saves returns nil; folder name parsing; party and playtime text; history line format; autosave collapsing (same hero and day only) and reload note; 250-line cap keeps the most recent; latest save without journal |
| `ShelfKeeperAITests` | [ShelfKeeperAI](ShelfKeeperAI.md) Anthropic wire | request body shape (model, fallbacks, `max_tokens` 16000, `effort: medium`, schema keys, no thinking/temperature/top_p/top_k, system prefix, user prompt prefix); headers and URL; parse skips thinking blocks and trims; refusal and truncation; HTTP error mapping (401, 429, 529, 503, 400 with message, 418 without); malformed replies |
| `KeeperModelTests` (`@MainActor`) | `BackOfBoxContent`, [AppModel](AppModel.md) | decoding without the newer fields; round trip with them; notes survive a document round trip; `blurbIfNeeded` keeps AI notes; template returns after notes are removed; `canWriteNotes` false in tests mode and `writeNotes` leaves state idle; `KeeperText` messages (the `corrupt` reason is not leaked) |
| `AIProviderTests` | [AIProvider](AIProvider.md), chat wire | key prefix detection for each service (longest prefix wins, plain `sk-` is OpenAI), base URL validation (https, localhost http, no plain http elsewhere, bad strings), `contentProviderID`, chat request shape (no max-token/sampling fields, Bearer auth, optional response format, keyless local servers, `notConfigured`), chat parsing (fenced JSON, part arrays, length, content filter, error bodies), model list request/parse (prefix strip, dedupe, natural sort), Anthropic feature gating by model, `isAIWritten` for both id styles |

### `LarianFixtures.swift` (12 lines of code, long base64 constants)

`enum LarianFixtures`: synthetic fixtures generated by [tools/bg3](tools-bg3.md), with **no real save data**: `lsvBase64` (an LSPK v18 package: `meta.lsf` stored, `SaveInfo.json` zstd, `Globals.lsf` zstd with LZ4 inner sections in linked frames), `lsfPlainBase64` (LSF v7, uncompressed sections), `lsfLZ4Base64` (same tree, LZ4 sections), `lz4BlockBase64` with `lz4BlockExpected`. The fixture save is named "Goblin Camp CLEARED - 26h 12m", hero "Corth".

## Gaps (what is not tested)

Views and rendering (no snapshot or UI tests; verified by hand and with screenshot scripts under `build/tools`), network behaviour of `SteamClient` and `ShelfKeeperAI` against live services (request/response handling is covered by offline tests only; no live runs for services other than Anthropic), `ImageCache` (disk and network), `Keychain`, `SteamFolderAccess`, `ArtGenerator` output, Sparkle and the release script.

## See also

[Overview](../architecture/overview.md) (reading order), and the "Tests" section of each architecture page: [App and state](../architecture/app-and-state.md), [Shelf rendering](../architecture/shelf-rendering.md), [Open box](../architecture/open-box.md), [Steam](../architecture/steam.md), [Personalizer](../architecture/personalizer.md), [AI writer](../architecture/ai-writer.md), [Distribution](../architecture/distribution.md).
