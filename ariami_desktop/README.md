# Ariami Desktop

GUI music server for Ariami. Indexes your music library and streams to the
Ariami mobile, desktop, and TV clients. This package is the server and its admin
console — there is no playback UI in it.

Fuller package documentation lives in [docs/](docs/README.md) (overview,
feature walkthrough, architecture, building, troubleshooting).

## Features

- Automatic library scanning (MP3, M4A, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC)
- Real-time folder monitoring
- System tray integration (closing the window offers "Minimize to Tray" instead of quitting)
- QR code plus a manual invite code for pairing clients
- Multi-user authentication with an owner (admin) account
- Four-tab dashboard (Overview, Activity, Users, Server) showing server status,
  library stats, listening activity, connected devices, and registered users
- Admin controls: add and delete users, change passwords, kick devices, toggle
  the TV account picker
- Server-side audio transcoding with quality presets (original, 128 kbps AAC,
  64 kbps AAC) and a configurable transcode-slot limit
- Ariami TV license activation, stored on the server so every TV in the
  household picks it up automatically
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

Per-platform prerequisites are in [docs/BUILDING.md](docs/BUILDING.md).

## Usage

1. Launch the app and follow the first-run wizard (Tailscale optional)
2. Select your music folder and wait for the library scan
3. **Create the owner account** when prompted (first account = server admin)
4. Scan the QR code with Ariami Mobile — or type the manual invite code — then
   **register** or log in
5. Use the dashboard with **owner sign-in** for admin actions (users, kick device, passwords)

The owner account is created on the desktop during setup, not from the phone. After the owner exists, new phone accounts register with the token in the server's QR code or the equivalent invite code — both are single-use and expire after 10 minutes, so re-open the connection screen ("Show QR") to mint a fresh one.
