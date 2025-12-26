# BMA Desktop

GUI music server for BMA (Basic Music App). Cross-platform desktop application for macOS, Linux, and Windows.

## Overview

BMA Desktop is a graphical music server that indexes your local music library and streams it to connected mobile clients. It features a native system tray integration, automatic library monitoring, and optional Tailscale connectivity for secure remote access.

## Features

### Library Management
- Automatic music library scanning and indexing
- Support for multiple audio formats (MP3, M4A, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC)
- Real-time folder monitoring for automatic updates
- Duplicate detection and filtering
- Album artwork extraction and serving
- Compilation album detection

### Server & Connectivity
- HTTP server with REST API and WebSocket support
- Audio streaming with range request support for seeking
- QR code generation for easy mobile client pairing
- Connection management with heartbeat monitoring
- Tailscale integration for secure remote access
- Local network and internet connectivity options

### Desktop Integration
- System tray icon with quick access menu
- Background operation (minimizes to tray instead of quitting)
- macOS dock icon management (hides when minimized to tray)
- Cross-platform support (macOS, Linux, Windows)
- Persistent server state across restarts

### User Interface
- Setup wizard for first-time configuration
- Dashboard with server status and connected clients
- Real-time client connection monitoring
- QR code display for mobile pairing
- Tailscale status and configuration

## Prerequisites

- Dart SDK: ^3.9.2
- Flutter SDK (latest stable)
- Platform-specific requirements:
  - macOS: Xcode command-line tools
  - Linux: Development libraries (varies by distribution)
  - Windows: Visual Studio 2022 or later

## Installation

```bash
cd bma_desktop

# Install dependencies
flutter pub get
```

## Running

### Development

```bash
# macOS
flutter run -d macos

# Linux
flutter run -d linux

# Windows
flutter run -d windows
```

### Building

```bash
# macOS
flutter build macos

# Linux
flutter build linux

# Windows
flutter build windows
```

Build outputs:
- macOS: `build/macos/Build/Products/Release/bma_desktop.app`
- Linux: `build/linux/x64/release/bundle/`
- Windows: `build/windows/x64/runner/Release/`

## First-Time Setup

1. Launch the application
2. Complete the setup wizard:
   - Configure Tailscale (optional)
   - Select your music folder
   - Wait for initial library scan
   - View QR code for mobile app connection
3. Server starts automatically and minimizes to system tray

## System Tray

The desktop app integrates with the system tray:
- Click tray icon to show/hide main window
- Right-click for menu options (Show BMA, Quit)
- Server continues running when window is closed
- macOS: Dock icon automatically hides/shows based on window visibility

## Configuration

Configuration is stored in platform-specific locations:
- macOS: `~/Library/Application Support/bma_desktop`
- Linux: `~/.local/share/bma_desktop`
- Windows: `%APPDATA%\bma_desktop`

Settings stored:
- Music folder path
- Server port
- Tailscale configuration
- Setup completion status

## API Endpoints

The server exposes the following REST endpoints:

- `GET /api/ping` - Health check
- `POST /api/connect` - Client connection
- `POST /api/disconnect` - Client disconnection
- `GET /api/library` - Full library structure
- `GET /api/albums` - List all albums
- `GET /api/albums/<id>` - Album details
- `GET /api/songs` - All songs
- `GET /api/artwork/<id>` - Album artwork
- `GET /api/stream/<path>` - Stream audio file
- `GET /api/download/<path>` - Download audio file
- `GET /api/stats` - Server statistics
- `GET /api/ws` - WebSocket connection

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
flutter run -d macos -v
```

## Assets

Required assets in `assets/` directory:
- `app_icon.png` - System tray icon for macOS and Linux
- `app_icon.ico` - System tray icon for Windows

## Platform-Specific Notes

### macOS
- Uses `NSApp.setActivationPolicy` to dynamically hide/show dock icon
- Dock icon visible when window is shown, hidden when minimized to tray
- Requires camera permissions for QR code display (set in Info.plist)

### Linux
- System tray support varies by desktop environment
- Some environments may require additional packages for tray support

### Windows
- System tray icon uses `.ico` format
- May require firewall rules for network access

## Dependencies

Key dependencies:
- `bma_core` - Shared core library (path dependency)
- `tray_manager` - Cross-platform system tray support
- `window_manager` - Window management and close interception
- `qr_flutter` - QR code generation
- `file_picker` - Folder selection dialog
- `shared_preferences` - Configuration storage
- `path_provider` - Platform-specific paths

## Troubleshooting

### Server Won't Start
- Check that port 8080 is not already in use
- Verify music folder has read permissions
- Check logs for error messages

### System Tray Not Working
- Linux: Ensure desktop environment supports system tray
- Windows: Check that app has permission to create tray icons

### Library Not Scanning
- Verify folder permissions
- Check that folder contains supported audio formats
- Look for error messages in console output

### Mobile Can't Connect
- Ensure desktop and mobile are on same network (or using Tailscale)
- Check firewall allows connections on port 8080
- Verify QR code was scanned correctly
