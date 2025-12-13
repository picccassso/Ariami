# BMA CLI

Headless music server for BMA (Basic Music App). Designed for deployment on servers, Raspberry Pi, and other headless environments.

## Overview

BMA CLI is a command-line music server that provides the same functionality as the desktop app but without a GUI. It features a web-based setup interface and runs as a background daemon process.

## Features

- Headless operation (no GUI required)
- Background daemon mode with process management
- Web-based setup interface (auto-opens on first run)
- Music library scanning and indexing
- HTTP server with REST API and WebSocket support
- Audio streaming with range request support
- QR code generation for mobile client pairing
- Tailscale integration for secure remote access
- Real-time library monitoring and updates
- Cross-platform support (macOS, Linux, Windows)

## Prerequisites

- Dart SDK: ^3.9.2
- Flutter SDK (for building web UI)

## Installation

```bash
cd bma_cli

# Install dependencies
flutter pub get

# Build web UI (required before running)
flutter build web -t lib/web/main.dart

# Compile to executable
dart compile exe bin/bma_cli.dart -o bma_cli
```

## Usage

### First Run

On first run, the server runs in foreground mode and automatically opens a browser to the web setup interface:

```bash
./bma_cli start
```

Follow the web setup wizard to:
1. Configure Tailscale (optional)
2. Select your music folder
3. Wait for library scanning
4. View QR code for mobile app connection

### Subsequent Runs

After initial setup, the server runs as a background daemon:

```bash
# Start server in background
./bma_cli start

# Check server status
./bma_cli status

# Stop server
./bma_cli stop
```

### Custom Port

```bash
./bma_cli start --port 8081
```

## Configuration

Configuration is stored separately from bma_desktop:

- macOS/Linux: `~/.bma_cli/`
- Windows: `%APPDATA%\.bma_cli\`

Files:
- `config.json` - Server settings and music folder path
- `server.pid` - Process ID of running server

## Commands

- `start` - Start the server (foreground on first run, background after setup)
- `stop` - Stop the background server gracefully
- `status` - Check if server is running and show PID
- `--port <port>` - Specify custom port (default: 8080)

## Web Interface

Access the web interface at:
- Local: `http://localhost:8080`
- Tailscale: `http://<tailscale-ip>:8080`

## Development

### Running in Development Mode

```bash
# Build web UI
flutter build web -t lib/web/main.dart

# Run directly with Dart (foreground mode)
dart run bin/bma_cli.dart start
```

### Rebuilding Web UI

See `REBUILD.md` for detailed rebuild workflows.

Quick rebuild:
```bash
flutter build web -t lib/web/main.dart
# Then hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)
```

### Running Tests

```bash
flutter test
```

## Installation (Global)

To install globally and use from anywhere:

```bash
dart compile exe bin/bma_cli.dart -o /usr/local/bin/bma_cli
chmod +x /usr/local/bin/bma_cli

# Now use from anywhere
bma_cli start
```

## Process Management

The CLI uses a daemon service for background process management:
- PID file stored in `~/.bma_cli/server.pid`
- Graceful shutdown via SIGTERM signal
- Automatic resource cleanup on exit

## Supported Audio Formats

MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC
