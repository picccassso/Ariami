<div align="center">
  <img src="BMA_icon.png" alt="BMA Logo" width="200"/>
  <h1>BMA (Basic Music App)</h1>
</div>

A cross-platform personal music streaming system built with Flutter. Host your own music library and stream to your devices from anywhere using Tailscale for secure connectivity.

## Architecture

BMA consists of three components:

- **Desktop App** (`bma_desktop`) - GUI server for macOS, Linux, and Windows that indexes your music folder and streams to connected clients
- **CLI App** (`bma_cli`) - Headless server with web-based setup UI for dedicated servers and Raspberry Pi deployments
- **Mobile App** (`bma_mobile`) - Client application for Android and iOS that connects to either server to browse and play your music

All server apps share a common core library (`bma_core`) containing platform-agnostic music library management and HTTP server functionality.

## Quick Start

```bash
# Get dependencies
cd bma_core && dart pub get && cd ..
cd bma_mobile && flutter pub get && cd ..
cd bma_desktop && flutter pub get && cd ..
cd bma_cli && flutter pub get && cd ..

# Run desktop server (GUI)
cd bma_desktop && flutter run -d macos

# Or run CLI server (headless)
cd bma_cli
flutter build web -t lib/web/main.dart
dart run bin/bma_cli.dart start

# Run mobile app
cd bma_mobile && flutter run
```

## Server Features (Desktop & CLI)

- **Library Management**
  - Automatic music library scanning with metadata extraction (MP3, M4A, FLAC, OGG, WAV, AIFF, and more)
  - Album categorization with compilation detection
  - Duplicate filtering based on file hash and metadata matching
  - Real-time folder monitoring for automatic library updates
  - Pure Dart MP3 duration parser (handles large embedded artwork)

- **Streaming & Connectivity**
  - HTTP audio streaming with range request support for seeking
  - WebSocket support for real-time updates
  - QR code generation for easy mobile device pairing
  - Tailscale integration for secure remote access
  - Session-based connection management

- **CLI-Specific Features**
  - Background daemon mode for headless operation
  - Web-based setup interface
  - Automatic browser launching on first run
  - Process management (start, stop, status commands)
  - Custom port configuration

- **Desktop-Specific Features**
  - System tray integration with background operation
  - Dynamic dock icon control (macOS)
  - GUI-based setup and configuration

## Mobile Features

- **Connectivity**
  - QR code scanning to connect to server
  - Automatic connection management with heartbeat
  - Tailscale support for secure remote connections
  - Automatic offline mode detection

- **Library & Playback**
  - Library browsing (albums, songs, playlists)
  - Advanced search with ranking (exact, prefix, substring matching)
  - Audio streaming with background playback support
  - Full playback controls (play/pause, skip, shuffle, repeat)
  - Queue management with drag-to-reorder

- **UI**
  - Mini player and full-screen player views
  - Album detail views with track listings
  - Playlist management (create, edit, reorder, delete)

- **Offline & Storage**
  - Download songs and albums for offline playback
  - Smart caching with LRU eviction for artwork and frequently played songs
  - SQLite database for downloads, cache, and statistics
  - Streaming statistics (play counts, total listening time)

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
BMA/
├── bma_core/          # Shared platform-agnostic library (Dart package)
│   ├── services/      # Library management, HTTP server, streaming
│   └── models/        # Shared data models
├── bma_desktop/       # GUI server app (Flutter)
├── bma_cli/           # Headless server app (Flutter + Dart CLI)
│   ├── bin/           # CLI entry point
│   └── lib/web/       # Flutter web setup UI
├── bma_mobile/        # Mobile client app (Flutter)
└── context/           # Development documentation

```

## Requirements

- Dart SDK: ^3.9.2
- Flutter: Latest stable version
- For CLI deployment: Linux, macOS, or Windows (supports Raspberry Pi)
