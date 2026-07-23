# Installation & Deployment Guide

This is a decision-tree style guide to picking and starting the right
install path. It intentionally doesn't duplicate the step-by-step guides
this package already ships — it tells you which one to open and adds the
context needed to choose correctly. For full detail, follow the links.

## Which guide do I actually want?

| Your situation | Use |
| --- | --- |
| Raspberry Pi, NAS, Proxmox LXC, or any bare-metal/VM Linux/macOS/Windows box, run directly (no container) | [`../HEADLESS.md`](../HEADLESS.md) — the primary SSH/headless guide. |
| Prefer a very short, plain-text install sheet (e.g. to keep alongside a release zip) | [`../SETUP.txt`](../SETUP.txt) — condensed version of the same install/usage steps. |
| Docker or Docker Compose, any host | [`../docker/DOCKER.md`](../docker/DOCKER.md). |
| Building from source, rebuilding the web UI after a change, or cross-compiling a Raspberry Pi release from a Mac | [`../REBUILD.md`](../REBUILD.md). |
| Command/flag/env-var specifics while following any of the above | [`CLI_REFERENCE.md`](CLI_REFERENCE.md) and [`CONFIGURATION.md`](CONFIGURATION.md). |
| Something went wrong | [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md). |

## Getting a build

Verified from `.github/workflows/cli-artifacts.yml` and
`.github/workflows/docker-image.yml`:

- **Prebuilt release zips** — Linux x64, Linux arm64 (Raspberry Pi and other
  ARM64 Linux), macOS arm64, and Windows x64 — are published from the
  [GitHub releases page](https://github.com/picccassso/Ariami/releases) for
  tagged versions.
- **Docker image** — `ghcr.io/picccassso/ariami-cli`, built for both
  `linux/amd64` and `linux/arm64` and published as a single multi-platform
  manifest by the `Docker Image` workflow.
- **Build it yourself** — see [`REBUILD.md`](../REBUILD.md) for a plain
  `dart build cli` executable, or a Raspberry Pi arm64 cross-build from an
  Apple Silicon Mac via Docker (`build-pi-release-mac.sh`).

## The install flow, in one paragraph

Whichever platform you pick, the flow is the same: get the `ariami_cli`
executable (or container) running once, open the URL it prints in a
browser, walk through Tailscale (optional) → choose your music folder →
scan → create the owner account, then either let it daemonize into the
background (native installs) or leave it running under your process
supervisor of choice (systemd unit, Docker). See `../HEADLESS.md`'s "First
Run" section for the exact screen-by-screen sequence, and
[`CLI_REFERENCE.md`](CLI_REFERENCE.md#start) for exactly what `start` does
on a first run vs. a later run.

## Choosing how Ariami stays running

| Method | When to use | Where it's documented |
| --- | --- | --- |
| Built-in `autostart` | Simplest option; no sudo; works on Linux, macOS, and Windows via each OS's native no-privilege mechanism. | [`CLI_REFERENCE.md`](CLI_REFERENCE.md#autostart-enabledisablestatus), `../HEADLESS.md` |
| systemd unit (`--server-mode`) | You already manage other services with systemd, or want systemd's restart/logging integration (`journalctl`). Don't combine with built-in `autostart` on the same install. | `../HEADLESS.md` (example unit included) |
| Docker / Docker Compose | You want image-based deployment, `docker restart unless-stopped`, or you're already running other containers on the host. | `../docker/DOCKER.md` |

## Networking decisions up front

Decide this **before** first run, because it changes what you'll see in the
setup URLs:

- **Same machine only:** `--host 127.0.0.1`.
- **LAN + Tailscale (typical homelab):** default `--host 0.0.0.0`, no
  extra environment variables needed on a native install — Ariami
  autodetects LAN/Tailscale addresses.
- **Docker on Linux:** `--network host` for zero-config detection (and
  working LAN auto-discovery); see `../docker/DOCKER.md`.
- **Docker Desktop (macOS/Windows) or any bridge-networked container:**
  publish the port and set `ARIAMI_ADVERTISED_LAN_HOST` /
  `ARIAMI_ADVERTISED_TAILSCALE_HOST` explicitly — see
  [`CONFIGURATION.md`](CONFIGURATION.md#networking-and-deployment).
- **Deliberately public, behind your own HTTPS reverse proxy:** set
  `ARIAMI_PUBLIC_ORIGIN` and (only if the proxy is trusted and overwrites
  `X-Forwarded-For`) `ARIAMI_TRUST_PROXY_HEADERS=1`. Never publish the raw
  HTTP port directly to the internet — see the Security sections of
  `../HEADLESS.md` / `../docker/DOCKER.md`.

If you get any of this wrong, [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#clients-cant-connect)
walks through exactly how the symptoms look and how to fix each case.

## Updating an existing install

The short version (full version in `../HEADLESS.md`'s "Update Procedure"):

```bash
./ariami_cli stop
# back up the data directory shown by `./ariami_cli status`
# replace the extracted release files with the new release (keep the data directory)
./ariami_cli start
./ariami_cli status   # confirm "Reachable: yes"
```

For Docker, update the image/tag and recreate the container; the named
`/data` volume is what carries your install across the upgrade — see
`../docker/DOCKER.md`.
