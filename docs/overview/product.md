# Product overview

Steam Shelf turns a Steam library into a wooden bookcase of game boxes. It is a native macOS 15+ app (SwiftUI, with
RealityKit for the one opened box), distributed outside the App Store with Sparkle updates.

## The shelf
- **The window is the bookcase.** A walnut crown rail holds the brass nameplate, page plate, refresh knob, lights
  knob and settings knob. Each stile holds an inlaid page handle. The base rail shows status. The bay in between
  flexes with the window; boxes stay 2:3 and stand behind the front edge of their plank.
- **Pages of 4×4.** Handles show the neighbouring page number; single click slides a page, double-click jumps to
  the first or last. Arrow keys, Home/End, ⌘←/⌘→, and trackpad or Magic Mouse swipes also turn pages.
- **Shelf lights** (⌘L): warm LED strips under the crown and each plank, tuned against reference photographs.
- **Arrangement**: alphabetical until you drag a box; then the order is yours and persists. Dragging over a handle
  flips the page. *Shelf ▸ Arrange Alphabetically* restores the sort.
- **Covers** come from Steam's store CDN (portrait "library" art, with hashed and legacy paths and a header-art
  fallback), cached on disk. Games without art get a generated placeholder cover.

## The opened box
- Click a box: it lifts, flies to the centre of the bay and cross-fades into a real 3D box. Drag to spin with
  inertia; Space flips it; Escape, Close or clicking the backdrop returns it to its slot.
- **The back label** is a vintage exhibit card: title, tagline, your star rating, purchase date (manual: Steam does
  not expose it), hours played, last played, on-shelf-since, achievements, a template quip from the local
  "shelf-keeper", and your handwritten note on an index card. *Edit Label* slides in a panel; the 3D back
  re-renders as you type.
- **Play / Install**: opens the game's own app bundle from its Steam install folder; falls back to the Steam
  client (`steam://rungameid`) when no bundle is found or the game isn't installed.
- **Notes** (games with a personalizer, currently Baldur's Gate 3): the Shelf-Keeper reads every save file,
  computes the patterns (gaps, reloads, late-night saves, party attendance…), digs into the latest save's journal
  (quests, conversations, dice rolls), and asks an AI service to write a fond roast: a tagline, a one-line blurb for
  the back of the box, five or six observations, and a character reading of your playstyle. Any AI service with an
  API key works; nothing is sent until you press *Write Notes*.

## Settings
- **Library tab**: Steam Web API key (Keychain), SteamID or profile URL, Connect, the owned-games checklist with
  search/filter/sort, Refresh Library / Achievements.
- **Shelf-Keeper tab**: one-time grant of the Steam folder (security-scoped bookmark), the time zone the saves were
  played in, the AI service (presets + custom address), its key (per service, Keychain), and the model (listed from
  the service).

## Sharing
- *File ▸ Export Shelf…* writes a `.steamshelf` JSON document (the complete shelf: selection, order, ratings, notes,
  Shelf-Keeper notes, cached stats). *Import Shelf…* replaces the current shelf after confirmation.
- Updates: automatic daily check plus *Steam Shelf ▸ Check for Updates…*, via Sparkle from a public GitHub feed.

## Deliberately not built yet
- **Peer-to-peer shelves.** The document format and a `ShelfSource` abstraction are in place; a friend's shelf is
  just another source. Transport is undecided (see decisions Q9).
- **Personalizers for other games.** The protocol takes one file per game; Baldur's Gate 3 is the only one.
- **Deeper BG3 mining**: the Osiris story database (deaths, romances, choices) is unparsed; the journal gave enough.
- **Store details** (genres, developer, release date) from Steam's `appdetails`: reserved for a later pass.
