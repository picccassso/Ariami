# Changelog

Down below is a summary of all the changes made under each update!

Thank you for those that actually support and use this project at all! :D

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
