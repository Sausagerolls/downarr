# Downarr — Progress log

Newest first. Update this before/after each work chunk so a new session can resume cold.

## Status: feature-complete across five services, built and running

- [x] Probe every live API, record shapes in `docs/API-NOTES.md`
- [x] `PLAN.md`
- [x] Project skeleton — `project.yml` (XcodeGen), `build.sh`, `build-clt.sh`, `run.sh`
- [x] Core: Config/ConfigStore, HTTPClient + JSONValue, ImageLoader, Formatters, ToastCenter
- [x] Design system: Theme + Components (cards, poster, stat tiles, pills, banners)
- [x] Clients + stores for Sonarr, Radarr, Jellyfin, NZBGet, Deluge
- [x] App shell: AppState, sidebar with live health dots + transfer footer, router, `Go` menu
- [x] Dashboard, Activity (merged queues + both download clients), Calendar, Settings
- [x] Sonarr views: library (grid/table), series detail with season accordion, add, wanted, history
- [x] Radarr views: library, movie detail with media info, add, wanted, history
- [x] NZBGet views: queue with bulk actions, add-by-URL, history with failure decoding, server page
- [x] Jellyfin views: libraries, browser with paging, item detail, metadata editor, identify, images
- [x] Deluge views: torrent list with filters and bulk actions, server page, add magnet/URL
- [x] App icon (`Tools/IconGen`, `./make-icon.sh`)
- [x] `./diagnose.sh` — headless check of every client against the live servers
- [x] Built, launched and smoke tested against the live stack

### Not verified on screen yet

The detail screens and sheets — series detail, movie detail, Jellyfin item detail, metadata
editor, identify, images, add-series/add-movie, calendar, settings. They compile, and every
network call behind them has been exercised directly against the servers, so the risk is cosmetic.
SwiftUI poster links are not exposed to accessibility, so they cannot be clicked from a script.

### Ideas not yet built

- Sonarr/Radarr blocklist and manual-import screens
- Jellyfin cast/crew editing (people are display-only) and collection membership editing
- NZBGet per-file view and server-volume statistics; Deluge per-file priorities and peer list
- A real month-grid calendar instead of the day-grouped agenda

## Log

### 2026-10-13 — Mac App Store prep
Bundle ID now `com.jakewatts.downarr` (team J4UJD4Z33J). Added sandbox entitlements, privacy
manifest, asset-catalog icon, encryption flag and `./archive.sh`; a signed `.pkg` exports and a
sandboxed build works against the live stack. NZBGet queue Pause button became a menu that also
pauses post-processing and scanning; the Server page has per-subsystem controls. Remaining
submission work is listed in `APP-STORE.md`.

### 2026-09-16 ~08:30 — Deluge added as a second download client
`Sources/Downarr/Deluge/` (models, client, store, views) plus integration into the sidebar,
router, `Go` menu (`⌘D`), dashboard, activity merge and settings. Verified against the live
server: 23 torrents, one downloading, Label plugin enabled with a `radarr` label.

Notes from building it:

- Deluge's web UI authenticates with a **password only** — the username is ignored. The login
  returns a `_session_id` cookie that URLSession replays; an expired session shows up as JSON-RPC
  error code 1, which the client treats as "log in again and retry once".
- `web.update_ui` keys torrents by infohash and **does not repeat the hash inside the object**.
  The first build failed at runtime with `keyNotFound: "hash"` because a stored `hash` property
  makes Swift's synthesized decoder demand it — fixed by filling it in from the dictionary key and
  excluding it from `CodingKeys`. The app's own error banner surfaced this immediately.
- Radarr already had Deluge configured (Sonarr is usenet only), and a Servarr queue record's
  `downloadId` is the torrent infohash — so Activity joins the two exactly, with the release name
  as a fallback.

**Also fixed a startup regression this exposed.** With a fifth service in `bootstrap()`, the
dashboard came up showing 0 series / 0 movies while Deluge and NZBGet were fine. It was not load
or a timeout — `./diagnose.sh` (new) runs every client against the live servers headlessly and
everything passed in ~1.5s, concurrently included. The cause is macOS re-evaluating local-network
permission for a freshly re-signed build: the first requests are refused, the polling clients
recover on their own, and the one-shot loads did not. `bootstrap()` now retries whatever failed
after 2s and 6s, and the dashboard shows a retry banner naming the services that are not
connected.

Tooling added: `./diagnose.sh` + `Tools/Diagnose/main.swift`.

### 2026-09-16 ~07:45
App icon built and shipped: `Tools/IconGen/main.swift` draws it with CoreGraphics (blue-to-violet
rounded square, white download arrow dropping into a cyan tray) and renders every size in the
`.iconset` from the vector description rather than downscaling one 1024px master, so 16pt and 32pt
stay crisp. `./make-icon.sh` regenerates `Sources/Resources/AppIcon.icns`; both build paths set
`CFBundleIconFile`. Verified in the Dock at real size.

**Also fixed four changes that had silently never landed.** The cause was not a string mismatch as
first reported: `/usr/bin/python3` is an `xcrun` shim, so while the Xcode licence was un-accepted
every scripted edit exited without running and printed only the licence warning. Re-applied with
the editor and grepped to confirm:

1. `JellyfinLockableField` still offered `SortName` and `ExternalId` — the 400-on-save bug was
   still live in the shipped app.
2. The `LockedFields` filter in the metadata editor.
3. The Help menu still force-unwrapped `URL(string:)` on each service address (crash if a host is
   cleared in Settings).
4. `build.sh` had no Command Line Tools fallback.

Rule for this repo: **after any scripted edit, grep for the new text before trusting it.**

### 2026-09-15 ~21:20 — handover state
`build/Downarr.app` is a **release build**, ad-hoc signed, running, and pointed at the live stack.
Local-network permission is granted on this machine.

Verified on screen: sidebar with live health dots and transfer footer, Dashboard (real counters,
health warnings, Jellyfin recently-added artwork), Sonarr series grid (689 posters with completion
bars and missing badges), Jellyfin libraries page, Jellyfin browser (paging over 60,552 items,
opens on the Movies library).

**Not yet verified on screen**: the detail screens and sheets (series detail, movie detail, Jellyfin
item detail, metadata editor, identify, images, queue, activity, calendar, settings). They compile
and reuse the same primitives as the verified screens, and their network calls were all exercised
directly against the servers, so the risk is cosmetic rather than functional. SwiftUI poster
`NavigationLink`s are not exposed as accessibility buttons, so they could not be clicked from a
script — check those by hand first.

Lesson worth keeping: two patches applied with a Python string-replace silently matched nothing and
the "fix" shipped as a no-op until it was grepped for. Always grep for the new text after a
scripted edit.

### 2026-09-15 ~21:00
All modules written and the app verified running against live data (689 series, 492 movies, 60,552
Jellyfin items). Things found by testing rather than reading:

- **`xcodebuild` stopped working mid-build**: the installed Xcode's licence has not been accepted
  (`sudo xcodebuild -license accept` fixes it). Added `build-clt.sh`, which compiles with the
  Command Line Tools toolchain and assembles the bundle by hand, and made `build.sh` fall back to
  it automatically. The same shim blocks `/usr/bin/python3` intermittently — see the warning below.
- **Jellyfin rejects unknown `LockedFields` names with a 400 that fails the whole save.** Probed
  every value: `Name, Overview, Genres, Cast, Tags, Studios, ProductionLocations, OfficialRating,
  Runtime` are valid; `SortName` and `ExternalId` are **not**. Removed from the editor, and the
  outgoing array is filtered as a belt-and-braces guard.
- macOS asks for local-network permission on first launch; until granted every request fails with
  "The Internet connection appears to be offline". Granted on this machine.
- Write paths confirmed live: `PUT /series/1` 202, `PUT /movie/1` 202, `POST /Items/{id}` 204, and
  a Banner image upload + delete cycle on a test movie (item left exactly as it was found).

### 2026-09-15 ~20:30
Logic layer complete and compiling: 4 API clients, 4 stores, design system, app shell, dashboard,
full Sonarr surface. Notable decisions made while writing it:
- Writes to Sonarr/Radarr/Jellyfin **patch the raw JSON document** (GET → mutate keys → PUT/POST)
  because all three replace the whole object on write; typed models would silently drop fields.
- `Type` is not a legal Swift member name, so Jellyfin models map that one key via CodingKeys.
- NZBGet models keep PascalCase property names to mirror its JSON-RPC payloads exactly.
- Swift 5 language mode; `build.sh` greps the xcodebuild log and fails loudly.

### 2026-09-15 ~19:50
Verified connectivity and response shapes for Sonarr 4.0.19, Radarr 6.3.0, Jellyfin 12.0.0,
NZBGet 26.2. Toolchain: Xcode 26.6, Swift 6.3, xcodegen present. Plan written.
