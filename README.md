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
curl -L https://github.com/picccassso/Ariami/releases/download/v2.0.0/ariami-cli-raspberry-pi-arm64-v2.0.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v2.0.0

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
- No port forwarding or anything of the sort.

**Listening Data**
- Tracks basic listening stats for songs/albums/artists. Also shows average daily listening time for each.
- More detailed planned stats (such as specific days etc).

**Server Dashboard**
- Shows connected users and active devices.
- Admin controls to kick devices and change user passwords.
- Auth status indicator showing whether authentication is required or open.

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

### Multi-User Support

Full multi-user authentication has been added. Users can now create accounts and log in from the mobile app. Passwords are hashed with bcrypt and sessions last 30 days with a sliding TTL. If no users are registered, the server stays in open mode so nothing breaks for existing setups. Once the first user registers, authentication becomes required.

Each user gets one active session at a time — if you try to log in on a second device, the server will tell you that you're already logged in elsewhere. The first user to register is treated as the admin.

The server dashboards (both Desktop and CLI web) now show a connected users and devices table. From there, the admin can kick devices and change user passwords. The mobile app shows who you're logged in as in the connection settings, with a dedicated logout button.

Stream tokens are used for audio playback — short-lived tokens passed as query params so that just_audio can handle authenticated streaming without needing to set headers on every request. Downloads also go through stream tokens now.

Rate limiting is in place for login attempts (5 tries per 15 minutes per device) to prevent brute force.

### Server-Side Download Throttling

Download concurrency is now managed on the server. There are global and per-user limits to stop one user from hogging all the bandwidth. The limits are configured per platform — a Raspberry Pi with a microSD gets more conservative limits than a Mac with an SSD. The mobile app reads the server's limits and adjusts its own concurrency to match. When the server is at capacity it returns 503/429 and the client backs off.

### V2 Architecture Rework

The entire library sync, artwork, and download pipeline has been reworked. The old approach had the mobile app fetching the full library as one big snapshot every time, artwork requests firing off in uncontrolled bursts, and "download all" flows enqueuing everything at once in a client-side loop. This didn't scale well, especially with multiple users.

The v2 architecture replaces all of that:

- **Catalog database** — The server now writes its library to a persistent SQLite catalog instead of rebuilding everything in memory on each request. This gives us indexed lookups, pagination, and a change log that tracks what's been added, modified, or deleted.
- **Incremental sync** — Mobile clients do a paginated bootstrap on first connect, then only pull changes since their last sync token. No more re-fetching the entire library.
- **Local sync store** — The mobile app maintains its own normalized SQLite database as the source of truth for library data. Screens read from local storage instead of hitting the server repeatedly.
- **Artwork pipeline** — Artwork variants (full size and 200x200 thumbnails) are precomputed during indexing. Responses include ETag and Last-Modified headers so clients can skip re-downloading unchanged artwork. The metadata extraction has also been optimised to only read tag sections of files rather than the entire file.
- **Media request scheduler** — A bounded concurrency scheduler with priority tiers (visible, nearby, background) replaces the old unbounded artwork request pattern. Stale low-priority requests get dropped automatically.
- **Server-managed download jobs** — Instead of the mobile app enqueuing hundreds of items in a loop, it now creates a download job on the server and fetches items page by page. This plays nicely with the per-user download limits.
- **Multi-user fairness** — Per-user quotas for downloads and artwork requests, with a weighted fair queue so one user can't starve the others.
- **Observability** — Structured metrics logging with endpoint latency, queue depth per user, artwork cache hit ratios, and change log lag tracking.
- **Feature flags** — Everything is gated behind feature flags for staged rollout. V1 endpoints remain functional during the migration, with deprecation headers and a sunset target.

### Other Improvements

- Metadata caching for faster library rescans — durations and tags persist across restarts so rescans don't re-read every file
- Automatic quality switching based on network type (WiFi vs mobile data)
- Option to prefer local/cached files even when connected to the server
- iOS safe-area layout fixes for the mini player and bottom navigation
- CLI daemon fixes on Linux — `start` command no longer hangs

## License

MIT License - See [LICENSE](LICENSE) for details.
