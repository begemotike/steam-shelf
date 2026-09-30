# Steam Shelf

A skeuomorphic wooden bookshelf for your Steam library, for macOS 15 and later. Your games sit on the shelf as
boxes; click one and it lifts off as a 3D object you can spin. The back carries your rating, purchase date, hours
played, achievements and a note.

## Install (friends)

1. Download the latest `SteamShelf-x.y.z.zip` from [Releases](https://github.com/begemotike/steam-shelf/releases).
2. Unzip and drag **SteamShelf.app** to Applications.
3. Open it. Press ⌘, for Settings, paste a Steam Web API key from <https://steamcommunity.com/dev/apikey>, press
   Save, then enter your profile URL and press Connect. Your profile's *Game details* must be Public in Steam's
   privacy settings.

Updates arrive automatically (checked once a day) or via **Steam Shelf ▸ Check for Updates…**.

## Develop

```bash
make        # tests + Debug build
make demo   # launch with 40 imaginary games
```

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from
`project.yml`. Design and architecture notes live in `docs/`.

## Release

```bash
scripts/release.sh 0.2.0
```

Archives a Release build signed with Developer ID, notarizes and staples it, zips it, signs the zip with the Sparkle
EdDSA key from the login keychain, updates `appcast.xml`, publishes a GitHub release and pushes. One-time setup:

```bash
xcrun notarytool store-credentials steam-shelf-notary --apple-id you@example.com --team-id 9JHK4XRFW5
```
