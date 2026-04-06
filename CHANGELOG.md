# Changelog

This is a massive update, I have done a lot of work to make Ariami better and more usable, some edge cases are not 100% covered still, however, I am more than proud of where I have come with it thus far, and I hope you enjoy using it too.

Down below is a summary of all the changes made since version 3.2.0, and since this is a big update, I am jumping up to 4.0.0!

Thank you for those that actually support and use this project at all! :D

---

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
