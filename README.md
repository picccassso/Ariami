<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
</div>

Ariami is a self-hosted music library server with native desktop and mobile players.

---

## Quick Start

**First-time checklist**

- [ ] Install Tailscale on the server and your phone ([tailscale.com/download](https://tailscale.com/download))
- [ ] Download and run the server (desktop app or Raspberry Pi CLI)
- [ ] Choose your music folder and wait for the library scan
- [ ] Create the **owner account** (server admin — required before phones can register)
- [ ] Scan the server QR code on your phone and **register** or log in

Downloads are on the [releases](https://github.com/picccassso/Ariami/releases) page: desktop server ZIP for your OS (for example `Ariami-Desktop-v4.3.0-macos.zip`), and the Android APK (`ariami_apk_release_v4.3.0.apk` for v4.3.0). For iOS, build from source (see [Building from Source](#building-from-source)).

### Desktop server (macOS, Windows, Linux)

1. Install **Tailscale** on the computer running the server and on your phone.
2. **Run the desktop app** and follow the first-run wizard.
3. **Choose your music folder** and wait for the initial library scan.
4. **Create the owner account** when prompted. The first account on the server is the owner (admin). You need this before the server finishes setup.
5. **Scan the QR code** from the connection screen with the Ariami mobile app, then **register** a new account or log in.

After setup, use the dashboard for server status and the QR code. **Owner sign-in** is required for admin actions (manage users, kick devices, change passwords).

### Raspberry Pi / CLI server

On first run, the CLI starts in the foreground and opens a **browser setup wizard** (or go to `http://localhost:8080` if it does not open). Later runs use `./ariami_cli start` as a background daemon.

```bash
# Install Tailscale (see https://tailscale.com/download/linux/rpi)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Download and extract Ariami
curl -L https://github.com/picccassso/Ariami/releases/download/v4.3.0/ariami-cli-raspberry-pi-arm64-v4.3.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v4.3.0

chmod +x ariami_cli
./ariami_cli start
```

In the browser wizard:

1. Optional: set up **Tailscale** (or continue with local-only access).
2. **Select your music folder** and wait for the scan.
3. **Create the owner account** and sign in as owner.
4. **Scan the QR code** with the mobile app and **register** or log in.

Day-to-day: `./ariami_cli start` | `./ariami_cli status` | `./ariami_cli stop`. See `ariami_cli/SETUP.txt` in the release zip for more detail.

### Mobile app

1. Install the Android APK from [releases](https://github.com/picccassso/Ariami/releases) (or build iOS from source).
2. Install **Tailscale** on your phone.
3. Scan the **QR code** shown by the server (desktop connection screen or CLI web UI after owner setup).
4. **Register** a new account or **log in**. After the owner account exists, registration requires the time-limited token embedded in that QR code.

### Managing the server (owner)

The **owner** is the first account created on the server. Use **owner sign-in** on the desktop or CLI web dashboard for admin actions: view connected devices, kick a client, change passwords, delete users, and show a fresh registration QR for new phone accounts.

---

## Why use Ariami?

Ariami is a very easy way to get into self-hosting. You do not need to setup port forwarding or pay for any subscription. It is very easy to setup.
It is cross-platform so you can run this on your Mac/Windows/Linux machine, and is packaged for Raspberry Pis as well. Also works on Android/iOS.

## Features of Ariami:

**Music Library**
- Automatically scans your library and groups albums using embedded tags, so your metadata stays yours and does not depend on flaky external lookups.
- Supports common formats including MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, and ALAC.
- Handles large libraries comfortably, including compilation albums grouped as Various Artists when appropriate.
- Real-time folder watching: new, changed, or removed files update the library without a full rescan, and connected clients receive push updates over WebSocket.
- A metadata cache speeds up rescans by skipping files that have not changed.
- Incremental v2 sync: the phone keeps a local copy of the catalog, and the server tracks changes so you are not constantly doing full rescans.
- Server-side artwork is resized and cached for efficient delivery to clients.
- On mobile, browse in grid or list view, or use a mixed view that shows albums and playlists in one place. Pin albums and playlists, filter to downloaded content only, and use multi-select for batch downloads. Sorting favours what you opened recently on the device, then falls back to the usual ordering.
- Search across songs and albums with recent history; when offline, search works against your downloaded library.

**Multi-user**
- Password-protected accounts; each user gets their own session, downloads, and playback state.
- One active session per user at a time (signing in on another device replaces the previous session).
- If no one has registered yet, the server runs in open mode so older single-user setups still work.
- Login rate limiting helps protect against brute-force attempts.
- The desktop app can create an owner account during setup for server administration; mobile users register or log in when auth is required.

**Playlists**
- Create and edit playlists in the app, including artwork, reordering, and renaming.
- Like songs from the player to build a Liked Songs playlist.
- Folders whose names start with `[PLAYLIST]` become server-side playlists; you can import them to your phone for offline playback.

**Offline and downloads**
- Download music for fully offline playback; imported playlists live on the device.
- Manual offline mode lets you disconnect on purpose and keep using downloads without auto-reconnect.
- When the connection drops unexpectedly, the app stays usable offline and reconnects when the network returns.
- Streaming caches tracks you have not downloaded yet, and you can prefer local or cached files even when you are online.
- Downloads screen for managing in-progress, failed, and completed downloads; bulk download options; original-quality downloads that bypass transcoding when appropriate.
- Cache controls for streaming artwork and tracks, including size limits and clear cache.
- Server-managed v2 download jobs for big batches, with the download UI tuned for large queues.
- Server-side download throttling and per-user concurrency limits keep large download queues stable on busy servers.

**Streaming and audio**
- Stream from the server to any supported client, with HTTP range requests for seeking while playing.
- Server-side transcoding powered by Sonic (MP3 -> AAC) so clients can use formats and quality levels that suit the device.
- Quality presets that follow the connection type (for example Wi‑Fi vs mobile data), with separate settings for streaming and downloads.

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

**Mobile player**
- Background playback with lock screen and notification controls.
- Mini player and full-screen player with seek bar, shuffle, repeat, and playback that resumes where you left off.
- Queue management: view, reorder, and clear the queue; play next or add to queue from menus; swipe list rows to queue.
- Dynamic player colours extracted from album artwork; full appearance settings including light, dark, system, preset, and custom themes.
- Profile hub with optional local avatar and a quick listening snapshot.

**Apps and platforms**
- Native apps for Android, iOS (build from source), macOS, Windows, and Linux.
- Desktop server app with system tray support (minimize to tray instead of quitting), a first-run onboarding wizard, and an admin dashboard.
- CLI headless server for Raspberry Pi and Linux with `start`, `stop`, and `status` commands, a background daemon after setup, optional custom port, and a web UI for setup and administration.

**Connection, dashboard, and QR**
- No port forwarding: Tailscale gives you a private path to the server over the internet.
- When your phone and server are on the same LAN, the app prefers that path; when you are away it uses Tailscale if it is up, and switches back to LAN when you return.
- The dashboard (desktop app or CLI web UI) shows server status, library stats, connected clients, and registered users; start or stop the server, rescan the library, change the music folder, or show the QR code again.
- Admin actions include kicking a device, changing passwords, and deleting users; live user activity shows download queues and transcoding in progress.
- Shows whether authentication is required or the server is still open; owner sign-in is required for admin actions on the desktop app.
- QR setup includes LAN and Tailscale addresses when the server has both, so pairing works at home or on the road.

**Chromecast**
- The mobile app supports casting to Chromecast devices on the same network.

**Listening data**
- On the device, keeps listening stats for songs, albums, and artists, including average daily listening time and tabbed top tracks, artists, and albums views.
- Export and import playlists and listening stats as JSON for backup or moving to a new phone.
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
