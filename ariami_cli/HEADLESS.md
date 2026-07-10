# Ariami CLI Headless Guide

This guide is for SSH, Raspberry Pi, NAS, and homelab installs. It documents
the current CLI behavior. It does not describe planned features.

## Downloads

Pick the zip for your server from the GitHub release page
(https://github.com/picccassso/Ariami/releases):

| Zip | For |
| --- | --- |
| `ariami-cli-raspberry-pi-arm64-v<version>.zip` | Raspberry Pi 3/4/5 and any ARM64 Linux box |
| `ariami-cli-linux-x64-v<version>.zip` | Proxmox LXC, NAS, generic x86-64 Linux servers |
| `ariami-cli-macos-arm64-v<version>.zip` | Apple Silicon Macs |
| `ariami-cli-windows-x64-v<version>.zip` | Windows x64 (run `ariami_cli.bat` instead of `./ariami_cli`) |

Linux zips need glibc 2.35+ (Ubuntu 22.04 / Debian 12 / Raspberry Pi OS
Bookworm or newer). On macOS, if the zip came through a browser, clear the
quarantine flag once: `xattr -dr com.apple.quarantine <extracted dir>`.

## Quick Start Over SSH

```bash
unzip ariami-cli-raspberry-pi-arm64-v4.4.0.zip   # or the linux-x64 zip
cd ariami-cli-raspberry-pi-arm64-v4.4.0
chmod +x ariami_cli
./ariami_cli start --no-browser
```

On first run, keep the terminal open. Ariami prints setup URLs:

- `This machine`: use this only on the same machine.
- `Same network`: open this from another device on the LAN.
- `Tailscale`: open this from a device signed in to the same tailnet, when
  Tailscale is detected.

Complete setup in the browser, create the owner account immediately, then use
the dashboard QR code to connect mobile clients.

## Flags And Environment

| Name | Type | Use |
| --- | --- | --- |
| `--port <port>`, `-p <port>` | flag | Preferred HTTP port before a port is saved. Default is `8080`. During setup, Ariami can fall back through `8080`-`8099` when the port was not explicitly requested. An explicit port disables fallback. Normal `start` uses the saved port after setup. |
| `--host <address>` | flag | HTTP bind address. Default is `0.0.0.0`. Use `127.0.0.1` or `localhost` only for local-only access. An explicit value is saved for future starts. |
| `--no-browser` | flag | During setup, print URLs and never try to auto-open a browser. This is the normal SSH option. |
| `--verbose` | flag | Show stack traces and extra debug output for startup failures. |
| `ARIAMI_DATA_DIR` | environment | Overrides the default data directory, `~/.ariami_cli`, for that process. Set it consistently for `start`, `stop`, `status`, `reset`, and backups. |
| `ARIAMI_ADVERTISED_HOST` | environment | Overrides the host Ariami advertises in setup URLs, server info, and QR codes. Useful in containers; set it to the host machine's LAN or Tailscale IP. |
| `ARIAMI_ADVERTISED_LAN_HOST` | environment | Overrides the LAN host Ariami advertises in setup URLs, server info, and QR codes. Useful in containers; set it to the host machine's LAN IP for same-network devices. |
| `ARIAMI_ADVERTISED_TAILSCALE_HOST` | environment | Overrides the Tailscale host Ariami advertises in setup URLs, server info, and QR codes. Useful in containers; set it to the host machine's Tailscale IP for remote devices with Tailscale enabled. |
| `ARIAMI_CONTAINER` | environment | Set to `1` or `true` to tell Ariami it is running in a container. Docker images set this automatically. |
| `ARIAMI_TRUST_PROXY_HEADERS` | environment | Set to `1` only when a reverse proxy you control fronts Ariami: the server then uses `X-Forwarded-For` for login rate limiting. Leave unset otherwise — direct clients can forge the header. |

Until an owner account exists, the server prints a one-time **setup code** on
its console at startup. Creating the owner account from the web dashboard on
another device requires that code; a browser on the server machine itself
(`http://localhost:<port>`) does not.

The CLI also has an internal `--server-mode` flag. It runs the server in the
foreground for a supervisor. Use it only for service managers such as systemd.

## Data And Backup

Ariami data lives in `ARIAMI_DATA_DIR` when set, otherwise in `~/.ariami_cli`.
Your music files live in the music folder you choose during setup. Ariami stores
that folder path, but it does not copy your music into the data directory.

Expected data directory contents:

| Path | Purpose |
| --- | --- |
| `config.json` | Setup state, music folder path, server port, bind host, and CLI settings. |
| `users.json` | User account records. |
| `sessions.json` | Active web/mobile sessions. |
| `catalog.db` | Persistent library catalog database. |
| `metadata_cache.json` | Library metadata cache. |
| `artwork_cache/` | Generated artwork thumbnails/cache. |
| `transcoded_cache/` | Generated audio transcode cache. |
| `ariami.pid` | Runtime process ID for `status` and `stop`. |
| `server.json` | Runtime server state such as port, PID, and start time. |
| `server.log` | Startup/runtime log file, when present. |
| `autostart.log` | Boot log file created by built-in autostart, when present. |

Back up the whole data directory before upgrades or migrations. At minimum,
preserve `config.json`, `users.json`, `sessions.json`, `catalog.db`,
`metadata_cache.json`, `artwork_cache/`, and `transcoded_cache/`.
`ariami.pid`, `server.json`, `server.log`, and `autostart.log` are runtime
state and can be recreated.

Use `./ariami_cli status` to confirm the active data directory before backing
it up.

## Update Procedure

1. Stop the server:

   ```bash
   ./ariami_cli stop
   ```

2. Back up the data directory shown by `./ariami_cli status`.
3. Replace the extracted release files with the new release. Do not delete the
   data directory.
4. Start Ariami again:

   ```bash
   ./ariami_cli start
   ```

5. Verify it:

   ```bash
   ./ariami_cli status
   ```

The `Reachable` line should say the dashboard is responding on the active port.

## Autostart On Boot

The built-in path is:

```bash
./ariami_cli autostart enable
./ariami_cli autostart status
./ariami_cli autostart disable
```

On Linux and Raspberry Pi OS, this writes an `@reboot` crontab entry for the
current user and logs boot output to `autostart.log` in the Ariami data
directory. It does not require sudo. macOS uses a LaunchAgent. Windows uses the
current user's Run registry key.

The built-in autostart command starts Ariami with its normal `start` command.
It does not add `ARIAMI_DATA_DIR` to the generated boot entry. If you require a
custom data directory at boot, make sure the boot environment sets
`ARIAMI_DATA_DIR`, or use a supervisor such as systemd where the environment is
explicit.

First-time setup asks whether to enable start-on-boot when stdin is interactive.
In non-interactive sessions, Ariami skips the prompt and tells you to run
`ariami_cli autostart enable` if you want it.

## systemd Alternative

`autostart` is the supported built-in path. On servers that already use systemd,
you can run Ariami under systemd instead. In that mode, use the hidden
`--server-mode` flag so Ariami stays in the foreground and systemd supervises
the process directly.

Example unit:

```ini
[Unit]
Description=Ariami CLI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ariami
WorkingDirectory=/opt/ariami
Environment=ARIAMI_DATA_DIR=/var/lib/ariami
ExecStart=/opt/ariami/ariami_cli --server-mode --port 8080 --host 0.0.0.0
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Notes:

- `--server-mode` writes Ariami's PID file and runs the HTTP server in the
  foreground until it receives a shutdown signal.
- `--port` defaults to `8080`. In `--server-mode`, port fallback is disabled.
- `--host` is optional. If present, Ariami saves it in `config.json`.
- `User=` must be able to read the music folder and write `ARIAMI_DATA_DIR`.
- Set `ARIAMI_DATA_DIR` explicitly for service installs so upgrades do not
  depend on a home directory.
- Do not use the built-in `autostart enable` and a systemd unit at the same
  time.

## Security Posture

- Keep Ariami on LAN, Tailscale, or another VPN.
- Do not port-forward Ariami to the public internet.
- Create the owner account immediately during first setup. The first account is
  the server admin.
- Authentication is always enabled. If no owner account exists, `status` and
  the startup banner warn you to create one.
- Startup and status output print URLs, state, and paths. They do not print
  account passwords, session tokens, or QR registration secrets.
- If you bind to `0.0.0.0`, any device that can reach the host and port can
  attempt to load the dashboard. Keep the network boundary private.

## Manual Test Checklist

- Fresh first run: start with an empty data directory, run
  `./ariami_cli start --no-browser`, open the printed URL, choose the music
  folder, scan, create the owner account, and confirm transition to background.
- Configured restart: run `./ariami_cli stop`, then `./ariami_cli start`, then
  `./ariami_cli status`.
- SSH/no-GUI run: confirm `--no-browser` prints URLs and does not attempt to
  open a browser.
- Port in use: occupy port `8080`, run setup without an explicit port, and
  confirm fallback to another port in `8080`-`8099`.
- Invalid music directory: configure a missing music path and confirm startup
  warns that the folder is missing.
- No owner account: start with setup incomplete or no users and confirm the
  auth warning appears.
- LAN and Tailscale access: confirm dashboard URLs work from a LAN browser and,
  when Tailscale is installed, from a tailnet device.
- Mobile browser dashboard: open the dashboard from a phone browser and sign in.
- Client connect: scan the dashboard QR code with Ariami Mobile and register or
  log in.
- Graceful shutdown: use Ctrl+C during foreground setup and `./ariami_cli stop`
  for a background server.
