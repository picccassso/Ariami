# Ariami Desktop

GUI music server for Ariami. It indexes your music library and streams it to
the Ariami mobile, desktop, and TV clients. This package is the server and its
admin console; playback happens in the client apps.

Fuller package documentation lives in [docs/](docs/README.md) (overview,
feature walkthrough, architecture, building, troubleshooting).

## Features

- Automatic library scanning and real-time folder monitoring for MP3, M4A,
  MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, and ALAC files
- System tray integration: closing the window can hide Ariami to the tray so
  the server keeps running, and the tray menu shows the window or quits
- QR code and a manual invite code for pairing clients
- Multi-user authentication with an owner (admin) account
- Four-tab dashboard (Overview, Activity, Users, Server) with server status,
  library statistics, live download and transcode activity, connected devices,
  and registered users
- Admin controls: add and delete users, change passwords, kick devices, and
  toggle the TV account picker
- Server-side audio transcoding with quality presets (original, 128 kbps AAC,
  64 kbps AAC) and a configurable transcode-slot limit
- Ariami TV licence activation on the Server tab, stored on the server so
  every TV in the household picks it up automatically
- Spotify listening-history import (and removal) for the owner account
- Start at login, an update-available notice, and a Reset Ariami flow

## Building

```bash
cd ariami_desktop
flutter pub get
flutter run -d macos        # or linux/windows
flutter build macos         # or linux/windows
```

Low/medium-quality transcoding is powered by the Rust `sonic/` submodule at the
repository root, so fetch it before building:

```bash
git submodule update --init --recursive
```

Per-platform prerequisites, including a Rust toolchain, are in
[docs/BUILDING.md](docs/BUILDING.md).

## Usage

1. Launch the app and follow the first-run wizard (Tailscale optional)
2. Select your music folder and wait for the library scan
3. **Create the owner account** when prompted. The first account becomes the server admin.
4. Scan the QR code with Ariami Mobile, or type the manual invite code, then **register** or log in
5. Use the dashboard with **owner sign-in** for admin actions (users, kick device, passwords)

The owner account is created on the desktop during setup. After the owner
exists, new phone accounts register with the token in the server's QR code or
the equivalent manual invite code. Both are single-use and expire after
10 minutes, so re-open the connection screen ("Show QR") to mint a fresh one.
