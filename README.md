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
# Install Tailscale (follow commands from https://tailscale.com/download/linux/rpi)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Download and extract Ariami
curl -L https://github.com/picccassso/Ariami/releases/download/v3.1.0/ariami-cli-raspberry-pi-arm64-v3.1.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v3.1.0

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
- Incremental v2 sync architecture is in place, with local mobile storage and server-managed change tracking.

**Multi-User Support**
- Create user accounts with password authentication.
- Each user gets their own session, downloads, and playback state.
- Admin dashboard shows connected users and devices with the ability to kick devices and change passwords.
- One active session per user at a time to keep things simple.
- If no users are registered, the server runs in open mode for backward compatibility.

**Playlists**
- Create and manage playlists manually from the app. Can easily edit them, edit the photo for them etc.
- Folders with [PLAYLIST] in their name are treated as playlists. These appear in the app and can be imported to your phone for local playback.

**Offline and Local Playback**
- You can download all your music for local playback without needing to be connected to the server.
- Imported playlists are stored locally on your phone.
- Each song played automatically gets cached if not downloaded for smoother playback.
- Option to prefer local/cached files even when connected to the server.
- Server-managed v2 download jobs are supported for large download batches.
- Large download queues and UI updates have been optimised so bulk downloads behave much better.

**Streaming and Audio**
- Stream music from your server to any supported client.
- Server-side audio transcoding for compatibility with different devices.
- Automatic quality switching based on network type (WiFi vs mobile data).

**Apps and Platforms**
- Native apps that are available for iOS, Android, macOS, Windows and Linux.
- CLI version available for headless servers.
- Consistent UI across devices.

**Remote Access**
- Secure access using Tailscale.
- If your phone is on the same LAN as your server, Ariami now prefers the local network path automatically.
- If you leave home and Tailscale is available, Ariami switches to the remote route automatically, then switches back to LAN when you return.
- No port forwarding or anything of the sort.

**Listening Data**
- Tracks basic listening stats for songs/albums/artists. Also shows average daily listening time for each.
- More detailed planned stats (such as specific days etc).

**Server Dashboard**
- Shows connected users and active devices.
- Admin controls to kick devices and change user passwords.
- Auth status indicator showing whether authentication is required or open.
- Connection setup and QR flow now include both LAN and Tailscale endpoints when available.

**Planned**
- Additional Playlists tools
- Ability for server to detect and transcode data in real time to optimise for different network connections (lower bit rate for worse WiFi/mobile data connections).

---

## Screenshots

<details>
<summary>Mobile App</summary>

### Library View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view_1_grid.png" alt="Library View Grid 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_1_list.png" alt="Library View List 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/library_view_2_grid.png" alt="Library View Grid 2" width="30%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view_2_list.png" alt="Library View List 2" width="30%">
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
  <img src="app%20photos/Ariami%20Mobile/search_view_1.png" alt="Search View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/search_view_2.png" alt="Search View 2" width="30%">
</p>

### Offline Mode
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_1.png" alt="Offline Mode 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_2.png" alt="Offline Mode 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_3.png" alt="Offline Mode 3" width="30%">
</p>

### Settings View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/settings_view_1.png" alt="Settings" width="30%">
</p>

### Streaming Quality View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/streaming_quality_view_1.png" alt="Streaming Quality" width="30%">
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
  <img src="app%20photos/Ariami%20Mobile/downloads_view_3.png" alt="Downloads 3" width="30%">
</p>

### Connection Stats View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/connection_stats_view.png" alt="Connection Stats" width="30%">
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
  <img src="app%20photos/Ariami%20CLI/main_dashboard.png" alt="CLI Dashboard" width="60%">
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

## Latest Updates

- Bulk downloads were reworked so large libraries behave much better. Queue persistence, downloads UI churn, cache-triggered refreshes, and completion flow were tightened up, and queue limits were increased for large libraries.
- Ariami now supports dual-endpoint routing. The app can store both LAN and Tailscale endpoints, prefer LAN when you are home, switch to Tailscale when remote, and switch back to LAN when you come back.
- Setup is less rigid now. If Tailscale is missing, users can still continue with local setup, and the QR/setup flow includes both endpoints when available.
- V2 download-job handling was fixed on the desktop server path, including the setup flow and quota handling for large download jobs.

### Other Improvements

- Metadata caching for faster library rescans — durations and tags persist across restarts so rescans don't re-read every file
- Automatic quality switching based on network type (WiFi vs mobile data)
- Option to prefer local/cached files even when connected to the server
- iOS safe-area layout fixes for the mini player and bottom navigation
- CLI daemon fixes on Linux — `start` command no longer hangs

## License

MIT License - See [LICENSE](LICENSE) for details.
