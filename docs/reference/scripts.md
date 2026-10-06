# scripts

Path: [`scripts/`](../../scripts) (2 files, both tracked in git)

Two developer scripts: `release.sh` builds, signs, notarizes and publishes a release and updates the Sparkle appcast; `make-icon.swift` draws the app icon procedurally. Neither is part of the app target.

## Depends on / used by

- `release.sh` depends on: `xcodegen`, `xcodebuild`, `codesign`, `ditto`, `xcrun notarytool` and `stapler`, `spctl`, `git`, `gh` (GitHub CLI), Sparkle's `generate_appcast` (from the SwiftPM artifact under `build/SourcePackages/artifacts/sparkle/Sparkle/bin`), a notarytool keychain profile named `steam-shelf-notary`, the Developer ID Application certificate and the Sparkle EdDSA private key in the login keychain. Used by hand: `scripts/release.sh X.Y.Z [--dry-run]`.
- `make-icon.swift` depends on AppKit/CoreGraphics/CoreText and the Copperplate font. Used by hand: `swift scripts/make-icon.swift out.png`; the resulting PNG was turned into `Resources/AppIcon.icns` (the iconset lives in `build/AppIcon.iconset`, not in git).

## `release.sh`

Bash with `set -euo pipefail`. Arguments: `VERSION` (required, must match `^[0-9]+\.[0-9]+\.[0-9]+$`) and optional `--dry-run`. Constants: `REPO=begemotike/steam-shelf`, `NOTARY_PROFILE=steam-shelf-notary`, output `build/release/<version>/`, zip `SteamShelf-<version>.zip`. The step-by-step walk-through, with why each step exists, is in [Distribution](../architecture/distribution.md#scriptsreleasesh-step-by-step). In order:

| # | Step | Detail |
|---|---|---|
| 1 | Preconditions | Full release only: working tree must be clean and tag `v<version>` must not exist. |
| 2 | Build number | `BUILD = git rev-list --count HEAD` (monotonic; Sparkle compares `CFBundleVersion`). |
| 3 | Generate and resolve | `xcodegen generate`; `xcodebuild -resolvePackageDependencies`; require Sparkle's `generate_appcast`. |
| 4 | Archive | Release configuration, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` overridden on the command line. |
| 5 | Re-sign Sparkle | `codesign -f --timestamp -o runtime --preserve-metadata=entitlements -s "Developer ID Application"` on `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, the framework, then the app itself (inside-out). |
| 6 | Verify | `codesign --verify --deep --strict`; each nested binary and the app must show `Authority=Developer ID Application`. |
| 7 | Zip | `ditto -c -k --keepParent`. |
| 8 | Notarize (not in dry run) | `notarytool submit --wait`; fails unless the log shows `status: Accepted` (prints the first 40 lines of the notary log). |
| 9 | Staple | `stapler staple`, re-zip, `spctl --assess`. |
| 10 | Appcast | `generate_appcast` signs the zip with the EdDSA key and merges into `appcast.xml`, with download prefix `https://github.com/<repo>/releases/download/v<version>/`. |
| 11 | Publish (not in dry run) | Commit `appcast.xml` ("Release X (build N)"), `git tag`, `git push origin main v<version>`, then `gh release create` with generated notes. |

`--dry-run` stops after step 10 and leaves `appcast.xml` modified (discard with `git checkout appcast.xml`).

## `make-icon.swift`

A script, not a module. Draws 1024 x 1024: a macOS squircle (824-pt artwork, corner radius 22.37%) with a drop shadow; walnut body with 140 seeded grain strokes; a bay with inner shadows; two shelves each holding three glossy 2:3 boxes using the app's placeholder cover palettes (sunburst, accent rules, shrink-wrap gloss, spine sliver, contact shadow); crown and plinth highlight lines; a brass nameplate with screws and engraved "STEAM SHELF" (Copperplate-Bold 30); a 2007-style gloss over the top of the tile; rim strokes. Writes the PNG named by the first argument (default `icon.png`). The local `Rand` type duplicates `SplitMix64` because a standalone script cannot import app code.

## Gotchas

- `release.sh` publishes from the *current* branch name `main` (hard-coded in `git push origin main`).
- Never re-release the same version: the build number is the commit count, and the tag must not already exist.
- The Sparkle tools path depends on a prior `-resolvePackageDependencies` using `-derivedDataPath build`; if `build/` is deleted, step 3 recreates it.

## See also

[Distribution](../architecture/distribution.md).
