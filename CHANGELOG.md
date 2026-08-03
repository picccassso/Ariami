# Changelog

Down below is a summary of all the changes made under each update!

Thank you for those that actually support and use this project at all! :D

---

## 5.1.0

Ariami 5.1.0 is the Ariami Connect release. 5.0.0 shipped Connect as a first
version; this one takes it apart and rebuilds it to survive real households —
devices that sleep, drop off Wi-Fi, get force-quit, or run three different
Ariami versions at once. Alongside that, the premium desktop player picks up
the library tools it was missing: an All Songs view, multi-select, and sidebar
search.

### Highlights
- Ariami Connect is now version-negotiated per peer, so a phone on 5.1.0 and a
  TV still on 5.0.0 agree on what they can ask of each other instead of
  guessing.
- Connect ownership is fenced and revision-safe — handoffs no longer race,
  stale devices can't reclaim a queue they've lost, and playback continues when
  the controlling client exits.
- Connect commands are bounded and reliably delivered rather than fire-and-forget.
- The desktop player gains an All Songs view, multi-select with queue and
  playlist actions, and sidebar library search.
- Song likes are now available from the overflow menu on both desktop and mobile.
- Albums whose tracks were scattered across inconsistent tags are grouped back
  into one album.

### Full changes

- Negotiated the Ariami Connect protocol version per peer, so mixed-version households agree on a common command set
- Advertised per-client Connect command capabilities so controllers only offer what the target can actually do
- Split Connect queue and progress state so a progress tick no longer republishes the whole queue
- Made Connect handoffs revision-safe, ending races where two devices both believed they held the queue
- Fenced stale Connect ownership work so a device that lost ownership stops acting on it
- Bounded and reliably delivered Connect commands instead of dropping them silently
- Hardened the Connect transport
- Made Connect failover safe, and resumed playback after owner loss
- Continued Connect playback when the controlling client exits
- Kept the Connect owner audible across foreground resumes
- Kept Connect controllers uninterrupted while another device is being driven
- Made Ariami Connect say which device is which, instead of showing anonymous entries
- Hardened Connect queue ownership across desktop, mobile and TV
- Sent single-song queue additions to the active Connect device rather than the local queue
- Cleared the active Connect device's queue from the desktop controller
- Prevented cleared queues from returning
- Kept mobile handoffs playing
- Mirrored Connect playback in the mobile notification
- Held the requested Cast volume until the receiver confirms it
- Measured and characterized Connect with a fixture-backed baseline before hardening it
- Documented Ariami Connect in one place
- Added an All Songs view and multi-select to the desktop player
- Added Premium sidebar library search
- Added queue and playlist actions to library multi-select on mobile
- Made the multi-select tick visible on every theme
- Added song like menu actions to desktop and mobile
- Remembered the Premium desktop window state across restarts
- Hid the batch Download action when this machine hosts the library
- Grouped tag-scattered compilations into one album
- Reduced playback progress UI work
- Advertised the port clients can actually reach
- Hardened Docker port and endpoint discovery, and clarified custom-port mappings
- Bundled JACK in the Linux AppImage and fixed its desktop library compatibility
- Shipped a thank-you note inside the desktop disk image
- Stopped CI rebuilding the desktop on every push

---

## 5.0.0

Ariami 5.0.0 is the largest release yet. It makes Ariami feel genuinely connected across devices with shared playback, synced statistics, pins, profile pictures, and playlist edits, then builds a whole listening-history experience on top of it — credited artists, period views, Recently Played, offline caching, and Spotify history imports. Mobile gains a graphic equalizer, gapless playback, and a proper tablet layout, the server gains zero-config LAN discovery and a serious security pass, and the CLI becomes something you can genuinely run headless or in Docker.

There is an enormous amount packed into this one, and I hope both listening and self-hosting feel better than ever! :D

### Highlights

- Added Ariami Connect for transferring, mirroring, and controlling playback across signed-in clients, with device renaming, ghost-device eviction, atomic queue clearing, and far more reliable handoffs.
- Overhauled listening statistics with server-derived credited-artist rollups, a day/week/month/year period selector, uncapped lists, offline caching and outbox overlays, and a Recently Played history screen.
- Added Spotify Extended Streaming History imports from the CLI web dashboard and the Desktop app, with match previews, import status reporting, and source-scoped removal.
- Added a graphic equalizer with Android and iOS support, plus gapless mobile playback.
- Optimized the mobile app for tablets with an extended sidebar, docked now-playing card, and landscape full player.
- Added zero-configuration LAN server discovery over UDP beacons and mDNS/DNS-SD.
- Completed a security hardening pass across the server, CLI, and mobile, including gated first-owner registration and hardened request handling.
- Made library scanning, metadata extraction, and playlist detection survive large, messy libraries, with M3U import and an auto-import/suggestion workflow.
- Added a shared search engine with tiered ranking, diacritic folding, transliteration, and keyboard-layout correction.
- Added Ariami TV license activation with a server-side license relay.
- Added complete CLI Docker packaging, multi-arch GHCR publishing, and per-package documentation for Core, CLI, Desktop, and Mobile.
- Overhauled the headless CLI experience with clearer startup details, new server flags, a real health-checking status command, and better diagnostics.
- Added automated CLI release archives for Linux x64, Raspberry Pi arm64, macOS arm64, and Windows x64, including a Windows launcher and startup coverage.
- Unified Ariami Connect and Google Cast into one responsive playback-output chooser across the mobile full player and mini player.

### Full changes

- Fixed the mobile tab back gesture collapsing two navigation levels at once and exiting the app instead of returning to the library
- Fixed CLI rescan tracking, music folder validation, and mobile catalog recovery when sync tokens are stale
- Fixed album tracks being dropped as playlist duplicates while keeping generated playlist copies deduplicated
- Added Ariami Connect playback transfers, remote queue selection, and playback control across signed-in clients
- Added live remote playback mirroring for the current song, queue, progress, play state, shuffle, and repeat controls
- Fixed Connect state recovery after reconnects and server restarts so clients no longer remained stuck on stale playback
- Fixed repeated Connect handoffs drifting in position or missing the first playback update after a transfer
- Added automatic Connect playback failover to the most recent controller when the active player disconnects, while allowing quick reconnects to reclaim the session safely
- Fixed repeat-one carrying across explicit Connect skips, queue selections, and remote play requests
- Unified Ariami Connect and Google Cast into one mobile playback-output chooser and removed duplicated player and settings controls
- Allowed an account to remain signed in on multiple distinct devices while replacing stale sessions from the same installation
- Bound stream tickets to their requested quality so concurrent clients could not reuse a ticket for a different stream profile
- Added account-wide listening statistics with durable offline event queues, idempotent server rollups, live refreshes, account isolation, and backup import compatibility
- Synced pinned albums and playlists per account with live updates while preserving offline fallback data
- Added server-synced JPEG and PNG profile pictures that can be uploaded, changed, or removed from the mobile profile screen
- Added per-account server playlist renaming, reordering, adding, and removing as non-destructive edits that survive library rescans
- Synced imported mobile playlist copies with server edits in both directions and queued offline changes for replay after reconnecting
- Fixed mobile playlist edits loading during startup, reconnects, manual refreshes, and live update notifications
- Added Remove from Playlist to each playlist song's overflow menu as an alternative to swiping
- Added a unified CLI startup summary with dashboard and network addresses, data and music paths, authentication state, and security guidance
- Added `--no-browser`, `--verbose`, and persisted `--host` CLI start options plus `ARIAMI_DATA_DIR` for relocating server data
- Upgraded `ariami_cli status` into a health check with PID, uptime, live reachability, build mismatch detection, and data and backup details
- Fixed headless first-run prompts at end-of-input, graceful shutdowns that could leave the process alive, and hidden shutdown messages during setup
- Improved CLI startup and usage errors with actionable stderr output, optional stack traces, and correct usage exit codes
- Added a headless-server guide covering SSH setup, backups, updates, systemd, security, and manual checks
- Added a release workflow that builds and verifies CLI archives for Linux x64, Raspberry Pi arm64, macOS arm64, and Windows x64
- Added a Windows CLI launcher and expanded setup instructions for each supported platform
- Fixed the CLI crashing at startup on Windows when it tried to watch an unsupported termination signal
- Added a multi-stage CLI Docker image, Docker Compose configuration, persistent data volume, health check, and server-mode process handling
- Added zero-configuration host networking for CLI containers on Linux
- Added `ARIAMI_ADVERTISED_HOST`, `ARIAMI_ADVERTISED_LAN_HOST`, and `ARIAMI_ADVERTISED_TAILSCALE_HOST` overrides so container pairing advertises reachable addresses
- Made the setup wizard detect containers, complete setup without an unavailable background transition, and explain container networking on the Tailscale step
- Fixed offline downloads vanishing when screens opened during startup before the restored queue was broadcast
- Added a graphic equalizer to mobile with 9 built-in presets, user-saved presets, a frequency-response curve, and native Android and iOS support
- Fixed iOS playback hanging forever with the equalizer pipeline by scoping audio effects per platform
- Added gapless mobile playback
- Hardened library scanning and tagging for large messy libraries, surviving unreadable directories, dead scanner isolates, and formats `dart_tags` cannot parse
- Added zero-configuration LAN server discovery via a UDP beacon and an mDNS/DNS-SD advertiser, with a matching client browser
- Synced client-created playlists and custom playlist cover photos across an account's devices
- Fixed iOS streaming over Tailscale by exempting cleartext HTTP from App Transport Security
- Removed ghost devices from Ariami Connect with protocol-level WebSocket pings and timeouts on relayed commands
- Made the CLI exit quietly when its output pipe closes early instead of crashing on a broken pipe
- Updated the app icon with new Ariami artwork across mobile, desktop, and the README
- Regenerated the mobile wordmark masks from the new icon artwork
- Added renameable device names synced through the server so Connect no longer lists identical devices
- Improved download reliability with background continuation, stall fixes, and sturdier download jobs
- Added smarter playlist detection with additive folders, M3U/M3U8 import, and a suggestion approval workflow
- Fixed duplicate-quality ties so the surviving song ID is deterministic across filesystems
- Added a shared search engine in core with tiered ranking, diacritic folding, Cyrillic transliteration, and QWERTY/ЙЦУКЕН layout correction, adopted by mobile search
- Exposed engine matching for order-preserving find-in-page style filters
- Removed the white border from the Ariami app icon and regenerated the launcher icons
- Added tap-the-downloaded-tick to remove a playlist or album's downloads on mobile
- Added automatic import of high-confidence playlist folders while keeping medium-confidence ones as suggestions
- Hardened the mobile setup flow and added an owner-controlled sign-in account picker with dashboard toggles
- Counted direct-from-disk playback in server stream accounting with delivery-typed stream tickets
- Fixed the mobile playlist downloaded tick counting stale entries with no library match
- Added a server-side credited-artist stats derivation layer with rebuildable rollups and day/period/artists/albums endpoints
- Added credited-artist and period listening stats to mobile with a floating day/week/month/year selector
- Unified mobile stats tracking onto the shared core engine and added playback source context to listening events
- Completed a security hardening pass across server, CLI, and mobile covering first-owner registration, rate limiting, request logging, file permissions, body caps, CORS, and container privileges
- Polished Desktop setup onboarding with contextual help on every step and a warmer welcome
- Added a TV account-picker toggle to the Desktop dashboard Users tab
- Improved CLI onboarding guidance
- Made mobile server disconnect reset cleanly into offline mode and removed the dedicated Server Offline screen
- Added a Cooler Downloads mode and serialized post-download artwork extraction to reduce device heat during bulk downloads
- Refined mobile playlist reordering
- Added live aggregate progress rings and cancellation state to mobile album and playlist download buttons
- Added Ariami TV license activation and a server license relay usable from mobile, Desktop, and the CLI web dashboard
- Softened the TV license card's stored-license copy
- Improved streaming and sync performance on Tailscale paths with progressive cold transcodes, gzipped API responses, at-least-once Connect delivery, and a pooled keep-alive mobile HTTP client
- Synced Liked Songs across devices through the shared account playlist contract
- Fixed Unicode metadata and recovered embedded JPEG and PNG artwork missed by `dart_tags`
- Hardened cross-format metadata importing with deterministic tag precedence, bounded parser inputs, and ffprobe/ffmpeg artwork fallbacks
- Protected queue swipe-removal with an undo toast and allowed queue edits over Ariami Connect
- Added the Ariami privacy policy
- Improved dynamic artwork theming so small accent details cannot dominate the UI
- Set the Ariami Mobile Android package name to `app.ariami.mobile`
- Fixed playlist bulk downloads pulling in songs from playlists not present in the mobile library
- Opened the mobile listening stats view on today's period by default
- Synced the themed listening stats period selector
- Repaired missing album metadata in mobile stats and download records
- Fixed the Sonic submodule not being fetched in CLI artifact builds
- Hardened license server test startup against parallel CI port claims
- Improved remote playback sync and made ranged original-quality downloads resumable with ETag and If-Range
- Fixed current-year listening stats totals dropping imported baseline hours
- Added a tappable playtime units toggle with a first-run hint to listening stats
- Hid uncounted listens from stat rankings while preserving partial listening in aggregate playtime
- Allowed playlists to share display names by keying identity on server IDs and import mappings
- Fixed nondeterministic streaming stats widget tests by seeding preferences
- Fixed missing mobile artwork fallbacks for sparse and stale listening-stat identities
- Kept CLI and Desktop scan results visible until the user explicitly continues, with exact attempted-file counts
- Clarified CLI and Desktop scan completion guidance for the new manual flow
- Moved the Desktop library scan ahead of owner account setup
- Fixed unreliable disconnect-server navigation by navigating on confirm and capping the server notify at 3s
- Added a Desktop notification banner when a newer release is available
- Optimized the mobile app for tablets with an extended sidebar, docked now-playing card, landscape full player, and width-capped sheets and settings
- Fixed mobile Connect refresh after app resume
- Added a fallback to the downloaded copy when stream startup stalls
- Cached listening stats per account and server for offline viewing
- Stabilized the owner bootstrap server test against dormant CI VPN and virtual adapters
- Added a mobile Recently Played history screen with deduplicated history, collapsible days, and per-day queue actions
- Changed Clear Queue to keep Now Playing and its position, locally and on an active Connect device
- Made Connect queue clearing atomic with a single `clear_queue` command
- Prevented Connect startup playback races so a pre-welcome phone play wins the session
- Kept mirrored queue identity stable across Connect broadcasts to stop queue rows flickering
- Dropped the redundant output button from the tablet sidebar now-playing card
- Made the stats PLAYTIME and AVG DAILY metrics cycle through hours, minutes, and compact minutes with a remembered unit
- Removed CocoaPods integration from the macOS project
- Ignored Gradle caches repo-wide
- Upgraded dependencies within existing constraints
- Bumped CI Flutter to 3.44.6
- Disabled Jetifier in the mobile Android build
- Deflaked the endpoint discovery test by awaiting the initial probe
- Modularised the streaming stats screen into a focused stats/ feature folder
- Fixed endpoint test cross-contamination from the singleton server's retained discovery callback
- Modularised Core auth and admin handlers into focused auth, admin, and media-ticket modules
- Modularized the CLI dashboard screen into auth, library, refresh, and user modules
- Modularized the listening stats store into schema, ingestion, rollup, and read modules
- Modularized the core metadata extractor into parsing, probe, and artwork part files
- Modularized the mobile playback manager, extracting Connect coordination and lifecycle wiring
- Eliminated the server info endpoint port race by recording the OS-assigned port
- Modularised the mobile API models into focused part files
- Modularised the LibraryManager catalog into focused part files
- Modularised the mobile playlist detail screen into lifecycle, resolution, action, and offline-copy modules
- Showed full listening stats lists instead of capping at 20/50, with `limit=0` support on the server endpoints
- Sped up uncapped listening stats views with lazy list building, memoized credited-artist matching, and instant cached snapshots
- Added auto-skip for queue entries deleted from the server library, with `410 SONG_NOT_FOUND` on stream tickets
- Gated web dashboard owner panels on the signed-in role so non-admin sessions stop collecting 403s
- Added Settings > Downloads > Clean Up Playlists to sweep ghost entries for songs deleted from the server
- Fixed offline library startup on mobile data by treating unconfirmed connections as offline
- Removed CocoaPods from the iOS project in favour of SPM only
- Added an offline outbox overlay so pending plays appear immediately in period listening stats
- Added Spotify Extended Streaming History imports from the CLI web dashboard and the Desktop server app
- Improved Spotify history matching by normalizing title and artist variants and rejecting unsafe matches
- Eliminated Core test port races with atomic OS-assigned port binding
- Bumped to 5.0.0 and added a multi-arch GHCR Docker publish workflow
- Fixed the Docker workflow not fetching submodules, leaving the Sonic source missing
- Fixed Spotify import 1970 timestamps and computed avg daily from distinct active listening days
- Updated the README with expanded client features and corrected session and stats accuracy
- Added per-package documentation for Core, CLI, Desktop, and Mobile
- Ignored Obsidian workspace config
- Fixed mobile cover art leading audio after rapid skips by serializing overlapping song loads
- Fixed mobile library sync stranding rows when the catalog changed mid-bootstrap
- Added Spotify stats removal to the Desktop dashboard
- Added Spotify stats removal to the CLI web dashboard
- Added a Spotify import status line reporting play count, last import, and history span beside the import actions on both dashboards
- Documented listening stats and the Spotify import lifecycle in Core's LISTENING_STATS.md
- Evicted Connect peers whose socket died without a close event by tracking last-seen and sweeping stale peers
- Made mobile Recently Played usable on a years-long history with indexed lookups and lazy day building

---

## 4.4.0

Ariami 4.4.0 is the biggest reliability and polish release so far, with 100+ commits focused on setup, security, Raspberry Pi performance, downloads/offline playback, queue reliability, mobile polish, CI/release builds, start-on-boot, and safe reset tools.

I hope people who use this new version can feel the difference in how much work has gone into making it as good as possible! :D

### Highlights
- Easier pairing with LAN/Tailscale address handling, manual server entry, QR invite tokens, and desktop-generated invite codes.
- Hardened auth and registration flow.
- Major download/offline reliability improvements, including native background downloads and better resume behavior.
- Improved queue behavior, repeat handling, swipe-to-queue, and playback controls.
- Raspberry Pi and Sonic transcoding improvements.
- Mobile UI polish across bottom sheets, mini-player spacing, search, downloads, and CLI mobile dashboard.
- Added CI checks, Android APK release builds, Desktop/CLI start-on-boot, and safe reset/factory reset tools.

### Full changes

- Excluded the dashboard from mobile client counts and softened QR auth error messaging
- Advertised both LAN and Tailscale addresses for mobile pairing across the dashboards and CLI web UI, fixing Tailscale being preferred on the same LAN
- Improved mobile download resume reliability
- Improved mobile download reliability with native background download support
- Fixed mobile downloads and stream warmup
- Fixed Raspberry Pi playback performance
- Added a /docs folder and Raspberry Pi 3 performance findings from real-world usage
- Fixed the Pi download job and catalog cleanup
- Added Raspberry Pi optimisations
- Updated the Sonic transcoding integration
- Tuned transcode concurrency per platform
- Improved full player queue and cast controls
- Consume one-shot queue entries after playback
- Added swipe-to-queue across song lists
- Unified bottom sheet design with mini-player awareness
- Grayed out the delete button in download settings when no songs are downloaded
- Grouped the downloads screen by album and virtualized the lists
- Fixed downloads summary percentage and active count
- Migrated add-to-playlist sheets to bottom sheets and added undo to the confirmation toast
- Fixed playback stats after lifecycle checkpoint
- Fixed the queue swipe popup
- Fixed CLI library scanning
- Fixed download lag for singles
- Polished startup screens
- Stopped tracking iOS SwiftPM resolution files
- Updated Flutter dependencies
- Fixed macOS desktop quit and shutdown races
- Fixed real-time download badges on album, playlist, and search screens
- Aligned playlist download with album action row placement
- Added a per-track overflow menu to playlist detail songs
- Auto-refresh Tailscale/LAN endpoints when the network changes after server start
- Added repeat-all wrap-around to the Now Playing carousel and previous skip
- Fixed song title truncation in the marquee and metadata extraction
- Moved playlist edit and delete actions into an action bar bottom sheet
- Resolved cross-platform safe-area spacing and bottom sheet overlaps on iOS
- Updated dependencies
- Fixed the destructive server disconnect reset flow
- Disabled the playlist download button when the playlist is empty
- Implemented multi-select and batch downloads with a robust local fallback
- Made the batch download bar animate smoothly when dismissed
- Prevented a cover art scrolling loop and visual flash on queue shuffle
- Added a disconnect server button to the login screen
- Wipe all local data on server disconnect
- Made full player skip controls respond to rapid taps
- Fixed queue confirmation toast spacing above the mini player when the keyboard is open
- Implemented library catalog integrity and sync resilience fixes
- Improved the CLI setup flow for headless servers
- Preserve library scroll position when closing the full player
- Show the Disconnect Server option on Connection Status while offline
- Added manual server address refresh across dashboards
- Preserve library scroll position during background refreshes
- Hardened unauthenticated server access
- Secured mobile registration with QR invite tokens
- Fixed macOS desktop quit hang on Cmd+Q and dock quit
- Fixed critical mobile search UX issues
- Fixed CLI web owner auth handoff
- Fixed playlist duplication on backup reimport
- Reorganized the desktop and CLI dashboards into intent-based tabs
- Removed snackbars in favor of less intrusive confirmations
- Stabilized the global download bar for multi-song batches
- Handle already-downloaded items in library batch download
- Replaced album and playlist track popup menus with bottom sheets
- Fixed the CLI web dashboard back arrow loop after setup
- Open the setup browser only after the HTTP server is listening
- Improved Chromecast metadata and notification handoff
- Moved the Now Playing overflow menu to the bottom toolbar
- Fixed the queue reorder drop target for the now playing row
- Added automatic port fallback when 8080 is busy
- Reserve library scroll space for the batch download bar on mobile
- Modularised the library controller, dashboard screen, playlist service, and server runner into focused part files
- Updated tests for hardened auth and the current mobile UI
- Fixed the CLI web build pulling native SQLite FFI
- Updated the Sonic streaming transcoder
- Fixed Pi CLI native bundle packaging
- Publish transcoded cache files atomically
- Added CI checks and fixed CI dependency setup and test failures
- Added Android APK release builds
- Clarified the setup flow and required owner account step across the docs
- Keep the mini player anchored when the keyboard opens
- Added a desktop-style user management dashboard to the CLI
- Hide the Disconnect Server button when the keyboard is open
- Preserve downloaded library items as offline copies
- Improved streamed artwork quality
- Added manual server entry and desktop-generated invite codes for pairing without a QR scan
- Allow a second-device login to take over instead of being blocked
- Fixed a song not playing after adding it to an empty queue
- Fixed CLI connect screen overflow
- Keep the dashboard QR page open when clients are connected
- Fixed the search keyboard gap without hiding the mini player
- Improved mobile search typo tolerance
- Fixed repeat-mode track selection and boundary skips
- Cache the profile image in memory and pre-warm it on boot to stop avatar flicker
- Keep download checkmarks across LAN/Tailscale route switches
- Sped up startup by deferring service init and showing the cached library first
- Fixed downloaded songs not playing on first tap offline
- Silence playback when media volume is muted and unsilence it when raised
- Made the CLI web UI mobile-friendly and fixed pairing-code copy
- Added a Material You themed (monochrome) launcher icon
- Fixed same-name artists splitting on invisible tag characters
- Route queue tap, remove, and clear actions through PlaybackManager
- Reduced queue row flicker on queue updates
- Re-link downloads when album IDs change under metadata normalization
- Stopped queue confirmation toasts from bouncing in the mobile app
- Repaired UTF-8 artist names mangled by truncated ID3v1 tags
- Fixed mobile backup import/export detection
- Fixed YouTube channel album artists in library metadata
- Improved background streaming stats accuracy
- Fixed Android Bluetooth media controls by configuring audio session focus
- Fixed desktop app icons for Windows and Linux
- Simplified Ariami CLI setup output
- Fixed the Android back gesture popping the nested route under the full-screen player
- Added start-on-boot to Desktop and CLI, and fixed the CLI owner-state probe error
- Added Reset Ariami to Desktop and CLI with a safe, music-preserving deleter
- Delete SQLite WAL sidecars during reset so the catalog can be recreated
- Disabled the Chromecast button when offline in mobile players
- Showed the "Added to queue" confirmation for album, playlist, and per-song add-to-queue actions that were previously silent

---

## 4.3.0

- Fixed artist stats double-counting after library moves and imports
- Remap stale song IDs during import and library sync, with auto-healing of playlists and stats after every sync
- Overhauled listening statistics tracking — switched from wall-clock timers to position-based tracking, with debounced DB writes, app-lifecycle flushing, and seek-gating
- Changed library mixed view sorting from last-opened to last-played
- Added search bar when adding songs to playlists
- Added undo snackbar for remove-from-recent and corrected bottom-chrome spacing

---

## 4.2.0

- Fetch Sonic binary via git submodule in CI Pi release workflow
- Handle interrupted downloads with recovery controls on reconnect
- Prompt user before resuming interrupted downloads after reconnect
- Fixed reconnect on app resume and deduplicated restore attempts
- Bundle Sonic in Pi CLI releases and tuned download concurrency limits for Raspberry Pi 5
- Redesigned all settings screens to a modern flat layout with updated typography and a profile header
- Used square corners for library list view tiles for consistency with the grid view
- Stopped the library refresh loop when bootstrap sync is not yet ready
- Added an actionable Profile hub with View Profile navigation
- Implemented a dynamic global theming system with light/dark mode, preset colors, custom colors, and cover art theming
- Applied global theming to the Settings screen and all sub-widgets
- Added horizontal swipe to skip tracks on the mini player
- Prevented redundant artwork network requests by checking local cached files first
- Replaced back button with a Lucide icon
- Implemented static cover art theming option
- Removed the menu button from the main player view
- Reworked the appearance system and polished player and settings UX
- Infer track numbers from common numeric filename prefixes when metadata tags are missing
- Auto-heal mobile album sync mismatches by triggering a fresh bootstrap when local track counts are stale
- Used folder structure as the source of truth for downloaded music classification and fixed playlist/album grouping regressions
- Applied dynamic theming to the Streaming Quality settings screen
- Added an indicator showing which song is driving the current dynamic theme
- Grayed out download icons for songs that are already being downloaded
- Improved animations in the main player and mini player
- Refactored download_manager.dart with added test coverage
- Split PlaybackManager into focused part files without behavior changes
- Split album detail screen into reusable album widgets
- Refactored library_sync_database.dart
- Added user management to the dashboard with a safe account deletion flow
- Upgraded GitHub Actions workflows to v6 runtimes and removed unused CI jobs
- Added user deletion to the Registered Users panel with mobile session invalidation
- Fixed library deletion not actually removing the library from disk
- Enforced a strict song-only cache size limit and decoupled artwork storage from the cache cap
- Reset theme on logout and isolated playback state and pinned items per user
- Added a per-user download and transcode activity board to the desktop and CLI dashboards
- Added local profile image support
- Fixed animation regressions in the main player
- Fixed seek bar position resetting when resuming playback after scrubbing
- Applied dynamic theming to the queue player screen
- Prevented bottom sheet action buttons from being clipped by the mini player and navigation bar
- Removed the download button from search results
- Deduplicated song results that appeared across playlist and source variants
- Hardened player and playlist swipe gestures to prevent accidental track skips
- Replaced the search overflow popup with a bottom sheet and removed the Download action
- Showed Downloaded badge on already-downloaded songs in the options menu
- Disabled "Fast Downloads (Original)" when download quality is set to Medium or Low to avoid conflicting settings

## 4.1.0

- Integrated FFI-based transcoder for improved performance and reliability
- Tuned download pipeline for better throughput and resource usage
- Fixed QR screen redirecting when only the CLI dashboard is connected
- Added client type tracking to distinguish dashboard vs mobile clients in WebSocket connections
- Stats endpoint now reports mobile client count separately from total connections
- Fixed interrupted downloads handling: active/pending downloads now pause cleanly on connection loss or app closure, with recovery controls and auto-resume preference support
- Added reconnect recovery prompt in Downloads so interrupted items can be resumed explicitly after connection is restored
- Fixed resume reconnection flow by triggering immediate reconnect on app resume and deduplicating concurrent restore attempts

## 4.0.0

- Major internal refactoring: split the HTTP server, library manager, and transcoding service into focused part files for maintainability
- Refactored the CLI dashboard screen and desktop dashboard into modular widgets, models, and services
- Refactored the mobile downloads screen into a controller/state/widget structure
- Fixed a long-standing bug with playlist timestamps not being set correctly
- Added Chromecast support: cast music to any Chromecast device on your network
- Chromecast: added volume control overlay on the artwork
- Chromecast: fixed next song not playing on track completion while casting
- Chromecast: fixed music continuing to play after the app is closed during a cast session
- Chromecast: improved handoff and resume reliability for edge cases
- Removed the unnecessary snackbar confirmation on Chromecast connect
- Redesigned the mobile app with a modern, Spotify-inspired layout
- Main player now uses Lucide icons and a cleaner layout
- Queue viewer updated with Lucide icons and shows the currently playing track at the top
- Artwork in the main player is now swipeable to skip tracks
- Added a Chromecast button to the mini player showing connected state
- Duration display now shows hours and minutes instead of minutes only for long playlists and albums
- Library sync is now v2-only; removed legacy `/api/library` reads
- Fixed v2 playlist sync identity and duration propagation
- Fixed v2 bootstrap refresh and legacy playlist backfill detection
- Fixed albums being split when track-level artist tags vary
- Improved song duration extraction: durations are now parsed during scan (preferring Dart MP3 parsing before ffprobe)
- Improved mobile download performance for large libraries
- Added pin-to-top support for albums and playlists in the library view
- Artwork is now cached from downloaded files instead of HTTP requests
- Fixed offline thumbnail loading from downloaded files
- Fixed online thumbnail loading after cache migration
- Fixed manual offline mode not persisting across app restarts
- Added reconnect trigger from library pull-to-refresh, with a shared manual-offline helper
- Fixed album detail hero artwork not being full width on mobile
- Fixed artwork letterboxing and playlist collage seams on mobile
- Fixed gap appearing between the mini player and keyboard when the IME is open
- Fixed extra bottom padding in the full-player overflow menu
- Fixed connected devices table not expanding to full card width on desktop
- Flutter updated to 3.41 with mobile compatibility fixes
- Added a RESET.md guide for resetting Ariami to a clean state
- Fixed CLI dashboard auth so logged-in dashboard sessions no longer block QR/mobile login for the same account.
