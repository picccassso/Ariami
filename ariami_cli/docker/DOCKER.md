# Ariami CLI Docker

This image packages the Ariami CLI as a headless music server. The container
runs the HTTP server in the foreground with `--server-mode`, which is the right
shape for Docker process supervision.

## Build

Run this from the repository root. Quote the path if your checkout lives in a
directory with spaces:

```bash
cd "/path/to/Ariami Test Desktop"
docker build -f ariami_cli/docker/Dockerfile -t ariami-cli .
```

## Run on a Linux server (recommended: zero config)

On Linux (Raspberry Pi, NAS, homelab), use host networking. Ariami then
detects the machine's real LAN and Tailscale addresses automatically —
setup URLs and the mobile QR code work with no environment variables:

```bash
docker run -d \
  --name ariami \
  --network host \
  -v ariami-data:/data \
  -v "/path/to/Music:/music:ro" \
  ariami-cli
```

With `--network host` the server listens on port 8080 directly; no `-p`
mapping is needed or used. Host networking also lets the server answer
LAN auto-discovery (UDP beacon on 45420 + mDNS), so clients like the TV
app find it instantly without scanning.

## Run on Docker Desktop (Mac/Windows)

Docker Desktop containers cannot see the machine's real network (host
networking only exposes the internal VM), so map the port and tell Ariami
which addresses to advertise:

```bash
docker run -d \
  --name ariami \
  -p 8080:8080 \
  -e ARIAMI_ADVERTISED_LAN_HOST=192.168.1.50 \
  -e ARIAMI_ADVERTISED_TAILSCALE_HOST=100.x.y.z \
  -v ariami-data:/data \
  -v "/path/to/Music:/music:ro" \
  ariami-cli
```

Set `ARIAMI_ADVERTISED_LAN_HOST` to the host machine's LAN IP for same-network
devices. Set `ARIAMI_ADVERTISED_TAILSCALE_HOST` to the host machine's Tailscale
IP for remote devices that have Tailscale enabled. The setup URLs, server info,
and mobile QR code will advertise both reachable hosts instead of the
container's internal Docker address, and the mobile app automatically picks a
reachable one.

`ARIAMI_ADVERTISED_HOST` remains available as a single-address shorthand for
older setups. It advertises one host only, so prefer the explicit LAN and
Tailscale variables when you want both connection paths.

Note on auto-discovery: broadcast and multicast traffic does not cross
Docker's bridge network, so with port mapping the server cannot answer
UDP/mDNS discovery probes. Clients still find it automatically — the TV
app falls back to scanning ports 8080–8099 on its own subnet — as long as
the mapped port stays within that range. On Linux, prefer host networking
for instant discovery.

## First-run setup

Open `http://<host>:8080` and complete the first-run wizard. Choose `/music` as
the music folder.

When the wizard reaches the final setup transition, Ariami completes setup in
place. The server keeps running in the foreground under Docker supervision
instead of daemonizing inside the container.

## Data

Ariami stores its container state in `/data` through `ARIAMI_DATA_DIR`. Keep
that volume when upgrading or recreating the container. Music files are read
from `/music`; the example above mounts them read-only.

## Security notes

The container runs as the unprivileged `ariami` user (uid 10001), not root.
Only `/data` is writable; the application files and `/music` are read-only
for it. Two consequences for mounts:

- A named `/data` volume (as in the examples) inherits the right ownership
  automatically. If you bind-mount a host directory to `/data` instead, make
  it writable by uid 10001, e.g. `chown -R 10001 /path/to/data`.
- The music bind mount must be readable by uid 10001 (world-readable files
  are fine, which is the common case). Keep it read-only (`:ro`) as shown.

Keep Ariami on your LAN or VPN, and do not port-forward it to the public
internet.

For a deliberately public review/demo server, put a maintained HTTPS reverse
proxy in front of the container and publish port 8080 on loopback only (for
example, `127.0.0.1:8080:8080`). Configure both:

```bash
-e ARIAMI_PUBLIC_ORIGIN=https://review.ariami.xyz \
-e ARIAMI_TRUST_PROXY_HEADERS=1
```

The public origin must be HTTPS and contain no path, query, fragment, or
credentials. Do not expose the container's HTTP port through the cloud
firewall; only the reverse proxy's HTTPS port should be internet-reachable. The
proxy must overwrite, not merely append to, any client-supplied
`X-Forwarded-For` header before proxying to Ariami.

## Commands

Because the image entrypoint is the Ariami binary, one-off commands can be run
by passing the subcommand after the image name:

```bash
docker run --rm -v ariami-data:/data ariami-cli --version
docker run --rm -v ariami-data:/data ariami-cli status
```

For a running container:

```bash
docker exec ariami /opt/ariami/bin/ariami_cli status
docker exec ariami /opt/ariami/bin/ariami_cli --version
docker exec ariami /opt/ariami/bin/ariami_cli stop
docker stop ariami
```

Use `docker stop` for normal container shutdown. The `ariami_cli stop` command
is available too, but it is mainly intended for daemonized non-container
installs.

## Healthcheck

The image includes a Docker healthcheck that calls:

```bash
http://127.0.0.1:8080/api/ping
```

Inspect it with:

```bash
docker ps
docker inspect --format '{{.State.Health.Status}}' ariami
```

## Compose

From `ariami_cli/docker`, edit the `./music:/music:ro` bind mount in
`docker-compose.yml` so it points at your real music folder, then run:

```bash
cd "ariami_cli/docker"
docker compose up -d --build
docker compose logs -f
```
