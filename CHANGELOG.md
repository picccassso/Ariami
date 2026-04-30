# Changelog

Down below is a summary of all the changes made under each update!

Thank you for those that actually support and use this project at all! :D

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
