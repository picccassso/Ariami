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
./ariami_cli start                  # Start server
./ariami_cli start --no-browser     # Print setup URLs and do not open a browser
./ariami_cli start --port 8081      # Preferred setup port
./ariami_cli start --host 127.0.0.1 # Bind to localhost only
./ariami_cli start --verbose        # Show stack traces and extra debug output
./ariami_cli status                 # Show server, reachability, auth, data, and backup status
./ariami_cli stop                   # Stop server

./ariami_cli autostart enable   # Start the server automatically on boot
./ariami_cli autostart disable  # Stop starting on boot
./ariami_cli autostart status   # Show the current setting

./ariami_cli reset              # Interactive reset menu
./ariami_cli reset --setup      # Reset setup/config only (keep library + accounts)
./ariami_cli reset --factory -y # Factory reset all Ariami data, no prompts
```

By default the server binds to `0.0.0.0`. Normal `start` uses the saved port
after setup; before a port is saved, `--port` sets the preferred setup port.
When a requested port is busy during setup, Ariami may fall back through
8080-8099 unless you explicitly passed `--port`. Use `--host 127.0.0.1` or
`--host localhost` only when other devices should not connect.

Set `ARIAMI_DATA_DIR` to move Ariami's data directory from the default
`~/.ariami_cli` location:

```bash
ARIAMI_DATA_DIR=/srv/ariami-data ./ariami_cli start --no-browser
```

`status` now prints the process state, local dashboard reachability, LAN and
Tailscale URLs when available, setup state, music folder state, authentication
summary, data directory, database/cache names, and a backup reminder.

For SSH, Raspberry Pi, NAS, and homelab installs, see [HEADLESS.md](HEADLESS.md).

`reset` clears Ariami's local state so you can start over. **Setup/config only**
removes setup progress, server config and pairing state but keeps the catalog
database and accounts. **Factory reset** removes everything Ariami owns under
the Ariami data directory, `~/.ariami_cli` by default (database, accounts,
sessions, caches), and disables start-on-boot.
Both require typing `RESET` to confirm (unless `-y` is passed), stop the server
first if it is running, and **never touch your music folder**.

`autostart` uses the platform's native mechanism (an `@reboot` crontab entry
on Linux/Raspberry Pi, a LaunchAgent on macOS, a `Run` registry key on
Windows) and needs no sudo. First-time setup also asks this as a y/N prompt;
the commands above let you change it later — including on installs set up
before this option existed.

## First Run

1. Run `./ariami_cli start` (or `./ariami_cli start --no-browser` over SSH)
2. On first run you're asked whether Ariami should **start on boot** (y/N), unless the session is non-interactive
3. Complete the web wizard: Tailscale (optional) → music folder → library scan
4. **Create the owner account** (first account is server admin) and sign in as owner
5. Server auto-transitions to background; setup is marked complete
6. Scan the QR code with Ariami Mobile and **register** or log in

If the browser does not open, use one of the URLs printed by the server. On a
headless machine, open the LAN or Tailscale URL from another browser that can
reach the server.

See `REBUILD.md` for rebuild workflows and Raspberry Pi cross-compilation.
