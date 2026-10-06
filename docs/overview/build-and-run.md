# Build, run, test, release

## Requirements
- macOS 15 or later to run; the project was built on macOS 26 with **Xcode 27 / Swift 6.4**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from
  `project.yml` and is not committed.
- Swift packages resolve automatically: Sparkle 2.10 (updates) and facebook/zstd 1.5.7 (save-file decompression).
- To build Release or to run `make` as-is you need the Developer ID certificate in your login keychain (Debug is
  signed with it too, so the Keychain stops re-prompting; see [architecture/distribution.md](../architecture/distribution.md)).
  To build without it, set `CODE_SIGN_IDENTITY="-"` for Debug in `project.yml`.

## Everyday commands
```bash
make            # tests + Debug build; prints the .app path
make test       # tests only
make build      # Debug build only
make run        # build and launch
make demo       # build and launch on the demo shelf (40 imaginary games, no Steam account needed)
make clean
```
`make … DERIVED=build/ci` builds into another folder, useful when the app is running (macOS will not let a build
replace a running signed app).

Debug-only launch arguments: `--demo` (start on the demo shelf), `--demo-notes` (give the first demo box stored
Shelf-Keeper notes so the panel can be seen), `--dump-digest <appid>` (write the personalizer digest to
`~/Library/Caches/SteamShelf/digest-<appid>.txt`; needs the folder grant).

## First run
1. Settings (⌘,) ▸ Library: paste a Steam Web API key (https://steamcommunity.com/dev/apikey; requires Steam Guard),
   Save; enter your profile URL or SteamID64; Connect. Your Steam profile's *Game details* must be Public.
2. Tick the games you want on the shelf.
3. Optional, Shelf-Keeper tab: Grant Access to the Steam folder, choose the time zone you play in, pick an AI
   service, paste its key, choose a model.

## Tests
`Tests/` has 70+ XCTest cases, all offline: Steam JSON decoding against fixtures, cover URL construction,
`ShelfDocument` round-trips (including older documents), pagination and bay layout math, the Larian save-file
readers against synthetic fixtures (`Tests/LarianFixtures.swift`), the BG3 digest, the AI request/response handling
for both wire formats, provider detection, and the app model's demo/toggle behaviour with an in-memory store.
Tests never touch the network, the Keychain or real save files.

## Release
```bash
scripts/release.sh 0.3.0            # full release
scripts/release.sh 0.3.0 --dry-run  # archive, sign and build the appcast locally; no notarization/upload/push
```
One-time setup: `xcrun notarytool store-credentials steam-shelf-notary --apple-id <you> --team-id 9JHK4XRFW5`.
The script archives a Release build, re-signs Sparkle's nested helpers with Developer ID, verifies, notarizes and
staples, zips, signs the zip with the Sparkle EdDSA key from the login keychain, updates `appcast.xml`, pushes the
tag, publishes the GitHub release and pushes `main`. Version numbers must only go up; the tree must be clean.
Back up the Sparkle private key (`generate_keys -x file`): without it no installed copy can take another update.
