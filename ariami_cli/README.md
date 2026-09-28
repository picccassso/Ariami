# Ariami CLI

Headless music server for Ariami. Runs on servers and Raspberry Pi.

## Features

- Background daemon operation
- Web-based setup wizard and dashboard
- Streaming, scanning, and transcoding from the same `ariami_core` engine as the desktop server
- Multi-user authentication
- Dashboard showing connected users and devices, with controls to kick devices and change passwords
- Library rescan and Spotify Extended Streaming History import/removal from the dashboard

## Building

```bash
cd ariami_cli
flutter pub get
flutter build web -t lib/web/main.dart
dart build cli -o build/cli-release
./build/cli-release/bundle/bin/ariami_cli start
```

For Linux release artifacts built from a Mac (including bundled Sonic
transcoding and SQLite native libraries), use `./build-pi-release-mac.sh`
from this directory. It builds the Raspberry Pi/ARM64 zip by default and
accepts `--arch amd64` for a Linux x64 zip. The release archive includes a
root `./ariami_cli` launcher.

## Usage

```bash
./ariami_cli start                  # Start server
./ariami_cli start --no-browser     # Print setup URLs and do not open a browser
./ariami_cli start --port 8081      # Preferred setup port
./ariami_cli start --host 127.0.0.1 # Bind to localhost only
./ariami_cli start --verbose        # Show stack traces and extra debug output
./ariami_cli status                 # Show server, reachability, auth, data, and backup status
./ariami_cli help music-folder      # Explain a setup step in plain language
./ariami_cli stop                   # Stop server
./ariami_cli --version              # Print the CLI version

./ariami_cli configure --music-folder /home/user/Music  # Set the library path
./ariami_cli music-folder set /home/user/Music          # Same thing, alternate spelling

./ariami_cli autostart enable   # Start the server automatically on boot
./ariami_cli autostart disable  # Stop starting on boot
./ariami_cli autostart status   # Show the current setting

./ariami_cli reset              # Interactive reset menu
./ariami_cli reset --setup      # Reset setup/config only (keep library + accounts)
./ariami_cli reset --factory -y # Factory reset, no prompts
```

By default the server binds to `0.0.0.0`. Normal `start` uses the saved port
after setup; before a port is saved, `--port` sets the preferred setup port.
When a requested port is busy during setup, Ariami may fall back through
8080-8099 unless you explicitly passed `--port`, and setting `ARIAMI_PORT`
counts as explicit too. Use `--host 127.0.0.1` or `--host localhost` only
when other devices should not connect.

Set `ARIAMI_DATA_DIR` to move Ariami's data directory from the default
`~/.ariami_cli` location:

```bash
ARIAMI_DATA_DIR=/srv/ariami-data ./ariami_cli start --no-browser
```

`status` prints the process state, local dashboard reachability, LAN and
Tailscale URLs when available, setup state, music folder state, authentication
summary, data directory, database/cache names, and a backup reminder.

For SSH, Raspberry Pi, NAS, and homelab installs, see [HEADLESS.md](HEADLESS.md).
For Docker and Compose, see [docker/DOCKER.md](docker/DOCKER.md).

`reset` clears Ariami's local state so you can start over. **Setup/config
only** removes setup progress, server configuration, and runtime state from
the data directory while keeping the catalogue database, accounts, sessions,
and caches. **Factory reset** also removes accounts, sessions, the catalogue
database, metadata and music discovery caches, cached artwork, and cached
transcodes, and disables start-on-boot. Both stop the server first if it is
running, require typing `RESET` to confirm (unless `-y` is passed), and
**never touch your music folder**.

`autostart` uses the platform's native mechanism (an `@reboot` crontab entry
on Linux/Raspberry Pi, a LaunchAgent on macOS, a `Run` registry key on
Windows) and needs no sudo. First-time setup also asks this as a y/N prompt;
the commands above let you change it later, including on installs set up
before this option existed.

## First Run

1. Run `./ariami_cli start` (or `./ariami_cli start --no-browser` over SSH)
2. On first run you're asked whether Ariami should **start on boot** (y/N), unless the session is non-interactive
3. Complete the web wizard: Tailscale (optional) → music folder → library scan
4. **Create the owner account** (first account is server admin) and sign in as owner
5. Server auto-transitions to background; setup is marked complete
6. Scan the QR code with Ariami Mobile and **register** or log in

Use `./ariami_cli help` for a short explanation of Ariami, or add one of
`tailscale`, `music-folder`, `scan`, `owner`, or `connect` for the relevant
setup step. The browser wizard has the same contextual guidance under its
information buttons.

If the browser does not open, use one of the URLs printed by the server. On a
headless machine, open the LAN or Tailscale URL from another browser that can
reach the server.

See [REBUILD.md](REBUILD.md) for rebuild workflows and Linux cross-compilation.

## Documentation

The full documentation set lives in [docs/](docs/README.md):

- [OVERVIEW.md](docs/OVERVIEW.md): what Ariami CLI is and how it fits together
- [INSTALLATION.md](docs/INSTALLATION.md): picking an install path
- [CLI_REFERENCE.md](docs/CLI_REFERENCE.md): every command, flag, and exit code
- [CONFIGURATION.md](docs/CONFIGURATION.md): data directory, `config.json`, environment variables
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): symptom → cause → fix
- [FAQ.md](docs/FAQ.md): short answers to common questions
