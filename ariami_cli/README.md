# Ariami CLI

Headless music server for Ariami. Runs on servers and Raspberry Pi.

## Features

- Background daemon operation
- Web-based setup interface and dashboard
- Same streaming capabilities as Desktop
- Multi-user authentication
- Dashboard showing connected users and devices with admin controls (kick devices, change passwords)

## Building

```bash
cd ariami_cli
flutter pub get
flutter build web -t lib/web/main.dart
dart compile exe bin/ariami_cli.dart -o ariami_cli
```

## Usage

```bash
./ariami_cli start          # Start server (opens browser on first run)
./ariami_cli status         # Check if running
./ariami_cli stop           # Stop server
./ariami_cli start --port 8081  # Custom port
```

## First Run

1. Run `./ariami_cli start`
2. Browser opens to web setup
3. Select music folder and wait for scan
4. Server auto-transitions to background
5. Scan QR code with Ariami Mobile

See `REBUILD.md` for rebuild workflows and Raspberry Pi cross-compilation.
