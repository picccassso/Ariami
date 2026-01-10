<div align="center">
  <img src="Arami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
  <p><strong>Stream your music like Spotify. Except you own it.</strong></p>
</div>

Self-hosted music streaming that actually works. Your own self-hosted Spotify/Apple Music server, for free!

Point your server at your music folder, scan a QR code on your phone, and you're streaming. Your entire library, anywhere you go.

---

## Quick Start

### Desktop/Laptop Server

1. **Download** - Get the [server app](https://github.com/picccassso/Ariami/releases) for your platform (Desktop GUI)
2. **Install Tailscale** - Free secure networking ([tailscale.com](https://tailscale.com))
3. **Point to music** - Select your music folder, server auto-indexes everything
4. **Install mobile app** - Download from [releases](https://github.com/picccassso/Ariami/releases)
5. **Scan QR code** - Connect instantly, start streaming

### Raspberry Pi Server

```bash
# Download and extract
curl -L https://github.com/picccassso/Ariami/releases/download/v1.0.1/ariami-cli-raspberry-pi-arm64-v1.0.1.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v1.0.1

# Run the server
chmod +x ariami_cli
./ariami_cli start

# Web interface opens automatically - scan QR code on phone, done
```

No port forwarding. No reverse proxy. No nginx configs. Just music.

---

## Why Use This?

**You already own the music.** Whether it's ripped CDs, Bandcamp purchases, or DRM-free downloads, you paid for it, and you should be able to stream it freely and easily.

**Actually works offline.** Download songs to your phone. Play counts and stats sync when you reconnect.

**Doesn't touch your files.** Read-only access. Your music library stays exactly as it is. No database corruption, no file modifications.

**Zero compromises on features:**
- Background playback with lock screen controls
- Gapless playback and crossfade
- Smart playlists and queue management
- Download albums for offline listening
- Streaming stats (play counts, listening time)
- Multi-device support (iOS, Android, macOS, Windows, Linux)

---

## Key Features

### Server (Desktop & CLI)
- **Auto-indexing** - Scans MP3, FLAC, M4A, OGG, WAV, AIFF, and more
- **Smart album grouping** - Handles compilations and multi-disc albums correctly
- **Live library updates** - Add files to your folder, they appear instantly
- **Tailscale integration** - Secure remote access without exposing ports
- **Lightweight** - Runs on low-end hardware (including Raspberry Pis!) without any problems!

### Mobile (iOS & Android)
- **Offline mode** - Downloads don't expire, no check-ins required
- **Smart caching** - Frequently played songs and artwork cached automatically
- **Queue management** - Drag to reorder, shuffle, repeat modes
- **Search** - Fast search across your entire library
- **Background playback** - OS-native lock screen controls and notifications

---

## Screenshots

<details>
<summary>Mobile App</summary>

### Library View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view.png" alt="Library View" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_2.png" alt="Library View 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_3.png" alt="Library View 3" width="30%">
</p>

### Album Playlist View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/album_playlist_view_1.png" alt="Album Playlist 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/album_playlist_view_2.png" alt="Album Playlist 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/album_playlist_view_3.png" alt="Album Playlist 3" width="30%">
</p>

### Main Player View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/main_player_1.png" alt="Main Player 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/main_player_2.png" alt="Main Player 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/main_player_3.png" alt="Main Player 3" width="30%">
</p>

### Queue View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/queue_view_1.png" alt="Queue View" width="30%">
</p>

### Search View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/search_view_1.png" alt="Search View" width="30%">
</p>

### Offline Mode
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_1.png" alt="Offline Mode 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_2.png" alt="Offline Mode 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_3.png" alt="Offline Mode 3" width="30%">
</p>

### Settings View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/settings_view_1.png" alt="Settings 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/settings_view_2.png" alt="Settings 2" width="30%">
</p>

### Streaming Stats View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/streaming_stats_view_1.png" alt="Streaming Stats 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/streaming_stats_view_2.png" alt="Streaming Stats 2" width="30%">
</p>

### Downloads View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_1.png" alt="Downloads 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_2.png" alt="Downloads 2" width="30%">
</p>

### Connection Stats View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/connection_stats_view_1.png" alt="Connection Stats" width="30%">
</p>

</details>

<details>
<summary>Desktop App</summary>

<p align="center">
  <img src="app%20photos/Ariami%20Desktop/main_1.png" alt="Desktop Main 1" width="45%">
  <img src="app%20photos/Ariami%20Desktop/main_2.png" alt="Desktop Main 2" width="45%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Desktop/main_3.png" alt="Desktop Main 3" width="45%">
  <img src="app%20photos/Ariami%20Desktop/main_4.png" alt="Desktop Main 4" width="45%">
</p>

</details>

<details>
<summary>CLI (Web Interface)</summary>

<p align="center">
  <img src="app%20photos/Ariami%20CLI/main_dashboard_1.png" alt="CLI Dashboard 1" width="45%">
  <img src="app%20photos/Ariami%20CLI/main_dashboard_2.png" alt="CLI Dashboard 2" width="45%">
</p>

</details>

---

## Architecture

Ariami has four components:

- **ariami_core** - Shared Dart library (music indexing, HTTP server, streaming)
- **ariami_desktop** - GUI server for macOS/Windows/Linux with system tray
- **ariami_cli** - Headless server for Linux servers and Raspberry Pi
- **ariami_mobile** - iOS/Android client app

Single Flutter codebase across all platforms. The server components use `ariami_core` for the heavy lifting (library scanning, HTTP/WebSocket APIs, audio streaming with range request support).

---

## Installation

### Server

**Desktop (GUI):**
Download from [releases](https://github.com/picccassso/Ariami/releases) for your platform (macOS, Windows, Linux).

**CLI (Raspberry Pi / Servers):**
```bash
# Download and compile
git clone https://github.com/picccassso/Ariami.git
cd Ariami/ariami_cli
flutter build web -t lib/web/main.dart
dart compile exe bin/ariami_cli.dart -o ariami_cli

# Run
./ariami_cli start
```

### Mobile

Download from [releases](https://github.com/picccassso/Ariami/releases) or build from source:

```bash
cd ariami_mobile
flutter build apk        # Android
flutter build ios        # iOS
```

---

## Development

**Requirements:**
- Dart SDK: ^3.9.2
- Flutter: Latest stable

**Setup:**
```bash
# Get dependencies
cd ariami_core && dart pub get && cd ..
cd ariami_mobile && flutter pub get && cd ..
cd ariami_desktop && flutter pub get && cd ..
cd ariami_cli && flutter pub get && cd ..

# Run desktop server
cd ariami_desktop && flutter run -d macos

# Run mobile app
cd ariami_mobile && flutter run
```

See [GUIDE.md](GUIDE.md) for detailed development documentation.

---

## Latest Updates

- **Windows Desktop Support**: Fixed Tailscale detection on Windows (was using Unix-only `which` command instead of Windows `where`)
- **Transparent Navigation Bar**: Spotify-style frosted glass bottom navigation with blur effect on mobile app
- **Offline Search Improvements**: Search history now displays properly in offline mode, with visual badges showing downloaded vs non-downloaded songs
- **Korean/CJK Character Support**: Fixed character encoding for Korean, Japanese, and Chinese song titles in both online and offline modes

---

## Tech Stack

- **Flutter** - Cross-platform UI (iOS, Android, macOS, Windows, Linux, Web)
- **Shelf** - HTTP server with REST APIs and WebSocket support
- **just_audio** - Mobile audio playback with background support
- **dart_tags** - Metadata extraction (ID3/Vorbis tags)
- **Tailscale** - Secure device-to-device networking
- **SQLite** - Mobile storage (cache, downloads, stats)

---

## License

MIT License - See [LICENSE](LICENSE) for details.
