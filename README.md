<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
</div>

**Ariami is a self-hosted music app that lets you stream your own music library from a desktop, Raspberry Pi, or server to your phone, without port forwarding or complicated setup.**

---

## What is Ariami?

Ariami is not a cloud music service. Your files stay on your machine, and you run the server yourself. The **desktop app** and **CLI** are server hosts; the **mobile app** is the main playback client for now.

At home, your phone connects over your local network. Away from home, [Tailscale](https://tailscale.com/download) gives you a private path to the same server without opening ports on your router. No subscription, no uploading your library to someone else's servers.

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/main_player_1.png" alt="Mobile player" width="24%">
  <img src="app%20photos/Ariami%20Mobile/library_view_mixed_grid_1.png" alt="Mobile library" width="24%">
  <img src="app%20photos/Ariami%20Desktop/main_1_overview.png" alt="Desktop dashboard" width="24%">
  <img src="app%20photos/Ariami%20CLI/main_1_overview.png" alt="CLI dashboard" width="24%">
</p>
<p align="center"><sub>Mobile player · Mobile library · Desktop app/server · CLI web dashboard</sub></p>

---

## Download

Get the [latest release](https://github.com/picccassso/Ariami/releases) for your platform:

| Component | Platforms | Notes |
| --- | --- | --- |
| **Desktop app/server** | macOS, Windows, Linux | GUI server with setup wizard and dashboard |
| **CLI / headless server** | Raspberry Pi, Linux | Background daemon with web setup UI |
| **Mobile client** | Android APK | Install from releases |
| **Mobile client** | iOS | Build from source (no App Store release yet) |

---

## Quick Start

The basic flow is the same everywhere: **download server → choose music folder → create owner account → pair mobile app with QR or invite code → stream music.**

### Desktop app/server (macOS, Windows, Linux)

1. Download and run the desktop app from [releases](https://github.com/picccassso/Ariami/releases).
2. Follow the first-run wizard. Tailscale is optional but recommended for remote access.
3. **Choose your music folder.** The server scans your library from embedded tags.
4. **Create the owner account.** The first account on the server becomes the owner (admin).
5. **Scan the QR code** with the Ariami mobile app, then register or log in.

After setup, the dashboard shows server status, library stats, and the QR code again. **Owner sign-in** is required for admin actions (manage users, kick devices, change passwords).

### Raspberry Pi / CLI server

On first run, the CLI starts in the foreground and opens a **browser setup wizard** (or go to `http://localhost:8080` if it does not open). After setup, `./ariami_cli start` runs as a background daemon.

```bash
# Optional but recommended: install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Download and extract the latest CLI release (example for v4.4.0)
curl -L https://github.com/picccassso/Ariami/releases/download/v4.4.0/ariami-cli-raspberry-pi-arm64-v4.4.0.zip -o ariami-cli.zip
unzip ariami-cli.zip
cd ariami-cli-raspberry-pi-arm64-v4.4.0

chmod +x ariami_cli
./ariami_cli start
```

In the browser wizard:

1. Optional: set up **Tailscale** (or continue with local-only access).
2. **Select your music folder** and wait for the scan.
3. **Create the owner account** and sign in as owner.
4. **Scan the QR code** with the mobile app and register or log in.

Day-to-day: `./ariami_cli start` | `./ariami_cli status` | `./ariami_cli stop`

See `ariami_cli/SETUP.txt` in the release zip for more detail.

### Mobile app

1. Install the **Android APK** from [releases](https://github.com/picccassso/Ariami/releases), or **build iOS from source** (see [Building from Source](#building-from-source)).
2. Optional: install **Tailscale** on your phone for remote access.
3. Scan the **QR code** shown by the server (desktop connection screen or CLI web UI).
4. **Register** a new account or **log in**.

After the owner account exists, new registrations require the time-limited token in the owner's QR code, or a one-time **invite code** from the server dashboard. If you cannot scan the QR, use **Manual entry** in the app, type the server address, and enter the invite code.

---

## Remote access with Tailscale

Ariami works on your LAN out of the box. You do not need port forwarding for home use.

For listening away from home, install [Tailscale](https://tailscale.com/download) on the server and your phone. Tailscale creates a private network between your devices. The mobile app prefers LAN when you are home and switches to Tailscale when you are away.

Without Tailscale, remote access would require manual port forwarding on your router. Tailscale is optional, but it is the recommended way to reach your server from outside your home network.

---

## Server management

### Owner account

The **first account created becomes the owner/admin.** The owner is created on the server during setup, not from the phone. Use **owner sign-in** on the desktop or CLI web dashboard for admin actions: view connected devices, kick a client, change passwords, delete users, and generate a fresh registration QR or invite code for new phone accounts.

After setup, new registrations require an owner-generated QR code or invite code.

### Dashboard

- **Desktop:** in-app dashboard after setup (Server tab, library stats, connected clients).
- **CLI:** web UI at `http://localhost:8080` (or the next free port 8081–8099).

Both show server status, library stats, connected clients, and registered users. Admin views include live download queues and transcoding activity.

### QR code and invite codes

The server QR code includes LAN and Tailscale addresses when both are available, so pairing works at home or on the road. Registration tokens and invite codes expire after 10 minutes and are single-use.

### Start on boot / autostart

- **Desktop:** Dashboard → **Server** tab → **Start at Login** (launch automatically when you sign in).
- **CLI:** `./ariami_cli autostart enable` (use `disable` or `status` to manage). First-run setup also asks this as a y/N prompt.

### Reset / factory reset

**Ariami never deletes your music folder.** Setup reset clears setup/pairing state; factory reset clears Ariami-owned data such as accounts, sessions, stats, playlists, database, and cache.

- **Desktop:** Dashboard → **Server** tab → **Danger Zone** → Reset Ariami
  - *Setup only:* clears setup progress and pairing state; keeps catalog DB, accounts, and caches.
  - *Factory reset:* clears database, users, sessions, stats, playlists, and cache.
- **CLI:** `./ariami_cli reset` (interactive menu), or `./ariami_cli reset --setup -y` / `./ariami_cli reset --factory -y`

Both reset types require typing `RESET` to confirm. Factory reset also disables Start at Login / autostart.

---

## Why Ariami?

Self-hosting your music usually means wrestling with port forwarding, reverse proxies, and server config. Ariami packages the server, handles library scanning and transcoding, and pairs your phone with a QR code. Run it on the computer you already have, or on a Raspberry Pi in the corner. Your metadata stays in your files, your library stays on your hardware, and there is nothing to pay monthly.

---

## Features

### Library and metadata

- Scans your library and groups albums from embedded tags, so metadata stays yours without flaky external lookups.
- Supports MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, and ALAC.
- Handles large libraries, including Various Artists compilations when appropriate.
- Real-time folder watching: new, changed, or removed files update the library without a full rescan; connected clients get push updates over WebSocket.
- Metadata cache speeds up rescans by skipping unchanged files.
- Incremental v2 sync: the phone keeps a local catalog copy; the server tracks changes so you are not constantly doing full rescans.
- Server-side artwork is resized and cached for efficient delivery.
- On mobile: grid, list, or mixed views; pin albums and playlists; filter to downloaded content; multi-select batch downloads; search with recent history (works offline against downloads).

### Mobile player

- Background playback with lock screen and notification controls.
- Mini player and full-screen player with seek bar, shuffle, repeat, and resume where you left off.
- Dynamic player colours from album artwork; appearance settings including light, dark, system, preset, and custom themes.
- Profile hub with optional local avatar and a quick listening snapshot.

### Downloads and offline

- Download music for fully offline playback.
- Manual offline mode to disconnect on purpose and keep using downloads.
- When the connection drops, the app stays usable offline and reconnects when the network returns.
- Streaming cache for tracks you have not downloaded yet; prefer local or cached files even when online.
- Downloads screen for in-progress, failed, and completed downloads; bulk download options; original-quality downloads that bypass transcoding when appropriate.
- Cache controls for streaming artwork and tracks, including size limits and clear cache.
- Server-managed v2 download jobs for big batches, with throttling and per-user concurrency limits.

### Queue and playback

- View, reorder, and clear the queue; play next or add to queue from menus; swipe list rows to queue.
- HTTP range requests for seeking while streaming.
- Quality presets that follow connection type (Wi‑Fi vs mobile data), with separate settings for streaming and downloads.
- Server-side transcoding powered by Sonic (MP3 → AAC) so clients can use formats and quality levels that suit the device.

### Playlists

- Create and edit playlists in the app, including artwork, reordering, and renaming.
- Like songs from the player to build a Liked Songs playlist.
- Folders whose names start with `[PLAYLIST]` become server-side playlists; import them to your phone for offline playback.
- Export and import playlists and listening stats as JSON for backup or moving to a new phone.

### Multi-user and auth

- Password-protected accounts; each user gets their own session, downloads, and playback state.
- The first account created becomes the owner/admin. After setup, new registrations require an owner-generated QR code or invite code.
- A user can have one active non-dashboard device session at a time; signing in on another device can replace the previous mobile session after confirmation.
- Login rate limiting helps protect against brute-force attempts.

### Desktop and CLI server

- **Desktop:** GUI server with system tray (minimize to tray instead of quitting), first-run wizard, admin dashboard, Start at Login, and reset options.
- **CLI:** headless server for Raspberry Pi and Linux with `start`, `stop`, `status`, `autostart`, and `reset` commands, a background daemon after setup, optional custom port, and a web UI for setup and administration.

### Chromecast

- Cast from the mobile app to Chromecast devices on the same network.

### Listening stats

- On-device stats for songs, albums, and artists, including average daily listening time and tabbed top tracks, artists, and albums views.
- Stats stay on your phone per account; export and import as JSON.

### Sonic transcoding

- Sonic is purpose-built for Ariami's music transcoding workload (MP3 → AAC). In Ariami's own Raspberry Pi 5 tests, Sonic completed full transcoding jobs faster than FFmpeg for the same scenarios. Sonic is not a general FFmpeg replacement; FFmpeg is still used for artwork processing.

<details>
<summary>Sonic transcoder benchmarks (Raspberry Pi 5)</summary>

Test setup: Raspberry Pi 5 connected over ethernet, active cooler enabled. Average temperature during hard Sonic transcoding: about 68 C (cooler kicked in to dissipate heat).

| Scenario (Pi 5) | Sonic | FFmpeg | Difference |
| --- | --- | --- | --- |
| Original quality (single device, full run) | 57s, 3877.4 MB | 1m 8s, 3877.4 MB | Sonic faster by 11s |
| Medium quality (single device) | 4m 22s, 1993.4 MB (full run) | 53 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Low quality (single device) | 4m 36s, 1122.7 MB (full run) | 54 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Medium quality, 2 devices at same time | S23: 4m 56s, iPhone 12: 4m 54s (1993.4 MB each) | S23: 41 songs, iPhone 12: 40 songs after 2m | Sonic completed both full jobs |
| Different quality, 2 devices at same time | S23 Low: 8m 12s, iPhone 12 Medium: 7m 55s | S23 Low: 22 songs, iPhone 12 Medium: 28 songs after 2m | Sonic completed both full jobs |

</details>

### Planned

- Richer listening stats (for example per calendar day breakdowns).
- Desktop player mode.
- Extension and integration support.

---

## Screenshots

Tap a section to expand. All images reflect the current app UI.

<details>
<summary><strong>Mobile App</strong> (35 screenshots)</summary>

<br>

#### Library and browse

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view_grid_1.png" alt="Library grid view" width="24%">
  <img src="app%20photos/Ariami%20Mobile/library_view_list_1.png" alt="Library list view" width="24%">
  <img src="app%20photos/Ariami%20Mobile/library_view_mixed_grid_1.png" alt="Library mixed grid view" width="24%">
  <img src="app%20photos/Ariami%20Mobile/library_view_mixed_list_1.png" alt="Library mixed list view" width="24%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/library_view_select_1.png" alt="Library multi-select" width="24%">
  <img src="app%20photos/Ariami%20Mobile/library_view_settings_1.png" alt="Library filters and settings" width="24%">
  <img src="app%20photos/Ariami%20Mobile/album_view_2.png" alt="Album view" width="24%">
  <img src="app%20photos/Ariami%20Mobile/search_view_1.png" alt="Search" width="24%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/search_view_2.png" alt="Search results" width="24%">
</p>

#### Player and queue

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/main_player_1.png" alt="Now playing" width="24%">
  <img src="app%20photos/Ariami%20Mobile/main_player_2.png" alt="Full player" width="24%">
  <img src="app%20photos/Ariami%20Mobile/main_player_3.png" alt="Player controls" width="24%">
  <img src="app%20photos/Ariami%20Mobile/main_player_queue_4.png" alt="Queue" width="24%">
</p>

#### Playlists

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_1.png" alt="Playlists" width="24%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_2.png" alt="Playlist detail" width="24%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_3.png" alt="Edit playlist" width="24%">
  <img src="app%20photos/Ariami%20Mobile/playlist_view_4.png" alt="Playlist artwork" width="24%">
</p>

#### Downloads and offline

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_1.png" alt="Downloads" width="24%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_2.png" alt="Download progress" width="24%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_3.png" alt="Download queue" width="24%">
  <img src="app%20photos/Ariami%20Mobile/downloads_view_4.png" alt="Download options" width="24%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_1.png" alt="Offline mode" width="24%">
  <img src="app%20photos/Ariami%20Mobile/offline_mode_2.png" alt="Offline library" width="24%">
</p>

#### Streaming and connection

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/streaming_quality_1.png" alt="Streaming quality" width="24%">
  <img src="app%20photos/Ariami%20Mobile/streaming_quality_2.png" alt="Download quality" width="24%">
  <img src="app%20photos/Ariami%20Mobile/connection_stats_1.png" alt="Connection stats" width="24%">
  <img src="app%20photos/Ariami%20Mobile/connection_stats_2.png" alt="Connection details" width="24%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/chromecast_view_1.png" alt="Chromecast" width="24%">
</p>

#### Profile, stats, and appearance

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/profile_view_1.png" alt="Profile hub" width="24%">
  <img src="app%20photos/Ariami%20Mobile/profile_view_2.png" alt="Profile settings" width="24%">
  <img src="app%20photos/Ariami%20Mobile/listening_stats_1.png" alt="Listening stats" width="24%">
  <img src="app%20photos/Ariami%20Mobile/listening_stats_2.png" alt="Top tracks and artists" width="24%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_1.png" alt="Appearance themes" width="24%">
  <img src="app%20photos/Ariami%20Mobile/appearence_view_2.png" alt="Custom theme" width="24%">
</p>

#### Import and export

<p align="center">
  <img src="app%20photos/Ariami%20Mobile/import_export_playlist_server_1.png" alt="Import and export" width="48%">
  <img src="app%20photos/Ariami%20Mobile/import_export_playlist_server_2.png" alt="Server playlist import" width="48%">
</p>

</details>

<details>
<summary><strong>Desktop App</strong> (6 screenshots)</summary>

<br>

<p align="center">
  <img src="app%20photos/Ariami%20Desktop/main_1_overview.png" alt="Dashboard overview" width="48%">
  <img src="app%20photos/Ariami%20Desktop/main_2_activity.png" alt="User activity" width="48%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Desktop/main_3_users.png" alt="Registered users" width="48%">
  <img src="app%20photos/Ariami%20Desktop/main_4_server.png" alt="Server settings" width="48%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20Desktop/main_5_pairing.png" alt="Mobile pairing QR code" width="48%">
  <img src="app%20photos/Ariami%20Desktop/main_6_reset.png" alt="Reset and danger zone" width="48%">
</p>

</details>

<details>
<summary><strong>CLI Web Dashboard</strong> (5 screenshots)</summary>

<br>

<p align="center">
  <img src="app%20photos/Ariami%20CLI/main_1_overview.png" alt="Dashboard overview" width="48%">
  <img src="app%20photos/Ariami%20CLI/main_2_activity.png" alt="User activity" width="48%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20CLI/main_3_users.png" alt="Registered users" width="48%">
  <img src="app%20photos/Ariami%20CLI/main_4_server.png" alt="Server settings" width="48%">
</p>
<p align="center">
  <img src="app%20photos/Ariami%20CLI/main_5_pairing.png" alt="Mobile pairing QR code" width="48%">
</p>

</details>

---

## Building from Source

If you want to build from source, check the README in each package folder:

- `ariami_desktop/` - Desktop app/server
- `ariami_cli/` - CLI server for Raspberry Pi / Linux servers
- `ariami_mobile/` - Mobile client app
- `ariami_core/` - Shared library

**Requirements:** Dart SDK ^3.5.0, and Flutter (latest stable is fine for local builds; GitHub release binaries are built with Flutter 3.44.0).

**iOS:** there is no App Store release yet. Build and install on your own device with `flutter build ios` (requires macOS and Xcode).

Clone with submodules if you need the Sonic transcoder for desktop builds:

```bash
git clone --recurse-submodules https://github.com/picccassso/Ariami.git
```

---

## License

MIT License - See [LICENSE](LICENSE) for details.
