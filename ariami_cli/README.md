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
dart build cli -o build/cli-release
./build/cli-release/bundle/bin/ariami_cli start
```

For Raspberry Pi release artifacts (including bundled Sonic transcoding
and SQLite native libraries), use `./build-pi-release-mac.sh` from this
directory. The release archive includes a root `./ariami_cli` launcher.

## Usage

```bash
./ariami_cli start          # Start server (opens browser when ready on first run)
./ariami_cli status         # Check if running
./ariami_cli stop           # Stop server
./ariami_cli start --port 8081  # Custom port

./ariami_cli autostart enable   # Start the server automatically on boot
./ariami_cli autostart disable  # Stop starting on boot
./ariami_cli autostart status   # Show the current setting
```

`autostart` uses the platform's native mechanism (an `@reboot` crontab entry
on Linux/Raspberry Pi, a LaunchAgent on macOS, a `Run` registry key on
Windows) and needs no sudo. First-time setup also asks this as a y/N prompt;
the commands above let you change it later — including on installs set up
before this option existed.

## First Run

1. Run `./ariami_cli start` (foreground on first launch; browser opens when ready)
2. On first run you're asked whether Ariami should **start on boot** (y/N)
3. Complete the web wizard: Tailscale (optional) → music folder → library scan
4. **Create the owner account** (first account is server admin) and sign in as owner
5. Server auto-transitions to background; setup is marked complete
6. Scan the QR code with Ariami Mobile and **register** or log in

If the browser does not open, go to `http://localhost:8080` (or the next free port 8080–8099).

See `REBUILD.md` for rebuild workflows and Raspberry Pi cross-compilation.
