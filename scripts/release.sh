#!/bin/bash
# Build, sign, notarize and publish a Steam Shelf release, then update the Sparkle appcast.
#
#   scripts/release.sh 0.2.0            # full release
#   scripts/release.sh 0.2.0 --dry-run  # build + sign + appcast locally, no notarize/upload/push
#
# One-time setup (needs an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials steam-shelf-notary --apple-id you@example.com --team-id 9JHK4XRFW5
set -euo pipefail

VERSION="${1:?usage: release.sh X.Y.Z [--dry-run]}"
DRY_RUN="${2:-}"
REPO="begemotike/steam-shelf"
NOTARY_PROFILE="steam-shelf-notary"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release/$VERSION"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
APP_NAME="SteamShelf"
ZIP="$APP_NAME-$VERSION.zip"

cd "$ROOT"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z"; exit 1; }
if [[ -z "$DRY_RUN" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "commit or stash your changes first"; exit 1; }
  git tag | grep -qx "v$VERSION" && { echo "tag v$VERSION already exists"; exit 1; }
fi

# Build number: monotonically increasing commit count (Sparkle compares CFBundleVersion).
BUILD="$(git rev-list --count HEAD)"
echo "▶ Steam Shelf $VERSION (build $BUILD)"

xcodegen generate --quiet
xcodebuild -resolvePackageDependencies -project $APP_NAME.xcodeproj -scheme $APP_NAME -derivedDataPath build -quiet
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Sparkle tools missing at $SPARKLE_BIN"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
echo "▶ Archiving (Release, Developer ID, hardened runtime)"
xcodebuild -project $APP_NAME.xcodeproj -scheme $APP_NAME -configuration Release \
  -derivedDataPath build -archivePath "$OUT/$APP_NAME.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  archive -quiet
APP="$OUT/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "archive did not produce $APP"; exit 1; }

echo "▶ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application" >/dev/null || { echo "not signed with Developer ID"; exit 1; }

echo "▶ Zipping"
ditto -c -k --keepParent "$APP" "$OUT/$ZIP"

if [[ -z "$DRY_RUN" ]]; then
  echo "▶ Notarizing (this takes a few minutes)"
  xcrun notarytool submit "$OUT/$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▶ Stapling"
  xcrun stapler staple "$APP"
  rm -f "$OUT/$ZIP"; ditto -c -k --keepParent "$APP" "$OUT/$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
else
  echo "▶ Dry run: skipping notarization"
fi

echo "▶ Building appcast"
# generate_appcast signs the zip with the EdDSA key from the login keychain and merges into appcast.xml.
mkdir -p "$OUT/appcast"; cp "$OUT/$ZIP" "$OUT/appcast/"
[[ -f appcast.xml ]] && cp appcast.xml "$OUT/appcast/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO/releases" \
  -o "$OUT/appcast/appcast.xml" "$OUT/appcast"
cp "$OUT/appcast/appcast.xml" appcast.xml
echo "appcast.xml updated:"; grep -E "sparkle:version|sparkle:shortVersionString|enclosure" appcast.xml | head -6

if [[ -n "$DRY_RUN" ]]; then
  echo "▶ Dry run complete: $OUT/$ZIP (appcast.xml modified in working tree; discard with git checkout appcast.xml)"
  exit 0
fi

echo "▶ Publishing GitHub release v$VERSION"
gh release create "v$VERSION" "$OUT/$ZIP" --repo "$REPO" --title "Steam Shelf $VERSION" --generate-notes
git add appcast.xml
git commit -m "Release $VERSION (build $BUILD)" -q
git tag "v$VERSION"
git push origin main --tags
echo "✔ Released $VERSION. Friends on older builds will be offered it within a day, or via Check for Updates…"
