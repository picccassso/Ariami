<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
</div>

Ariami is a self-hosted server and music player. 

---

## Quick Start 

1. **Download the server app** from [releases](https://github.com/picccassso/Ariami/releases) for your platform (macOS, Windows, Linux)
2. **Download the mobile app** from [releases](https://github.com/picccassso/Ariami/releases) (Android APK / iOS)
3. **Download and install Tailscale on both devices** from (https://tailscale.com/download)
4. **Run the server and select music folder.**
5. **Scan the QR code** with the mobile app and you're good to go.

### For Raspberry Pi

```bash
# Download and extract
curl -L https://github.com/picccassso/Ariami/releases/download/v1.9.0_testing/ariami-cli-raspberry-pi-arm64-v1.9.0_testing.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v1.9.0_testing

# Run the server
chmod +x ariami_cli
./ariami_cli start

# Web interface opens automatically - scan QR code on phone, complete
```

---

## Why use Ariami?

Ariami is a very easy way to get into self-hosting. You do not need to setup port forwarding or pay for any subscription. It is very easy to setup. 
It is cross-platform so you can run this on your Mac/Windows/Linux machine, and is packaged for Raspberry Pis as well. Also works on Android/iOS. (iOS is untested).

## Features of Ariami:

**Music Library**
- It automatically scans your music library.
- It uses embedded tags so it doesn't rely on external data which could mess up your library.
- Groups albums correctly.
- Supports large libraries.

**Playlists**
- Create and manage playlists manually from the app. Can easily edit them, edit the photo for them etc.
- Folders with [PLAYLIST] in their name are treated as playlists. These appear in the app and can be imported to your phone for local playback.

**Offline and Local Playback**
- You can download all your music for local playback without needing to be connected to the server.
- Imported playlists are stored locally on your phone.
- Each song played automatically gets cached if not downloaded for smoother playback.

**Streaming and Audio**
- Stream music from your server to any supported client.
- Server-side audio transcoding for compatibility with different devices.
- Gapless playback support (if applicable — remove if not accurate).

**Apps and Platforms**
- Native apps that are available for iOS, Android, macOS, Windows and Linux.
- CLI version available for headless servers.
- Consistent UI across devices. 

**Remote Access**
- Secure access using Tailscale.
- No port forwarding or anything of the sort.

**Listening Data**
- Tracks basic listening stats for songs/albums/artists. Also shows average daily listening time for each.
- More detailed planned stats (such as specific days etc).

**Planned**
- Multi-user support
- Additional Playlists tools
- Ability for server to detect and transcode data in real time to optimise for different network connections (lower bit rate for worse WiFi/mobile data connections).

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

## Testing Branch Latest Updates

### 21/01/2026

**Playlist Download Indicators** - Playlists now show a green download badge (matching albums) when they contain offline-available songs.

**Playlist Loading Performance** - Fixed N+1 API call issue when loading playlists. Now uses a single `/api/library` call instead of fetching every album individually. ~98% reduction in API calls for large libraries.

**Mini Player Aware UI** - Bottom sheets and scrollable screens now dynamically adjust padding when the mini player is visible, preventing content from being obscured.

---

### 16/01/2026

#### Audio Transcoding

Server-side audio transcoding is now available. This lets mobile users stream and download music at reduced quality levels, which saves a ton of bandwidth and makes playback smoother on bad connections.

Three quality presets:
- **High** - Original file, no transcoding
- **Medium** - 128 kbps AAC (around 50% smaller)
- **Low** - 64 kbps AAC (around 75% smaller)

In my testing, a 1.5 GB library went down to 706 MB on medium and 351 MB on low. Pretty significant savings if you're downloading your whole library to your phone.

You can configure separate quality settings for WiFi streaming, mobile data streaming, and downloads. The app automatically switches quality based on your network type. Go to Settings > Streaming Quality to set it up.

The server uses FFmpeg for transcoding (must be installed on the host machine). Transcoded files are cached so it only transcodes once per song per quality level. If FFmpeg isn't available, it just serves the original file.

---

## License

MIT License - See [LICENSE](LICENSE) for details.

