# BMA Mobile

Mobile client for BMA (Basic Music App). Native Android and iOS application for streaming music from BMA servers.

## Overview

BMA Mobile is a music streaming client that connects to BMA Desktop or BMA CLI servers. It features background playback, offline mode, download management, playlist support, and comprehensive library browsing capabilities.

## Features

### Library & Playback
- Full library browsing (albums, songs, artists)
- Audio streaming from server
- Background playback with lock screen controls
- Queue management with drag-to-reorder
- Shuffle and repeat modes
- Advanced search with ranking (exact, prefix, substring matching)
- Mini player and full-screen player views

### Offline Support
- Download songs and albums for offline playback
- Background download manager with progress tracking
- Automatic offline mode when server unavailable
- Smart cache management with LRU eviction
- Downloaded content persisted across app restarts

### Connectivity
- QR code scanning for easy server connection
- Automatic connection management with heartbeat
- WebSocket for real-time library updates
- Tailscale support for secure remote connections
- Session-based authentication

### Storage & Data
- SQLite databases for cache, downloads, and statistics
- Streaming statistics tracking (play counts, listening time)
- Artwork caching for improved performance
- Playlist management (create, edit, reorder, delete)

### User Experience
- High refresh rate display support
- Smooth animations and transitions
- Album detail views with track listings
- Real-time playback progress
- Network status indicators

## Prerequisites

- Flutter SDK (latest stable)
- Platform-specific tools:
  - Android: Android Studio, Android SDK
  - iOS: Xcode (macOS only)
- A physical device or emulator

## Installation

```bash
cd bma_mobile

# Install dependencies
flutter pub get
```

## Running

### Development

```bash
# List available devices
flutter devices

# Run on connected device/emulator
flutter run

# Run on specific device
flutter run -d <device-id>
```

### Building

```bash
# Android APK
flutter build apk

# Android App Bundle
flutter build appbundle

# iOS (requires macOS)
flutter build ios
```

Build outputs:
- Android APK: `build/app/outputs/flutter-apk/app-release.apk`
- Android Bundle: `build/app/outputs/bundle/release/app-release.aab`
- iOS: Open `ios/Runner.xcworkspace` in Xcode for signing and distribution

## First-Time Setup

1. Launch the app
2. Tap "Scan QR Code"
3. Grant camera permissions when prompted
4. Scan the QR code from your BMA Desktop or CLI server
5. App connects automatically and loads library

## Permissions

### Android
- Camera - QR code scanning
- Internet - Server connectivity
- Network state - Connection monitoring
- Storage - Downloads and cache
- Wake lock - Background playback

### iOS
- Camera - QR code scanning
- Network - Server connectivity
- Background audio - Continued playback when app is backgrounded

Permissions are requested at runtime when needed.

## Architecture

### Services

**API Services** (`services/api/`):
- `connection_service.dart` - Server connection and session management
- `api_client.dart` - HTTP client for REST API calls
- `websocket_service.dart` - Real-time updates from server

**Audio Services** (`services/audio/`):
- `audio_handler.dart` - Background playback with OS integration
- `playback_state_manager.dart` - Playback state coordination
- `audio_player_service.dart` - Low-level audio playback

**Storage Services**:
- `cache/cache_manager.dart` - LRU cache for artwork and songs
- `download/download_manager.dart` - Background downloads
- `offline/offline_playback_service.dart` - Offline playback
- `stats/streaming_stats_service.dart` - Usage statistics

**Other Services**:
- `playback_manager.dart` - High-level playback coordination
- `playlist_service.dart` - Playlist CRUD operations
- `search_service.dart` - Search with ranking
- `permissions_service.dart` - Permission handling

### Databases

Three SQLite databases in `lib/database/`:
- `cache_database.dart` - Cached artwork and frequently played songs
- `download_database.dart` - Downloaded songs with file paths and status
- `stats_database.dart` - Play counts, listening time, timestamps

## Background Playback

BMA Mobile uses `audio_service` package for background playback:
- Continues playing when app is backgrounded
- Lock screen controls (play, pause, skip)
- Android notification with artwork and controls
- iOS control center integration
- Automatic resumption after interruptions (calls, alarms)

## Offline Mode

When server is unavailable:
- App automatically switches to offline mode
- Only downloaded songs are playable
- UI indicates offline status
- Seamlessly switches back when server becomes available

## Development

### Running Tests

```bash
flutter test
```

### Code Analysis

```bash
flutter analyze
```

### Hot Reload

During development with `flutter run`:
- Press `r` for hot reload
- Press `R` for hot restart
- Press `q` to quit

### Debugging

Run with verbose logging:
```bash
flutter run -v

# Filter logs
flutter logs | grep "BMA:"
```

## Dependencies

Key dependencies:
- `just_audio` - Advanced audio playback
- `audio_service` - Background playback service
- `sqflite` - SQLite database
- `mobile_scanner` - QR code scanning
- `permission_handler` - Runtime permissions
- `web_socket_channel` - WebSocket connectivity
- `dio` - HTTP client with progress tracking
- `uuid` - Device ID generation
- `package_info_plus` - App version information

## Connection Flow

1. User scans QR code from server
2. QR code contains server IP (local or Tailscale), port, credentials
3. App calls `POST /api/connect` with device info
4. Server returns sessionId
5. App establishes WebSocket for real-time updates
6. Server validates connection via heartbeat (60s timeout)

## Troubleshooting

### Can't Scan QR Code
- Grant camera permissions in device settings
- Ensure QR code is well-lit and in focus
- Check camera is working in other apps

### Can't Connect to Server
- Verify mobile and server are on same network
- Check server is running (`bma_cli status` or check desktop app)
- Ensure firewall allows connections on server port
- For remote: Verify Tailscale is connected on both devices

### Audio Won't Play
- Check internet connection (or downloaded content for offline)
- Verify server has the song file
- Check device volume and silent mode
- Look for errors in logs: `flutter logs | grep "BMA:"`

### Downloads Failing
- Check available storage space
- Verify server is reachable
- Check download database isn't corrupted
- Clear app data and reconnect to server

### Background Playback Not Working
- Android: Ensure battery optimization is disabled for BMA
- iOS: Background audio capability must be enabled
- Check notification permissions are granted
- Restart app and try again

## Platform-Specific Notes

### Android
- Requires Android 5.0 (API level 21) or higher
- Background playback uses foreground service with notification
- Downloads stored in app-specific directory
- High refresh rate support on compatible devices

### iOS
- Requires iOS 12.0 or higher
- Background audio capability configured in Info.plist
- Downloads stored in app Documents directory
- Automatic dark mode based on system settings
