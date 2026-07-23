# What Is Ariami CLI?

Ariami CLI is the **headless / server variant** of Ariami: a self-hosted music
streaming server you run without a desktop GUI, on a Raspberry Pi, a NAS, a
Proxmox LXC, a generic Linux/macOS/Windows box, or in Docker. It is a real
CLI executable (`ariami_cli`) that runs the same Ariami server engine as the
rest of the project, sets it up through a **web browser** instead of a native
UI, and can daemonize itself into the background as a long-running service.

This document explains what it is, who it is for, and how it fits together
with the rest of the Ariami monorepo. It documents current, verifiable
behavior only — see [`README.md`](README.md) for the full documentation set.

## Who it's for

Ariami CLI is for people who want to run an Ariami server on a machine that
either has no desktop environment (SSH-only servers, headless Raspberry Pi,
NAS boxes, Proxmox/LXC containers) or where a background service makes more
sense than a foreground desktop app — including plain Docker hosts.

If you have a desktop machine and want an interactive GUI server instead,
that is a different package in this monorepo (`ariami_desktop`) and is out of
scope for this document set, which covers `ariami_cli` only.

## What it does

- Runs a first-run **web setup wizard** (served by the CLI itself) that walks
  you through optional Tailscale detection, choosing your music folder,
  scanning your library, and creating the owner account.
- Serves a **web dashboard** afterwards for managing users, viewing connected
  devices/sessions, and checking server health — no separate app needed on
  the server machine.
- Scans your music folder for tags and artwork and builds a persistent
  library **catalog database** (SQLite) so restarts don't require a full
  rescan (`lib/services/server_media_services_configurator.dart`,
  `ariami_core/lib/services/catalog/`).
- Handles **multi-user authentication** (accounts, sessions, rate-limited
  login) so each person in the household gets their own sign-in.
- Transcodes audio on the fly for lower-bandwidth quality tiers, using a
  bundled native library (Sonic), and generates artwork thumbnails via
  FFmpeg when available.
- Advertises itself on the LAN and (optionally) over Tailscale, including a
  best-effort discovery beacon so client apps can find it automatically.
- Can daemonize into the background after setup (`ariami_cli start`), be
  managed with `stop`/`status`, and be configured to start automatically on
  boot (`ariami_cli autostart`) — or run in the foreground under a
  supervisor such as systemd or Docker (`--server-mode`).

See [`CLI_REFERENCE.md`](CLI_REFERENCE.md) for every command and flag, and
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for how these pieces fail and how
to fix them.

## How it relates to `ariami_core`

`ariami_cli`'s `pubspec.yaml` depends on `ariami_core` as a local path
dependency (`../ariami_core`). `ariami_core` is the shared engine: the actual
HTTP server (`AriamiHttpServer`, built on `shelf`/`shelf_router`), the
library scanner and catalog database, the auth service, the transcoding and
artwork services, and LAN/Tailscale discovery. `ariami_cli` itself is
intentionally thin — it is the argument parser, the daemon/process
management (PID files, background start, autostart), the CLI-specific state
file (`config.json` and friends under the Ariami data directory), and the
Flutter-web setup/dashboard UI (`lib/web/`) that talks to that same core
server over its own HTTP API.

Concretely: `lib/server_runner.dart` wires CLI-specific concerns (data
directory, feature flags, Raspberry Pi runtime tuning, port fallback) into
`AriamiHttpServer` from `ariami_core`, then hands control to it.

## How it relates to the mobile client

Ariami CLI does not include or require any particular client. Any Ariami
server — CLI, or otherwise — is paired with client apps over the network by
scanning a QR code from the web dashboard, or entering the server address
manually. The publicly available, free client in this repository's release
matrix is **Ariami Mobile** (Android APK, or build-from-source on iOS, per
the top-level project `README.md`). The CLI's own web dashboard shows the
pairing QR code and setup URLs after the owner account is created.

## What platforms it targets

Verified from the CLI release build workflow
(`.github/workflows/cli-artifacts.yml`), the Docker workflow
(`.github/workflows/docker-image.yml`), and the existing `HEADLESS.md` /
`SETUP.txt` guides:

| Target | Notes |
| --- | --- |
| Linux x64 | Generic x86-64 Linux servers, NAS, Proxmox LXC. Needs glibc 2.35+ (Ubuntu 22.04, Debian 12, or newer). |
| Linux arm64 | Raspberry Pi 3/4/5 and any other ARM64 Linux box. Same glibc requirement, including Raspberry Pi OS Bookworm or newer. |
| macOS arm64 | Apple Silicon Macs. |
| Windows x64 | Runs via the bundled `ariami_cli.bat` launcher. |
| Docker (linux/amd64, linux/arm64) | Multi-stage image built from `docker/Dockerfile`; published to `ghcr.io/picccassso/ariami-cli` by `.github/workflows/docker-image.yml`, and buildable locally per `docker/DOCKER.md`. |

The Raspberry Pi build additionally bundles a native Sonic transcoding
library (`libsonic_transcoder.so`) and, for the release zip, a bundled
`libsqlite3.so`; see `build-pi-release-mac.sh` and `REBUILD.md`.

The server itself also detects at runtime whether it's actually running on a
Raspberry Pi (and which storage type backs your music/data) to pick more
conservative concurrency and cache limits — see
[`CONFIGURATION.md`](CONFIGURATION.md#runtime-tuning-raspberry-pi--storage-detection)
and [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#memory--performance-on-low-end-hardware).

## Under the hood (for context, not required reading)

- Language/runtime: Dart + Flutter (`environment: sdk: ^3.5.0` in
  `pubspec.yaml`), version `5.0.0`.
  - The CLI executable itself is plain Dart (`bin/ariami_cli.dart`).
  - The setup/dashboard UI (`lib/web/`) is a Flutter web app, built once with
    `flutter build web -t lib/web/main.dart` and served as static files by
    the same server.
- HTTP server: `shelf` + `shelf_router` + `shelf_web_socket` (from
  `ariami_core`).
- Catalog database: `sqlite3` (pure-Dart SQLite runtime).
- Metadata extraction: `dart_tags`. Password hashing: `bcrypt`.
- Audio transcoding: a bundled native library, Sonic (Rust, from the `sonic`
  submodule in this monorepo), used when present; the server falls back to
  serving original files when it is not (see `TROUBLESHOOTING.md`).
- Artwork thumbnails: FFmpeg, when found on the host; otherwise original
  artwork is served unresized.

## See also

- [`README.md`](README.md) — index of this documentation set.
- [`CLI_REFERENCE.md`](CLI_REFERENCE.md) — every command, flag, and exit code.
- [`CONFIGURATION.md`](CONFIGURATION.md) — data directory layout, config
  keys, and environment variables.
- [`INSTALLATION.md`](INSTALLATION.md) — install/deploy paths (native,
  systemd, Docker, autostart, building from source).
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — symptom → cause → fix.
- [`FAQ.md`](FAQ.md).
- The existing top-level guides this package already ships:
  [`../HEADLESS.md`](../HEADLESS.md), [`../README.md`](../README.md),
  [`../REBUILD.md`](../REBUILD.md), [`../SETUP.txt`](../SETUP.txt), and
  [`../docker/DOCKER.md`](../docker/DOCKER.md).
