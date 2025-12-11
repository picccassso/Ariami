# BMA CLI

Command-line version of BMA (Basic Music App) for headless servers and Raspberry Pi.

## Features

- Runs as a background daemon process
- Web-based setup interface (auto-opens in browser)
- Same functionality as desktop app (library scanning, HTTP server, streaming)
- No GUI required - perfect for headless servers
- Supports macOS, Linux, Windows

## Installation

```bash
cd bma_cli
dart pub get
dart compile exe bin/bma_cli.dart -o bma_cli
```

## Usage

```bash
# Start the server (first time - opens web browser for setup)
./bma_cli start

# Check server status
./bma_cli status

# Stop the server
./bma_cli stop
```

## Configuration

Configuration is stored separately from bma_desktop in:
- macOS/Linux: `~/.bma_cli/`
- Windows: `%APPDATA%\.bma_cli\`

## Web Interface

After starting, access the web interface at:
- `http://localhost:8080` (local)
- `http://<tailscale-ip>:8080` (Tailscale network)
