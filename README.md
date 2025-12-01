# BMA (Basic Music App)

A cross-platform personal music system built with Flutter. Host and stream your own music library across devices using Tailscale for secure connectivity.

## Architecture

- **Desktop App** (macOS, Linux, Windows): Runs as a local server that indexes your music folder and streams audio to connected clients.
- **Mobile App** (Android, iOS): Connects to the desktop server to browse, play, and manage your music.

## Desktop Features

- Music library scanning with metadata extraction (title, artist, album, year, track number, duration)
- Album categorization with compilation detection
- Duplicate filtering based on file hash and metadata matching
- Real-time folder monitoring for automatic library updates
- HTTP audio streaming with range request support for seeking
- QR code generation for mobile device pairing

## Mobile Features

- QR code scanning to connect to desktop server
- Library browsing (albums, songs, playlists)
- Search with ranking algorithm (exact, prefix, substring matching)
- Audio streaming with background playback support
- Full playback controls (play/pause, skip, shuffle, repeat)
- Queue management with drag-to-reorder
- Mini player and full-screen player views
- Playlist management (create, edit, reorder songs, delete)
- Download songs and albums for offline playback
- Smart caching with LRU eviction for artwork and recently played songs
- Automatic offline mode detection
- Streaming statistics (play counts, total listening time)

## Tech Stack

- Flutter for cross-platform UI
- Tailscale for secure device-to-device connectivity
- HTTP server-client architecture (desktop serves, mobile consumes)
- just_audio for mobile audio playback
- SharedPreferences for local data persistence
