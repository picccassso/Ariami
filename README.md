<div align="center">
  <img src="Ariami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
  <p><strong>Your music. Your server. One playback session across your devices.</strong></p>
  <p>
    <a href="https://apps.apple.com/us/app/ariami/id6789298823"><img src="https://img.shields.io/badge/App%20Store-Ariami%20Mobile-0D96F6?logo=apple&logoColor=white" alt="Download Ariami Mobile on the App Store"></a>
    <a href="https://www.amazon.com/gp/mas/dl/android?asin=B0GZFT53WL"><img src="https://img.shields.io/badge/Amazon%20Appstore-Ariami%20for%20Fire%20TV-FF9900?logo=amazon&logoColor=white" alt="Get Ariami for Fire TV on the Amazon Appstore"></a>
  </p>
  <p>
    <a href="https://ariami.xyz/">Website</a> ·
    <a href="https://github.com/picccassso/Ariami/releases">Downloads</a> ·
    <a href="#get-the-apps">Get the apps</a> ·
    <a href="#quick-start">Quick Start</a> ·
    <a href="#documentation">Docs</a> ·
    <a href="docs/connect/README.md">Ariami Connect</a>
  </p>
</div>

---

## What Ariami is

Point Ariami at a folder of music files on a computer you already own, and it becomes a
private music service for your household: your library is scanned from the tags already in
your files, and first-party apps for phone, tablet, desktop and TV stream from it. It works at home
over your local network, and away from home over [Tailscale](https://tailscale.com/download).

There is no Ariami-hosted cloud account, no monthly fee, and no requirement for port forwarding
or a reverse proxy. Accounts live on your own server.

Ariami does not provide music or connect to a commercial streaming catalogue. You bring the
audio files you own.

```
   your music folder  ─→  Ariami server  ─→  Mobile · Desktop Player · TV
   (MP3, FLAC, M4A…)      (scan, stream,      (stream, download,
                           transcode, sync)     play offline)

                     Desktop Server · CLI / Raspberry Pi · Docker
                              pick one to host
```

Ariami is an integrated system, not an OpenSubsonic client. The server and the apps are
built together and speak their own protocol, which is how features like Ariami Connect work
end to end. That protocol is not a black box: **Ariami Connect is fully documented** in
[`docs/connect/`](docs/connect/README.md), including a
[build-a-client guide](docs/connect/06-third-party-clients.md) for third-party apps.

---

## Get the apps

Ariami is on the stores. Both downloads are free; the TV app needs a licence key from
[ariami.xyz](https://ariami.xyz/) to unlock.

| Store | App | |
| --- | --- | --- |
| **Apple App Store** | Ariami for iPhone and iPad — free | [Download →](https://apps.apple.com/us/app/ariami/id6789298823) |
| **Amazon Appstore** | Ariami TV for Fire TV — free download, licence unlocks it | [Get it →](https://www.amazon.com/gp/mas/dl/android?asin=B0GZFT53WL) |

Android phones and Android TV are still served by the APKs in
[releases](https://github.com/picccassso/Ariami/releases); a Play Store release is in progress.
The Desktop Player is bought and downloaded from [ariami.xyz](https://ariami.xyz/), and every
server (Desktop Server, CLI, Docker) is free from
[releases](https://github.com/picccassso/Ariami/releases).

You still need to run a server — the apps stream from your own machine, not from a cloud
service. See [Quick Start](#quick-start).

---

## Ariami Connect

What makes Ariami different is that the server and playback apps are designed as one system.

**Connect moves playback, queue and position between your signed-in devices.** Start an album on your phone, push it to the TV, then keep controlling it from your desktop. 

- Transfer playback to any signed-in device, or take over from another one.
- The controlling device mirrors the active player's queue and transport. Its own play/pause, next, previous, seek, volume, shuffle and repeat controls become remote commands.
- Edit the active device's queue remotely: reorder, add, remove, clear.
- Automatic handoff if the active player disappears; every device can be renamed.
- Works across LAN and Tailscale together, so a TV at home and a phone on the road share the
  same session.

Audio is never proxied between devices. This means each device fetches its own stream from the server, and the server only brokers who is playing and what. See [`docs/connect/01-architecture.md`](docs/connect/01-architecture.md).

---

## Screenshots

<p align="center"><img src="app%20photos/Ariami%20CLI/cli_overview.webp" alt="CLI web dashboard" height="130"> <img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_overview_1.webp" alt="Desktop Server dashboard" height="130"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_home_1.webp" alt="Desktop Player" height="130"> <img src="app%20photos/Ariami%20Mobile/mobile_player_1.webp" alt="Mobile player" height="130"> <img src="app%20photos/Ariami%20TV/tv_now_playing_1.webp" alt="TV now playing" height="130"></p>
<p align="center"><sub>CLI web dashboard · Desktop Server · Desktop Player · Mobile · TV</sub></p>

<details>
<summary><strong>CLI web dashboard</strong> — 4 screenshots</summary>

<p align="center"><img src="app%20photos/Ariami%20CLI/cli_overview.webp" alt="Dashboard overview" width="48%"> <img src="app%20photos/Ariami%20CLI/cli_activity.webp" alt="User activity" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20CLI/cli_users.webp" alt="Registered users" width="48%"> <img src="app%20photos/Ariami%20CLI/cli_server.webp" alt="Server settings" width="48%"></p>

</details>
<details>
<summary><strong>Desktop Server</strong> — 6 screenshots of the admin dashboard</summary>

<p align="center"><img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_overview_1.webp" alt="Dashboard overview" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_overview_2.webp" alt="Dashboard overview" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_activity.webp" alt="User activity" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_users.webp" alt="Registered users" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_server_1.webp" alt="Server settings" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(normal%20server)/desktop_server_2.webp" alt="Server settings" width="48%"></p>

</details>
<details>
<summary><strong>Desktop Player</strong> — 15 screenshots (shown here running alongside a server)</summary>

#### Home and library

<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_home_1.webp" alt="Home" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_home_2.webp" alt="Home" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_album_1.webp" alt="Album view" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_album_2.webp" alt="Album view" width="48%"></p>

#### Playlists and recently played

<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_playlist_1.webp" alt="Playlist" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_playlist_2.webp" alt="Playlist" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_playlist_3.webp" alt="Playlist" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_playlist_4.webp" alt="Playlist" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_recently_played.webp" alt="Recently played" width="48%"></p>

#### Settings

<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_1.webp" alt="Settings" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_2.webp" alt="Settings" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_3.webp" alt="Settings" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_4.webp" alt="Settings" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_5.webp" alt="Settings" width="48%"> <img src="app%20photos/Ariami%20Desktop%20(Client%20+%20normal%20server)/desktop_client_settings_6.webp" alt="Settings" width="48%"></p>

</details>
<details>
<summary><strong>Mobile</strong> — 27 screenshots</summary>

#### Library and browse

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_library_1.webp" alt="Library view" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_library_2.webp" alt="Library view" width="24%"></p>

#### Player and Ariami Connect

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_player_1.webp" alt="Now playing" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_player_2.webp" alt="Full player" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_player_3.webp" alt="Player controls" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_player_4.webp" alt="Player controls" width="24%"></p>
<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_player_ariami_connect.webp" alt="Ariami Connect device picker" width="24%"></p>

#### Playlists

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_playlist_1.webp" alt="Playlists" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_playlist_2.webp" alt="Playlist detail" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_album.webp" alt="Album view" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_playlist_3.webp" alt="Edit playlist" width="24%"></p>
<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_playlist_4.webp" alt="Playlist artwork" width="24%"></p>

#### Downloads and import/export

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_downloads_1.webp" alt="Downloads" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_downloads_2.webp" alt="Download progress" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_import_export.webp" alt="Import and export" width="24%"></p>

#### Settings, connection, and sound

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_settings_1.webp" alt="Settings" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_settings_2.webp" alt="Settings" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_connection_1.webp" alt="Connection stats" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_connection_2.webp" alt="Connection details" width="24%"></p>
<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_eq.webp" alt="Equalizer" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_streaming_quality.webp" alt="Streaming quality" width="24%"></p>

#### Profile and stats

<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_listening_stats_1.webp" alt="Listening stats" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_listening_stats_2.webp" alt="Top tracks and artists" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_profile_1.webp" alt="Profile hub" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_profile_2.webp" alt="Profile settings" width="24%"></p>
<p align="center"><img src="app%20photos/Ariami%20Mobile/mobile_profile_3.webp" alt="Profile" width="24%"> <img src="app%20photos/Ariami%20Mobile/mobile_recently_played.webp" alt="Recently played" width="24%"></p>

</details>
<details>
<summary><strong>Tablet layout</strong> — 7 screenshots (same app, sidebar + docked player)</summary>

The mobile app expands into a tablet layout with a sidebar and a docked now-playing card, on
both iPad and Android tablets.

#### Library, playlists, and search

<p align="center"><img src="app%20photos/Ariami%20for%20tablets/tablet_library.webp" alt="Library" width="48%"> <img src="app%20photos/Ariami%20for%20tablets/tablet_playlist.webp" alt="Playlist" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20for%20tablets/tablet_search.webp" alt="Search" width="48%"> <img src="app%20photos/Ariami%20for%20tablets/tablet_queue.webp" alt="Queue" width="48%"></p>

#### Player, Ariami Connect, and stats

<p align="center"><img src="app%20photos/Ariami%20for%20tablets/tablet_player.webp" alt="Now playing" width="48%"> <img src="app%20photos/Ariami%20for%20tablets/tablet_ariami_connect.webp" alt="Ariami Connect" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20for%20tablets/tablet_listening_stats.webp" alt="Listening stats" width="48%"></p>

</details>
<details>
<summary><strong>TV</strong> — 11 screenshots</summary>

#### Home and browse

<p align="center"><img src="app%20photos/Ariami%20TV/tv_home_1.webp" alt="Home" width="48%"> <img src="app%20photos/Ariami%20TV/tv_home_2.webp" alt="Home" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20TV/tv_search.webp" alt="Search" width="48%"> <img src="app%20photos/Ariami%20TV/tv_albums.webp" alt="Albums" width="48%"></p>

#### Now playing and Ariami Connect

<p align="center"><img src="app%20photos/Ariami%20TV/tv_now_playing_1.webp" alt="Now playing" width="48%"> <img src="app%20photos/Ariami%20TV/tv_now_playing_2.webp" alt="Now playing" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20TV/tv_now_playing_3.webp" alt="Now playing" width="48%"> <img src="app%20photos/Ariami%20TV/tv_now_playing_4.webp" alt="Now playing" width="48%"></p>
<p align="center"><img src="app%20photos/Ariami%20TV/tv_ariami_connect.webp" alt="Ariami Connect on TV" width="48%"></p>

#### Settings

<p align="center"><img src="app%20photos/Ariami%20TV/tv_settings_1.webp" alt="Settings" width="48%"> <img src="app%20photos/Ariami%20TV/tv_settings_2.webp" alt="Settings" width="48%"></p>

</details>

---

## Step 1 — choose one server

The server holds your music folder, scans it, and streams to everything else. Pick whichever
machine suits you; you only need one.

| Server | Runs on | Best for |
| --- | --- | --- |
| **Desktop Server** | macOS, Windows, Linux | The computer your music already lives on. First-run wizard, admin dashboard, system tray, start at login. |
| **CLI server** | Raspberry Pi, Linux, macOS, Windows | An always-on box in the corner. Headless daemon with a browser setup wizard and web dashboard. |
| **Docker** | Anywhere Docker runs | NAS and homelab setups. `ghcr.io/picccassso/ariami-cli` — see [DOCKER.md](ariami_cli/docker/DOCKER.md). |

All three are free, run the same core, and expose the same admin features.
[Download the latest release →](https://github.com/picccassso/Ariami/releases)

## Step 2 — choose your playback apps

| App | Platforms | Availability |
| --- | --- | --- |
| **Mobile** | Android, iOS (phones and tablets) | Free. iOS/iPadOS on the [App Store](https://apps.apple.com/us/app/ariami/id6789298823); Android APK in [releases](https://github.com/picccassso/Ariami/releases), with a Play Store release in progress. |
| **Desktop Player** | macOS, Windows, Linux | One-time purchase. Bought and downloaded from [ariami.xyz](https://ariami.xyz/). A full player, separate from the Desktop Server above. |
| **TV** | Fire TV, Android TV | One-time licence, bought at [ariami.xyz](https://ariami.xyz/). The app itself is a free download from the [Amazon Appstore](https://www.amazon.com/gp/mas/dl/android?asin=B0GZFT53WL) on Fire TV; for Android TV, side-load the APK from [releases](https://github.com/picccassso/Ariami/releases) — a Play Store release is in progress. LAN-only by design. |

The Desktop Server can host your library on the same machine that runs the Desktop Player —
they are separate apps and either can be used on its own.

---

## Quick Start

1. **Install a server.** Download the Desktop Server or CLI build for your machine from
   [releases](https://github.com/picccassso/Ariami/releases), or pull the Docker image. The
   CLI opens a browser setup wizard on first run (`http://localhost:8080` if it does not open
   by itself).
2. **Choose your music folder.** Ariami scans it and builds the library from the tags already
   in your files. It never modifies or deletes your music.
3. **Create the owner account.** The first account on a server is the owner/admin, and is
   created on the server itself — not from your phone.
4. **Pair a device.** Scan the QR code shown by the server, or enter the server address and
   invite code manually. Expiry and account rules are in the
   [mobile setup guide](ariami_mobile/docs/SETUP.md).
5. **Play.** Sign the same account in on your other devices, then use Ariami Connect to move
   playback between them.

Remote access is optional: Ariami works on your LAN with no port forwarding. To listen away
from home, install [Tailscale](https://tailscale.com/download) on the server and your devices. The apps prefer LAN at home and switch to Tailscale when you are out. It is the recommended option and not a requirement.

Day-to-day CLI commands: `./ariami_cli start` · `status` · `stop` · `autostart enable` ·
`reset`. Full list in the [CLI reference](ariami_cli/docs/CLI_REFERENCE.md).

---

## Core capabilities

<details>
<summary><strong>Library and search</strong></summary>

Scans MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC and ALAC, grouping albums from
embedded tags (including Various Artists compilations) with no external lookups. Real-time
folder watching picks up added, changed and removed files without a full rescan and pushes
updates to connected clients; a metadata cache skips unchanged files. Clients keep a local
catalog copy and sync incrementally. Search is shared by every client, with transliteration
and keyboard-layout correction so mistyped or differently-scripted queries still land.

Details: [core docs](ariami_core/docs/README.md) ·
[playlist detection](ariami_core/PLAYLIST_DETECTION.md)

</details>
<details>
<summary><strong>Playback, downloads and offline</strong></summary>

Background playback with lock-screen and OS media controls, queue editing, shuffle, repeat,
gapless playback, and an equalizer with built-in and custom presets. Download tracks, albums,
playlists or the whole library for offline listening, with a manual offline mode and automatic
fallback when the connection drops. Quality presets follow connection type, with separate
settings for streaming and downloads, and a streaming cache for anything not yet downloaded.
Server-side transcoding is handled by Sonic (MP3 → AAC), with server-managed download jobs and
per-user concurrency limits so one device cannot starve the others. Mobile also casts to
Chromecast.

Details: [mobile features](ariami_mobile/docs/FEATURES.md) ·
[desktop features](ariami_desktop/docs/FEATURES.md)

</details>
<details>
<summary><strong>Playlists</strong></summary>

Create and edit playlists in the apps, with custom cover art that syncs across your devices,
reordering, renaming, and a Liked Songs playlist. On the server, folders named `[PLAYLIST]…`
and `.m3u` files become playlists, and detected playlist folders can be surfaced to the owner
for approval. Server playlists import to your devices as editable copies; edits sync back and
queue up if you make them offline.

</details>
<details>
<summary><strong>Accounts and multi-device</strong></summary>

Password-protected accounts (10 characters minimum), each with its own sessions, downloads,
playback state and stats. The first account is the owner/admin; afterwards, new registrations
need an owner-generated QR code or invite code, both single-use and time-limited, and headless
setups can bootstrap the owner with a one-time console code. One account can be signed in on
phone, desktop and TV at once — that is what makes Connect work. Login rate limiting guards
against brute force, and the TV account picker is off by default so a server never lists its
account names unless the owner turns it on.

</details>
<details>
<summary><strong>Listening stats</strong></summary>

Account-wide stats that follow you across every Ariami device and roll into one history:
tabbed top tracks, artists and albums with play counts and time listened; all-time, day, week,
month and year views; individually credited featured artists; average daily listening time and
a profile snapshot. You can import your Spotify listening history and match it against your
library, and export playlists and stats as JSON.

Details: [listening stats](ariami_core/docs/LISTENING_STATS.md)

</details>
<details>
<summary><strong>Server administration</strong></summary>

The Desktop dashboard and the CLI web dashboard both show server status, library stats,
connected clients and registered users, plus admin views for download queues and transcoding
activity. Owner actions cover adding and deleting users, changing passwords, kicking devices,
generating pairing QR codes and invite codes, rescanning the library, and Spotify import.
Start-at-login/autostart is available on both. **Ariami never deletes your music folder** — a
setup reset clears pairing and setup state, and a factory reset clears Ariami-owned data
(accounts, sessions, stats, playlists, database, cache); both require typing `RESET`.

Details: [RESET.md](RESET.md) · [CLI configuration](ariami_cli/docs/CONFIGURATION.md)

</details>
<details>
<summary><strong>Sonic transcoder benchmarks (Raspberry Pi 5)</strong></summary>

Sonic is purpose-built for Ariami's transcoding workload (MP3 → AAC). It is not a general
FFmpeg replacement; FFmpeg is still used for artwork processing.

Test setup: Raspberry Pi 5 over ethernet, active cooler enabled. Average temperature during
hard Sonic transcoding: about 68 °C.

| Scenario (Pi 5) | Sonic | FFmpeg | Difference |
| --- | --- | --- | --- |
| Original quality (single device, full run) | 57s, 3877.4 MB | 1m 8s, 3877.4 MB | Sonic faster by 11s |
| Medium quality (single device) | 4m 22s, 1993.4 MB (full run) | 53 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Low quality (single device) | 4m 36s, 1122.7 MB (full run) | 54 songs after 2m | Sonic completed full job; FFmpeg was still in progress |
| Medium quality, 2 devices at same time | S23: 4m 56s, iPhone 12: 4m 54s (1993.4 MB each) | S23: 41 songs, iPhone 12: 40 songs after 2m | Sonic completed both full jobs |
| Different quality, 2 devices at same time | S23 Low: 8m 12s, iPhone 12 Medium: 7m 55s | S23 Low: 22 songs, iPhone 12 Medium: 28 songs after 2m | Sonic completed both full jobs |

</details>

---

## Pricing and licensing

- **Ariami Core, the servers (Desktop Server, CLI, Docker) and the mobile app are free**, and
  the source in this repository is MIT licensed.
- **The Desktop Player and the TV app are one-time purchases**, available separately or as a
  bundle that activates both. There is no subscription. Buy them at [ariami.xyz](https://ariami.xyz/); current prices are listed there. Store downloads never charge you:
  the Fire TV app installs free from the Amazon Appstore and is unlocked by the licence key.
- A purchase gives you a licence key. TV licences are activated once and stored on the server,
  so every TV in the household picks the licence up automatically.
- Paid clients help fund continued development. Core and mobile stay free.

Ariami does not operate a cloud service: your library, accounts, playlists and listening
history live on your server, and the apps carry no ads, analytics or tracking. See
[PRIVACY.md](PRIVACY.md).

---

## Documentation

| Area | Where |
| --- | --- |
| **Ariami Connect** (protocol, commands, third-party clients) | [docs/connect/](docs/connect/README.md) |
| **Core** (architecture, HTTP/WebSocket API, persistence, stats, testing) | [ariami_core/docs/](ariami_core/docs/README.md) |
| **Mobile** (overview, features, setup, architecture, building) | [ariami_mobile/docs/](ariami_mobile/docs/README.md) |
| **Desktop Server** (overview, features, architecture, building) | [ariami_desktop/docs/](ariami_desktop/docs/README.md) |
| **CLI** (installation, configuration, command reference, FAQ) | [ariami_cli/docs/](ariami_cli/docs/README.md) · [Docker](ariami_cli/docker/DOCKER.md) · [headless](ariami_cli/HEADLESS.md) |
| **Architecture** | [core](ariami_core/docs/ARCHITECTURE.md) · [mobile](ariami_mobile/docs/ARCHITECTURE.md) · [desktop](ariami_desktop/docs/ARCHITECTURE.md) · [Connect topology](docs/connect/01-architecture.md) |
| **Troubleshooting** | [mobile](ariami_mobile/docs/TROUBLESHOOTING.md) · [desktop](ariami_desktop/docs/TROUBLESHOOTING.md) · [CLI](ariami_cli/docs/TROUBLESHOOTING.md) · [Connect gotchas](docs/connect/07-gotchas.md) |
| **Building from source** | [GUIDE.md](GUIDE.md) · [mobile](ariami_mobile/docs/BUILDING.md) · [desktop](ariami_desktop/docs/BUILDING.md) |
| **Other** | [CHANGELOG.md](CHANGELOG.md) · [RESET.md](RESET.md) · [PRIVACY.md](PRIVACY.md) · [AI.md](AI.md) |

---

## Roadmap

- Role-based access control for families, with explicit per-user song and album filtering.
- Per-user library control — today one library is shared by everyone, with no way to hide or
  manage content per person.
- More stats imports. Spotify history import already ships; YouTube Music and Apple Music are
  next, once there is a real set of listening data to build against.
- Ariami for tvOS (Apple TV) is something I am willing to look into if there is demand.

The most valuable input is user feedback. Ariami has been tested across as many VMs, laptops,
PCs, phones and real TVs as I could get hold of, but that is still a small slice of the devices
out there — reported issues are what make it better.

---

## Building from source

Per-package instructions live in each package's docs; [GUIDE.md](GUIDE.md) covers the full
developer setup.

- [`ariami_desktop/`](ariami_desktop/README.md) — Desktop Server
- [`ariami_cli/`](ariami_cli/README.md) — CLI server for Raspberry Pi / Linux
- [`ariami_mobile/`](ariami_mobile/README.md) — mobile client
- [`ariami_core/`](ariami_core/README.md) — shared library

**Requirements:** Dart SDK ^3.5.0 (compiling the CLI binary with `dart build cli` needs Dart
3.9+), and Flutter — latest stable is fine locally; release binaries are built with Flutter
3.44.0. A Rust toolchain is only needed to build [Sonic](sonic/); without it the server still
runs, but low/medium-quality transcoding is unavailable. FFmpeg is optional and used for
artwork resizing.

**iOS:** Ariami is on the [App Store](https://apps.apple.com/us/app/ariami/id6789298823), so
you only need to build it yourself if you are developing against it — `flutter build ios`
(requires macOS and Xcode).

Clone with submodules if you need the Sonic transcoder for desktop builds:

```bash
git clone --recurse-submodules https://github.com/picccassso/Ariami.git
```

---

## Contributing and feedback

Bug reports and feature requests are welcome via
[GitHub Issues](https://github.com/picccassso/Ariami/issues). Please include your platform, the Ariami version, and which server you are running. Pull requests are welcome for the packages in this repository.

## Licence

MIT — see [LICENSE](LICENSE).
