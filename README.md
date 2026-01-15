<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
  <p><strong>Stream your music like Spotify. Except you own it.</strong></p>
</div>

Self-hosted music streaming that actually works. Your own self-hosted Spotify/Apple Music server, for free!

Point your server at your music folder, scan a QR code on your phone, and you're streaming. Your entire library, anywhere you go.

YouTube How To & Demonstration: [Right here!](https://youtu.be/ssIoGl-0JS8)

---

## Quick Start

### Desktop/Laptop Server

1. **Download the server app** from [releases](https://github.com/picccassso/Ariami/releases) for your platform (macOS, Windows, Linux)
2. **Download the mobile app** from [releases](https://github.com/picccassso/Ariami/releases) (Android APK / iOS)
3. **Install Tailscale** on both devices.
4. **Run the server** and select your music folder
5. **Scan the QR code** with the mobile app - done!

### Raspberry Pi Server

```bash
# Download and extract
curl -L https://github.com/picccassso/Ariami/releases/download/v1.5.0/ariami-cli-raspberry-pi-arm64-v1.5.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v1.5.0

# Run the server
chmod +x ariami_cli
./ariami_cli start

# Web interface opens automatically - scan QR code on phone, done
```

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
  <img src="app%20photos/Ariami%20Mobile/library_view_1.png" alt="Library View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_2.png" alt="Library View 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_3.png" alt="Library View 3" width="30%">
</p>

### Playlist View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_1.png" alt="Playlist View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_2.png" alt="Playlist View 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_3.png" alt="Playlist View 3" width="30%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_4.png" alt="Playlist View 4" width="30%">
</p>

### Main Player View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/main_player_1.png" alt="Main Player 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/main_player_2.png" alt="Main Player 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/main_player_3.png" alt="Main Player 3" width="30%">
</p>

### Queue View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/queue_view_1.png" alt="Queue View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/queue_view_2.png" alt="Queue View 2" width="30%">
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

### Import/Export View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/import_export_view_1.png" alt="Import Export View" width="30%">
  <img src="app%20photos/Ariami%20Mobile/import_playlist_1.png" alt="Import Playlist 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/import_playlist_2.png" alt="Import Playlist 2" width="30%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/import_playlist_3.png" alt="Import Playlist 3" width="30%">
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

## Building from Source

If you want to build from source, check the README in each package folder:
- `ariami_desktop/` - Desktop server app
- `ariami_cli/` - CLI server for Raspberry Pi / Linux servers
- `ariami_mobile/` - Mobile client app
- `ariami_core/` - Shared library

**Requirements:** Dart SDK ^3.5.0, Flutter (latest stable)

---

## Latest Updates (v1.5.0)

- **Import/Export**: Export and import playlists & streaming stats via JSON file
- **Download All**: Download your entire library (all songs, albums, or playlists) with one tap
- **Concurrent Downloads**: Up to 10 simultaneous downloads (~10x faster)
- **Performance Boost**: Library scanning 50-60% faster on first scan, 90%+ faster on re-scans
- **Raspberry Pi Fix**: Server now properly runs in background after setup
- **Downloaded Status**: Context menus show checkmark when album/playlist is fully downloaded
- **Section Memory**: Library sections (Playlists/Albums/Songs) remember expanded/collapsed state

---

## License

MIT License - See [LICENSE](LICENSE) for details.
