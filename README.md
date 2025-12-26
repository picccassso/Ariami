<div align="center">
  <img src="Arami_icon.png" alt="Ariami Logo" width="200"/>
  <h1>Ariami</h1>
</div>

A cross-platform personal music streaming system built with Flutter. Host your own music library and stream to your devices from anywhere using Tailscale for secure connectivity.

## App Photos

<details>
<summary>Ariami CLI</summary>

<p align="center">
  <img src="app_photos/BMA%20CLI/terminal.png" alt="BMA CLI Terminal" width="45%">
  <img src="app_photos/BMA%20CLI/dashboard.png" alt="BMA CLI Dashboard" width="45%">
</p>

</details>

<details>
<summary>Ariami Desktop</summary>

<p align="center">
  <img src="app_photos/BMA%20Desktop/main_1.png" alt="BMA Desktop Main 1" width="45%">
  <img src="app_photos/BMA%20Desktop/main_2.png" alt="BMA Desktop Main 2" width="45%">
</p>
<p align="center">
  <img src="app_photos/BMA%20Desktop/main_3.png" alt="BMA Desktop Main 3" width="45%">
</p>

</details>

<details>
<summary>Ariami Mobile</summary>

### Library

<p align="center">
  <img src="app_photos/BMA%20Mobile/library_1.png" alt="BMA Mobile Library 1" width="45%">
  <img src="app_photos/BMA%20Mobile/library_2.png" alt="BMA Mobile Library 2" width="45%">
</p>
<p align="center">
  <img src="app_photos/BMA%20Mobile/library_3.png" alt="BMA Mobile Library 3" width="45%">
  <img src="app_photos/BMA%20Mobile/library_4_offline.png" alt="BMA Mobile Library 4 Offline" width="45%">
</p>
<p align="center">
  <img src="app_photos/BMA%20Mobile/library_5.png" alt="BMA Mobile Library 5" width="45%">
  <img src="app_photos/BMA%20Mobile/library_6.png" alt="BMA Mobile Library 6" width="45%">
</p>

### Main Player

<p align="center">
  <img src="app_photos/BMA%20Mobile/main_player_1.png" alt="BMA Mobile Main Player 1" width="45%">
</p>

### Queue

<p align="center">
  <img src="app_photos/BMA%20Mobile/queue_1.png" alt="BMA Mobile Queue 1" width="45%">
</p>

### Search

<p align="center">
  <img src="app_photos/BMA%20Mobile/search_1.png" alt="BMA Mobile Search 1" width="45%">
  <img src="app_photos/BMA%20Mobile/search_2.png" alt="BMA Mobile Search 2" width="45%">
</p>

### Settings

<p align="center">
  <img src="app_photos/BMA%20Mobile/settings_1_connected.png" alt="BMA Mobile Settings 1 Connected" width="45%">
  <img src="app_photos/BMA%20Mobile/settings_2_disconnected.png" alt="BMA Mobile Settings 2 Disconnected" width="45%">
</p>
<p align="center">
  <img src="app_photos/BMA%20Mobile/settings_3.png" alt="BMA Mobile Settings 3" width="45%">
</p>

### Streaming Stats

<p align="center">
  <img src="app_photos/BMA%20Mobile/streaming_stats_1.png" alt="BMA Mobile Streaming Stats 1" width="45%">
  <img src="app_photos/BMA%20Mobile/streaming_stats_2.png" alt="BMA Mobile Streaming Stats 2" width="45%">
</p>

### Downloads

<p align="center">
  <img src="app_photos/BMA%20Mobile/downloads_1.png" alt="BMA Mobile Downloads 1" width="45%">
  <img src="app_photos/BMA%20Mobile/downloads_2.png" alt="BMA Mobile Downloads 2" width="45%">
</p>
<p align="center">
  <img src="app_photos/BMA%20Mobile/downloads_3.png" alt="BMA Mobile Downloads 3" width="45%">
</p>

</details>

## Architecture

Ariami consists of three components that work together:

- **ariami_desktop** - GUI server (macOS, Linux, Windows) with system tray integration
- **ariami_cli** - Headless server with web UI for servers and Raspberry Pi
- **ariami_mobile** - Mobile client (Android, iOS) for browsing and streaming
- **ariami_core** - Shared platform-agnostic core library

## Quick Start

```bash
# Install dependencies
cd ariami_core && dart pub get && cd ..
cd ariami_mobile && flutter pub get && cd ..
cd ariami_desktop && flutter pub get && cd ..
cd ariami_cli && flutter pub get && cd ..

# Run desktop server (GUI)
cd ariami_desktop && flutter run -d macos

# Or run CLI server (headless)
cd ariami_cli
flutter build web -t lib/web/main.dart
dart run bin/ariami_cli.dart start

# Run mobile app
cd ariami_mobile && flutter run
```

## Features

### Server (Desktop & CLI)

**Library Management:**
- Automatic scanning with metadata extraction (MP3, M4A, FLAC, OGG, WAV, AIFF, more)
- Album categorization with compilation detection
- Duplicate filtering based on file hash and metadata
- Real-time folder monitoring for automatic updates
- Pure Dart MP3 duration parser (handles large embedded artwork)

**Streaming & Connectivity:**
- HTTP audio streaming with range request support for seeking
- WebSocket support for real-time updates
- QR code generation for easy mobile pairing
- Tailscale integration for secure remote access
- Session-based connection management

**CLI-Specific:**
- Background daemon mode for headless operation
- Automatic transition to background after first-time setup
- Web-based setup interface
- Process management (start, stop, status commands)
- Custom port configuration

**Desktop-Specific:**
- System tray integration with background operation
- Dynamic dock icon control (macOS)
- GUI-based setup and configuration

### Mobile

**Connectivity:**
- QR code scanning to connect to server
- Automatic connection management with heartbeat
- Tailscale support for secure remote connections
- Automatic offline mode detection

**Library & Playback:**
- Library browsing (albums, songs, playlists)
- Advanced search with ranking (exact, prefix, substring matching)
- Audio streaming with background playback support
- Full playback controls (play/pause, skip, shuffle, repeat)
- Queue management with drag-to-reorder

**Offline & Storage:**
- Download songs and albums for offline playback
- Smart caching with LRU eviction for artwork and frequently played songs
- SQLite database for downloads, cache, and statistics
- Streaming statistics (play counts, total listening time)

**UI:**
- Mini player and full-screen player views
- Album detail views with track listings
- Playlist management (create, edit, reorder, delete)

## Tech Stack

- **Frontend**: Flutter for cross-platform UI (mobile, desktop, web)
- **Backend**: Shelf HTTP server framework with REST API and WebSocket support
- **Audio**: just_audio and audio_service for mobile playback with background support
- **Metadata**: dart_tags for ID3/Vorbis tag extraction
- **Networking**: Tailscale for secure device-to-device connectivity
- **Storage**: SQLite (mobile), SharedPreferences (all platforms)
- **File Monitoring**: watcher package for real-time library updates

## Project Structure

```
Ariami/
├── ariami_core/       # Shared platform-agnostic library (Dart package)
│   ├── services/      # Library management, HTTP server, streaming
│   └── models/        # Shared data models
├── ariami_desktop/    # GUI server app (Flutter)
├── ariami_cli/        # Headless server app (Flutter + Dart CLI)
│   ├── bin/           # CLI entry point
│   └── lib/web/       # Flutter web setup UI
├── ariami_mobile/     # Mobile client app (Flutter)
└── context/           # Development documentation

```

## Requirements

- Dart SDK: ^3.9.2
- Flutter: Latest stable version
- For CLI deployment: Linux, macOS, or Windows (supports Raspberry Pi)
