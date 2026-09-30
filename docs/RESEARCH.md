# Steam Shelf — Research Notes

Researched 2026-09-29. Items marked **VERIFIED LIVE** were exercised with `curl` from this Mac during research. Items marked **DOCUMENTED** come from Valve/Apple docs. Items marked **UNVERIFIED** could not be exercised (no Steam Web API key available during research) and are from long-standing community knowledge: the implementer must write decoders that tolerate both the documented shape and a missing/empty shape.

---

## 1. Steam Web API — general

| Fact | Status |
|---|---|
| Public host: `https://api.steampowered.com/{Interface}/{Method}/v{N}/` | VERIFIED LIVE |
| `partner.steam-api.com` is the **publisher** host — do NOT use it with a user key | DOCUMENTED |
| No `key` param → **HTTP 401**, HTML body (`<title>Unauthorized</title>… verify your key= parameter`) | VERIFIED LIVE |
| Bad `key` value → **HTTP 403**, HTML body (`<title>Forbidden</title>…`) | VERIFIED LIVE |
| Terms of use: "limited to one hundred thousand (100,000) calls … per day" | DOCUMENTED (steamcommunity.com/dev/apiterms) |
| Short-window throttling exists but is undocumented; you may see **HTTP 429**. Treat 429 as "retry later". | community knowledge |
| Keys are obtained at `https://steamcommunity.com/dev/apikey` (requires a Steam account with a non-limited status) | DOCUMENTED |

**Consequence for the client:** error bodies for 401/403 are HTML, not JSON. Always check the HTTP status *before* JSON-decoding, except for `GetPlayerAchievements` (see §1.4), which returns JSON bodies on 400/403.

Recommended query params on every call: `key=…`, `format=json`.

### 1.1 ISteamUser/ResolveVanityURL (v1)

```
GET https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/?key=KEY&vanityurl=gabelogannewell&url_type=1
```
- `vanityurl` — the part after `steamcommunity.com/id/`.
- `url_type` — 1 = individual profile (default), 2 = group, 3 = official game group. Always send 1.

Success (HTTP 200):
```json
{ "response": { "steamid": "76561197960287930", "success": 1 } }
```
No match (HTTP 200):
```json
{ "response": { "success": 42, "message": "No match" } }
```
Decode `success` as Int; `1` → use `steamid`; anything else → `SteamError.vanityNotFound`.

### 1.2 ISteamUser/GetPlayerSummaries (v2)

```
GET https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=KEY&steamids=76561197960287930
```
- `steamids` — comma-separated, max 100.

```json
{ "response": { "players": [ {
  "steamid": "76561197960287930",
  "communityvisibilitystate": 3,
  "profilestate": 1,
  "personaname": "Rabscuttle",
  "profileurl": "https://steamcommunity.com/id/gabelogannewell/",
  "avatar": "https://avatars.steamstatic.com/<hash>.jpg",
  "avatarmedium": "https://avatars.steamstatic.com/<hash>_medium.jpg",
  "avatarfull": "https://avatars.steamstatic.com/<hash>_full.jpg",
  "avatarhash": "<hash>",
  "personastate": 0,
  "lastlogoff": 1700000000,
  "timecreated": 1063407589
} ] } }
```
- `communityvisibilitystate`: 1 = private/not visible to you, 3 = public. Only `steamid`, `personaname`, `profileurl`, `avatar*`, `communityvisibilitystate` are guaranteed; everything else is optional.
- Unknown SteamID → `"players": []` (HTTP 200) → `SteamError.profileNotFound`.

### 1.3 IPlayerService/GetOwnedGames (v1)

```
GET https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=KEY&steamid=7656119…&include_appinfo=1&include_played_free_games=1&format=json
```
| Param | Meaning |
|---|---|
| `steamid` (uint64, required) | player |
| `include_appinfo` (bool) | adds `name`, `img_icon_url`, `has_community_visible_stats` — **required** for us |
| `include_played_free_games` (bool) | include F2P games the user has played — send `1` |
| `appids_filter` (uint32 array) | not used |
| `include_extended_appinfo`, `include_free_sub`, `skip_unvetted_apps`, `language` | exist in newer API listings; **not used** in v1 |

Success (HTTP 200):
```json
{ "response": {
  "game_count": 2,
  "games": [
    { "appid": 620, "name": "Portal 2", "playtime_forever": 1234,
      "img_icon_url": "2e478fc6874d06ae5baf0d147f6f21203291aa02",
      "has_community_visible_stats": true,
      "playtime_windows_forever": 1200, "playtime_mac_forever": 34,
      "playtime_linux_forever": 0, "playtime_deck_forever": 0,
      "rtime_last_played": 1726000000, "playtime_disconnected": 0 },
    { "appid": 440, "name": "Team Fortress 2", "playtime_forever": 0,
      "img_icon_url": "e3f595a92552da3d664ad00277fad2107345f743",
      "rtime_last_played": 0 }
  ] } }
```
- `playtime_forever` is **minutes**. `playtime_2weeks` appears only if played in the last 2 weeks.
- `rtime_last_played` is Unix seconds; `0` means never → map to `nil`.
- `has_community_visible_stats` may be absent → treat as `false`.
- Icon (32×32) URL: `https://media.steampowered.com/steamcommunity/public/images/apps/{appid}/{img_icon_url}.jpg` (not needed for v1 UI; Settings list uses the portrait/header art instead).

**Private "Game details"** (UNVERIFIED): Steam returns **HTTP 200 with `{"response":{}}`** (no `games`, no `game_count`). Treat "decoded OK but `games == nil`" as `SteamError.gameDetailsPrivate`. A public profile that truly owns zero games returns `{"response":{"game_count":0}}` — `game_count == 0` with no `games` → empty library, not an error.
Whether a user's *own* key bypasses their own privacy setting is inconsistently reported; the app must just surface `gameDetailsPrivate` with the fix-it text ("Steam → Profile → Edit Profile → Privacy Settings → Game details: Public").

### 1.4 ISteamUserStats/GetPlayerAchievements (v1)

```
GET https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/?key=KEY&steamid=7656119…&appid=620&l=english
```
Success (HTTP 200):
```json
{ "playerstats": {
  "steamID": "7656119…", "gameName": "Portal 2",
  "achievements": [
    { "apiname": "ACH.SURVIVE_CONTAINER_RIDE", "achieved": 1, "unlocktime": 1303000000,
      "name": "Wake Up Call", "description": "Survive the manual override" },
    { "apiname": "ACH.WAKE_UP", "achieved": 0, "unlocktime": 0 }
  ],
  "success": true } }
```
- `name`/`description` only appear when `l=` is sent.
- **Total = `achievements.count`, earned = count where `achieved == 1`.** This endpoint lists every achievement (earned or not), so **`GetSchemaForGame` is not needed** for the total.
- Game with a stats schema but zero achievements (UNVERIFIED): `success: true`, no `achievements` key → total 0, earned 0 → UI shows "No achievements".

Error bodies are **JSON with non-200 status** (UNVERIFIED, long-standing behavior):
| Situation | HTTP | Body |
|---|---|---|
| Profile / game details private | 403 | `{"playerstats":{"error":"Profile is not public","success":false}}` |
| App has no stats | 400 | `{"playerstats":{"error":"Requested app has no stats","success":false}}` |
| Bad key | 403 | HTML (see §1) |

**Decoder rule:** for this endpoint, try to decode `PlayerStatsEnvelope` from the body *regardless of status*. If it decodes and `success == false`, map the `error` string: contains "not public" → `.privateProfile`, contains "no stats" → `.noStats`, else `.steamError(message)`. If it does not decode and status is 401/403 → `.invalidKey`.

Only call it for games where `has_community_visible_stats == true`; otherwise mark `achievementsState = .none` without a network call.

### 1.5 ISteamUserStats/GetSchemaForGame (v2) — not used in v1

```
GET https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?key=KEY&appid=620
→ { "game": { "gameName": "...", "gameVersion": "...", "availableGameStats": { "achievements": [ {"name":"...","displayName":"...","icon":"...","icongray":"..."} ] } } }
```
Would be needed only for achievement icons/names. Out of scope.

### 1.6 IStoreBrowseService/GetItems (v1) — keyless, used for cover art (**important finding**)

```
GET https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json=<URL-encoded JSON>
input_json = {"ids":[{"appid":620},{"appid":3527290}],
              "context":{"language":"english","country_code":"US"},
              "data_request":{"include_assets":true}}
```
VERIFIED LIVE: no key needed; a single request with **121 ids** succeeded (use batches of **100**).

```json
{ "response": { "store_items": [
  { "item_type": 0, "id": 3527290, "success": 1, "visible": true, "name": "PEAK", "appid": 3527290, "type": 0,
    "assets": {
      "asset_url_format": "steam/apps/3527290/${FILENAME}?t=1790591892",
      "header": "31bac6b2eccf09b368f5e95ce510bae2baf3cfcd/header.jpg",
      "library_capsule": "480bd879ac737921bfa2529a6fea15961267ad21/library_600x900.jpg",
      "library_capsule_2x": "480bd879ac737921bfa2529a6fea15961267ad21/library_600x900_2x.jpg",
      "library_hero": "…/library_hero.jpg", "main_capsule": "…/capsule_616x353.jpg" } },
  { "item_type": 0, "id": 620, "success": 1, "name": "Portal 2", "appid": 620,
    "assets": { "asset_url_format": "steam/apps/620/${FILENAME}?t=1790187113",
                "library_capsule_2x": "library_600x900_2x.jpg", "header": "…" } },
  { "id": 999999999, "success": 15, "appid": 0 }
] } }
```
Findings (all VERIFIED LIVE):
- Key results by **`id`**, not `appid` (invalid items come back with `appid: 0`).
- `success == 1` → found. `success == 15` → invalid/unknown app.
- Asset values are **either** a bare filename (older games: `library_600x900_2x.jpg`) **or** `<40-hex-hash>/<filename>` (newer games and re-uploaded art). The filename is **not fixed**: Dota 2 returns `…/library_capsule_2x.jpg`. Never synthesize the filename — use the string given.
- Full URL = `https://shared.akamai.steamstatic.com/store_item_assets/` + `asset_url_format` with `${FILENAME}` replaced by the asset string. Example (200 OK): `https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3527290/480bd879ac737921bfa2529a6fea15961267ad21/library_600x900_2x.jpg`.
- `library_capsule*` keys can be absent (no portrait art uploaded) → go to the fallback chain.

## 2. Cover art CDN

VERIFIED LIVE (appid 620, all returned the same 145,080-byte JPEG):
```
https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/620/library_600x900_2x.jpg   (primary host)
https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/620/library_600x900_2x.jpg
https://cdn.cloudflare.steamstatic.com/steam/apps/620/library_600x900_2x.jpg                     (legacy path)
https://steamcdn-a.akamaihd.net/steam/apps/620/library_600x900_2x.jpg                            (legacy host)
https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/620/library_600x900.jpg      (1x, 52 KB)
https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/620/header.jpg               (460×215)
```
**What has changed vs. common knowledge:** the un-hashed path is **no longer reliable**. For PEAK (appid 3527290) both `…/apps/3527290/library_600x900_2x.jpg` and `…/apps/3527290/header.jpg` return **404**; only the hashed path from `GetItems` works. Invalid apps 404 as well. A 404 is `text/html`, 146 bytes — validate `Content-Type` starts with `image/` and status 200.

Sizes: `library_600x900.jpg` = 600×900, `_2x` = 1200×1800 (2:3 portrait). `header.jpg` = 460×215.

**Resolution chain (implement exactly in `CoverURLs` + `ImageCache`):**
1. `GetItems` `library_capsule_2x` (hashed-aware URL)
2. `GetItems` `library_capsule`
3. Un-hashed `https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{id}/library_600x900_2x.jpg` (covers the case where GetItems failed / offline-first)
4. `GetItems` `header`, else un-hashed `…/apps/{id}/header.jpg` → composited onto a generated placeholder (landscape art pasted into the top of a titled cover).
5. Pure generated placeholder cover with the title (no network).

A miss at every step is remembered for 7 days (see ARCHITECTURE `ImageCache`) so we do not hammer the CDN.

## 3. Store details — `store.steampowered.com/api/appdetails`

VERIFIED LIVE:
- `GET https://store.steampowered.com/api/appdetails?appids=620` → `{"620":{"success":true,"data":{…}}}`, keyless. `data` includes `name, short_description, developers[], publishers[], genres[{id,description}], release_date{coming_soon,date:"Apr 18, 2011"}, header_image (hashed URL), achievements{total,…}, metacritic, categories`.
- Invalid app → `{"1":{"success":false}}` HTTP 200.
- Multiple appids without `filters=price_overview` → **HTTP 400**. It is effectively one app per call.
- Rate limit is unofficial: community-reported ~200 requests / 5 min per IP, then 429/403 for several minutes.

**v1 decision: not used.** Nothing on the v1 box needs it (title comes from GetOwnedGames, art from GetItems). It is the natural input for the future AI blurb (genres, developer, release date); the `BackOfBoxContext` reserves an optional `storeDetails` slot for it. See OPEN_QUESTIONS Q7.

## 4. "Date purchased"

Finding: **not obtainable with a user Web API key.** Confirms the lead's belief.
- `GetOwnedGames` has no acquisition timestamp (only `rtime_last_played`).
- `ISteamUser/CheckAppOwnership` returns an acquisition `timestamp` but is a **publisher-key-only** method and only for the publisher's own apps.
- The per-license "Date acquired" table exists only at `https://store.steampowered.com/account/licenses/`, behind a logged-in session cookie. Scraping it would require the user's Steam login in a web view — rejected for v1 (credentials policy, fragility).

**v1 behavior:** `purchaseDate: Date?` is user-editable, defaults to `nil`. The back of the box shows "Purchased: —" plus two honest proxies: **Last played** (`rtime_last_played`) and **On shelf since** (first time this app saw the game in the library). Pinned as OPEN_QUESTIONS Q1.

## 5. Caching / rate-limit plan

| Data | Where | TTL / refresh |
|---|---|---|
| Owned games + firstSeen map (`OwnedLibraryCache`) | `Application Support/SteamShelf/library-<steamid>.json` (not Caches: firstSeen must survive purges) | refreshed on launch if > 6 h old, and on "Refresh Library" |
| GetItems asset map | inside `OwnedLibraryCache.assets` | refreshed with the library, only for appids missing from the map or when the library refresh is manual |
| Cover images | `Caches/SteamShelf/covers/{appid}.jpg` (+ `{appid}.placeholder.png` never cached — regenerated) | forever until Caches is purged; "Refresh Library" does NOT refetch images |
| Image misses | `Caches/SteamShelf/covers/misses.json` `{appid: Date}` | retry after 7 days |
| Achievements | inside `ShelfEntry.stats` (the document) | refetched when a box is opened and `fetchedAt` > 6 h, and by "Refresh Stats" (shelved games only, max 4 concurrent) |

Worst realistic day: library refresh (1 call) + GetItems (N/100 calls) + achievements for shelved games (≤ a few hundred) ≪ 100k.

---

## 6. 3D engine research

### SceneKit
- DOCUMENTED (WWDC25 "Bring your SceneKit project to RealityKit"): SceneKit is **soft-deprecated** across all Apple platforms, in maintenance mode ("critical-bug only"), no new features; no hard-deprecation date announced. Xcode 26+ shows deprecation warnings on SceneKit symbols.
- Pros: very large training corpus → models write it fluently; synchronous `SCNMaterial.diffuse.contents = NSImage`.
- Cons: deprecation warnings in a brand-new Swift 6 project; `SCNSceneRendererDelegate` callbacks on the render thread fight Swift 6 strict concurrency (non-Sendable `SCNNode` touched off-main → errors/warnings); `SceneView` SwiftUI wrapper is limited on macOS.

### RealityKit on macOS (15+)
- `RealityView` is available on macOS 15+ (not AR — renders a virtual scene in a SwiftUI view). DOCUMENTED.
- Textures: `try await TextureResource(image: CGImage, options: .init(semantic: .color))` (async initializer, macOS 15). Materials: `PhysicallyBasedMaterial` / `SimpleMaterial` / `UnlitMaterial` with `baseColor = .init(texture: .init(texture))`.
- Meshes: `MeshResource.generatePlane(width:height:)` produces a plane in the XY plane facing +Z; `generateBox(...)` exists but its per-face material index order and UV orientation are easy to get wrong → build the box from 6 planes (deterministic).
- Per-frame hook: `content.subscribe(to: SceneEvents.Update.self) { event in … }` inside the `RealityView` make closure; runs on the main actor, so Swift 6 is happy.
- Gestures: plain SwiftUI `DragGesture` attached to the `RealityView` works on macOS; entity-targeted gestures would need `InputTargetComponent` + `CollisionComponent`, which we do **not** need (we rotate the whole box on any drag in the stage).
- Lighting: `DirectionalLight` / `PointLight` entities; camera: `PerspectiveCamera` entity.
- Dynamic textures: render any SwiftUI view with `ImageRenderer` → `CGImage` → new `TextureResource` → swap the material on the back-face entity.

### Decision — hybrid: 2D SwiftUI shelf + RealityKit (`RealityView`) for the single opened box
The shelf (up to 16 boxes on screen plus a page-slide animation) is 2D SwiftUI — layered images, gradients, shadows and a small skew for the spine sliver — which is the most reliable way for generated code to compile first time and hold 60 fps, and it is exactly how the 2007 Delicious Library/iBooks look was actually drawn. Only the opened box is real 3D, built in RealityKit from six textured planes with a SwiftUI-rendered back face; RealityKit is Apple's stated forward path, avoids SceneKit's deprecation warnings and render-thread concurrency friction under Swift 6, and the needed API surface (`RealityView`, `PerspectiveCamera`, `DirectionalLight`, `TextureResource(image:)`, `SceneEvents.Update`) is small enough to specify exactly. The 2D→3D handoff is hidden by flying a 2D image of the cover to the exact on-screen size of the 3D front face and cross-fading, so no engine has to render the shelf.

Sources: [WWDC25 session 288](https://developer.apple.com/videos/play/wwdc2025/288/), [Bringing your SceneKit projects to RealityKit](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit), [Steam Web API terms](https://steamcommunity.com/dev/apiterms), [Steamworks IPlayerService](https://partner.steamgames.com/doc/webapi/IPlayerService), [xPaw Steam API reference](https://steamapi.xpaw.me/).

## 7. Deployment target

**macOS 15.0.** It is the floor for `RealityView` on macOS and the async `TextureResource(image:options:)` initializer; it also gives `@Observable`, SwiftData, `openSettings`, `.push` transitions and `DragGesture.Value.velocity`. Nothing in v1 needs a macOS 26 API, and 15.0 avoids accidentally reaching for Liquid Glass APIs that would fight the skeuomorphic look.
