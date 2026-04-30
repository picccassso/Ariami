<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
</div>

Ariami is a self-hosted music library server with native desktop and mobile players.

---

## Quick Start

1. **Download the desktop server** from [releases](https://github.com/picccassso/Ariami/releases). Pick the ZIP for your OS (for example `Ariami-Desktop-v4.3.0-macos.zip`, `Ariami-Desktop-v4.3.0-windows.zip`, or `Ariami-Desktop-v4.3.0-linux.zip` — filenames follow that pattern for each version).
2. **Download the Android app** from the same [releases](https://github.com/picccassso/Ariami/releases) page (`ariami_apk_release_v4.3.0.apk` for v4.3.0). For iOS, you will have to build it and run it yourself.
3. **Install Tailscale** on the computer running the server and on your phone: [tailscale.com/download](https://tailscale.com/download)
4. **Run the server** and choose your music folder.
5. **Scan the QR code** shown by the server with the mobile app to connect.

### For Raspberry Pi

```bash
# Install Tailscale (follow commands from https://tailscale.com/download/linux/rpi)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Download and extract Ariami
curl -L https://github.com/picccassso/Ariami/releases/download/v4.3.0/ariami-cli-raspberry-pi-arm64-v4.3.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v4.3.0

# Run the server
chmod +x ariami_cli
./ariami_cli start

# Web interface opens automatically - scan QR code on phone, complete
```

---

## Why use Ariami?

Ariami is a very easy way to get into self-hosting. You do not need to setup port forwarding or pay for any subscription. It is very easy to setup.
It is cross-platform so you can run this on your Mac/Windows/Linux machine, and is packaged for Raspberry Pis as well. Also works on Android/iOS.

## Features of Ariami:

**Music Library**
- Automatically scans your library and groups albums using embedded tags, so your metadata stays yours and does not depend on flaky external lookups.
- Handles large libraries comfortably.
- Incremental v2 sync: the phone keeps a local copy of the catalog, and the server tracks changes so you are not constantly doing full rescans.
- On mobile, you can use a mixed library view that shows albums and playlists in one place (toggle from the library). Sorting favours what you opened recently on the device, then falls back to the usual ordering.

**Multi-user**
- Password-protected accounts; each user gets their own session, downloads, and playback state.
- One active session per user at a time (signing in on another device replaces the previous session).
- If no one has registered yet, the server runs in open mode so older single-user setups still work.

**Playlists**
- Create and edit playlists in the app, including artwork.
- Folders whose names start with `[PLAYLIST]` become server-side playlists; you can import them to your phone for offline playback.

**Offline and downloads**
- Download music for fully offline playback; imported playlists live on the device.
- Streaming caches tracks you have not downloaded yet, and you can prefer local or cached files even when you are online.
- Server-managed v2 download jobs for big batches, with the download UI tuned for large queues.

**Streaming and audio**
- Stream from the server to any supported client.
- Server-side transcoding powered by Sonic (MP3 -> AAC) so clients can use formats and quality levels that suit the device.
- Quality presets that follow the connection type (for example Wi‑Fi vs mobile data).

**Sonic transcoder (Raspberry Pi 5 benchmarks)**
- Sonic is Ariami's purpose-built transcoder and is much faster than ffmpeg for Ariami's quality-conversion tasks.
- Test setup: Raspberry Pi 5 connected over ethernet, active cooler enabled.
- Average temperature during hard Sonic transcoding: about 68 C (cooler kicked in to dissipate heat).

| Scenario (Pi 5) | Sonic | FFmpeg | Difference |
| --- | --- | --- | --- |
| Original quality (single device, full run) | 57s, 3877.4 MB | 1m 8s, 3877.4 MB | Sonic faster by 11s |
| Medium quality (single device) | 4m 22s, 1993.4 MB (full run) | 53 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Low quality (single device) | 4m 36s, 1122.7 MB (full run) | 54 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Medium quality, 2 devices at same time | S23: 4m 56s, iPhone 12: 4m 54s (1993.4 MB each) | S23: 41 songs, iPhone 12: 40 songs after 2m | Sonic completed both full jobs |
| Different quality, 2 devices at same time | S23 Low: 8m 12s, iPhone 12 Medium: 7m 55s | S23 Low: 22 songs, iPhone 12 Medium: 28 songs after 2m | Sonic completed both full jobs |

**Apps and platforms**
- Native apps for Android, iOS (build from source), macOS, Windows, and Linux, plus a CLI build with a web dashboard for headless servers.

**Connection, dashboard, and QR**
- No port forwarding: Tailscale gives you a private path to the server over the internet.
- When your phone and server are on the same LAN, the app prefers that path; when you are away it uses Tailscale if it is up, and switches back to LAN when you return.
- The dashboard (desktop app or CLI web UI) shows who is connected, lets admins kick a device or change passwords, and shows whether authentication is required or the server is still open.
- QR setup includes LAN and Tailscale addresses when the server has both, so pairing works at home or on the road.

**Chromecast**
- The mobile app supports casting to Chromecast devices on the same network.

**Listening data**
- On the device, keeps listening stats for songs, albums, and artists, including average daily listening time.
- Richer breakdowns (for example per calendar day) are planned.

**Planned**
- Improve the reliability of Ariami. 

---

## Screenshots

<details>
<summary>Mobile App</summary>

### Appearance View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_1.png" alt="Appearance 1" width="22%">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_2.png" alt="Appearance 2" width="22%">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_3.png" alt="Appearance 3" width="22%">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_4.png" alt="Appearance 4" width="22%">
</p>

### Chromecast View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/chromecast_view_1_new.png" alt="Chromecast 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/chromecast_view_2_new.png" alt="Chromecast 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/chromecast_view_3_new.png" alt="Chromecast 3" width="30%">
</p>

### Connection Stats View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/connection_stats_view.png" alt="Connection Stats" width="30%">
</p>

### Downloads View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_1_new.png" alt="Downloads 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_2_new.png" alt="Downloads 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_3_new.png" alt="Downloads 3" width="30%">
</p>

### Import/Export View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/import_export_view_1_new.png" alt="Import Export View" width="30%">
  <img src="app%20photos/Ariami%20Mobile/import_playlist_1.png" alt="Import Playlist 1" width="30%">
</p>

### Library View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view_1_new.png" alt="Library View" width="22%">
  <img src="app%20photos/Ariami%20Mobile/library_view_grid_1_new.png" alt="Library View Grid" width="22%">
  <img src="app%20photos/Ariami%20Mobile/library_view_list_1_new.png" alt="Library View List" width="22%">
  <img src="app%20photos/Ariami%20Mobile/library_view_mixed_1_new.png" alt="Library View Mixed" width="22%">
</p>

### Main Player View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/main_player_1_new.png" alt="Main Player 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/main_player_2_new.png" alt="Main Player 2" width="30%">
</p>

### Offline View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/offline_view_1_new.png" alt="Offline View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_view_2_new.png" alt="Offline View 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/offline_view_3_new.png" alt="Offline View 3" width="30%">
</p>

### Playlist View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_1_new.png" alt="Playlist View 1" width="18%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_2_new.png" alt="Playlist View 2" width="18%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_3_new.png" alt="Playlist View 3" width="18%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_4_new.png" alt="Playlist View 4" width="18%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_5.png" alt="Playlist View 5" width="18%">
</p>

### Profile Hub
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/profile_hub_1.png" alt="Profile Hub 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/profile_hub_2.png" alt="Profile Hub 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/profile_hub_3.png" alt="Profile Hub 3" width="30%">
</p>

### Queue View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/queue_view_1_new.png" alt="Queue View 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/queue_view_2_new.png" alt="Queue View 2" width="30%">
</p>

### Search View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/search_view_1_new.png" alt="Search View 1" width="30%">
</p>

### Settings View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/setting_view_1_new.png" alt="Settings 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/setting_view_2_new.png" alt="Settings 2" width="30%">
</p>

### Streaming Quality View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/streaming_quality_view_1_new.png" alt="Streaming Quality 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/streaming_quality_view_2_new.png" alt="Streaming Quality 2" width="30%">
</p>

### Streaming Stats View
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/streaming_stats_1_new.png" alt="Streaming Stats 1" width="30%">
  <img src="app%20photos/Ariami%20Mobile/streaming_stats_2_new.png" alt="Streaming Stats 2" width="30%">
  <img src="app%20photos/Ariami%20Mobile/streaming_stats_3_new.png" alt="Streaming Stats 3" width="30%">
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
  <img src="app%20photos/Ariami%20CLI/main_1.png" alt="CLI Dashboard 1" width="45%">
  <img src="app%20photos/Ariami%20CLI/main_2.png" alt="CLI Dashboard 2" width="45%">
</p>

</details>

---

## Building from Source

If you want to build from source, check the README in each package folder:
- `ariami_desktop/` - Desktop server app
- `ariami_cli/` - CLI server for Raspberry Pi / Linux servers
- `ariami_mobile/` - Mobile client app
- `ariami_core/` - Shared library

**Requirements:** Dart SDK ^3.5.0, and Flutter (latest stable is fine for local builds; GitHub release binaries are built with Flutter 3.29.2).

---

## License

MIT License - See [LICENSE](LICENSE) for details.
