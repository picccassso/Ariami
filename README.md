<div align="center">
  <img src="Arami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
  <p><strong>Stream your music like Spotify. Except you own it.</strong></p>
</div>

Self-hosted music streaming that actually works. No subscription fees. No privacy concerns. No vendor lock-in.

Point your server at your music folder, scan a QR code on your phone, and you're streaming. Your entire library, anywhere you go.

---

## Quick Start

1. **Download** - Get the [server app](../../releases) for your platform (Desktop GUI or CLI for servers)
2. **Install Tailscale** - Free secure networking ([tailscale.com](https://tailscale.com))
3. **Point to music** - Select your music folder, server auto-indexes everything
4. **Install mobile app** - Download from [releases](../../releases)
5. **Scan QR code** - Connect instantly, start streaming

No port forwarding. No reverse proxy. No nginx configs. Just music.

---

## Why Use This?

**You already own the music.** Whether it's ripped CDs, Bandcamp purchases, or DRM-free downloads, you paid for it. Why pay again monthly to stream it?

**Runs on a Raspberry Pi.** $50 hardware, one-time cost. Put it in a closet and forget about it. Supports Pi 3 or newer.

**Actually works offline.** Download songs to your phone. Airplane mode? Subway? Works the same. Play counts and stats sync when you reconnect.

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
- **Lightweight** - Runs on Raspberry Pi 3+ without breaking a sweat

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

### Library & Player
<p align="center">
  <img src="app_photos/BMA%20Mobile/library_1.png" alt="Library View" width="30%">
  <img src="app_photos/BMA%20Mobile/main_player_1.png" alt="Player" width="30%">
  <img src="app_photos/BMA%20Mobile/queue_1.png" alt="Queue" width="30%">
</p>

### Search & Downloads
<p align="center">
  <img src="app_photos/BMA%20Mobile/search_1.png" alt="Search" width="30%">
  <img src="app_photos/BMA%20Mobile/downloads_1.png" alt="Downloads" width="30%">
  <img src="app_photos/BMA%20Mobile/streaming_stats_1.png" alt="Stats" width="30%">
</p>

### Offline Mode
<p align="center">
  <img src="app_photos/BMA%20Mobile/library_4_offline.png" alt="Offline Library" width="30%">
</p>

</details>

<details>
<summary>Desktop App</summary>

<p align="center">
  <img src="app_photos/BMA%20Desktop/main_1.png" alt="Desktop Main" width="45%">
  <img src="app_photos/BMA%20Desktop/main_2.png" alt="Desktop Dashboard" width="45%">
</p>

</details>

<details>
<summary>CLI (Web Interface)</summary>

<p align="center">
  <img src="app_photos/BMA%20CLI/dashboard.png" alt="CLI Dashboard" width="45%">
  <img src="app_photos/BMA%20CLI/terminal.png" alt="CLI Terminal" width="45%">
</p>

</details>

---

## Raspberry Pi Deployment

Perfect for a Pi 3 or newer sitting in your closet:

```bash
# Install on Raspberry Pi
curl -O [release-url]/ariami_cli
chmod +x ariami_cli
./ariami_cli start

# Web interface opens automatically
# Scan QR code on phone, done
```

The CLI runs as a background daemon. Automatic restart on boot, graceful shutdown handling, web-based configuration.

**Hardware requirements:**
- Raspberry Pi 3 or newer (Pi 4 recommended)
- SD card with Raspberry Pi OS
- External drive for music (USB works fine)

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
Download from [releases](../../releases) for your platform (macOS, Windows, Linux).

**CLI (Raspberry Pi / Servers):**
```bash
# Download and compile
git clone https://github.com/alexuae-ua/ariami.git
cd ariami/ariami_cli
flutter build web -t lib/web/main.dart
dart compile exe bin/ariami_cli.dart -o ariami_cli

# Run
./ariami_cli start
```

### Mobile

Download from [releases](../../releases) or build from source:

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
