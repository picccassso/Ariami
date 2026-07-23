# Troubleshooting

Every symptom below is tied to real code: an actual error string, exit code,
log line, or documented fallback behavior in this repository. Paths are
relative to `ariami_cli/` unless said otherwise (`ariami_core/...` points
into the sibling package). If you hit something not covered here, run the
failing command with `--verbose` first — it's the fastest way to get a real
stack trace instead of a guess.

## Contents

- [First, get more detail](#first-get-more-detail)
- [Startup failures (general)](#startup-failures-general)
- [Port already in use / can't bind](#port-already-in-use--cant-bind)
- [Music library problems](#music-library-problems)
- [Clients can't connect](#clients-cant-connect)
- [Login, pairing, and rate-limiting problems](#login-pairing-and-rate-limiting-problems)
- [Database & config corruption](#database--config-corruption)
- [Docker-specific pitfalls](#docker-specific-pitfalls)
- [Raspberry Pi / arm64 specifics](#raspberry-pi--arm64-specifics)
- [Memory & performance on low-end hardware](#memory--performance-on-low-end-hardware)
- [Transcoding & audio format problems](#transcoding--audio-format-problems)
- [Logs and verbosity](#logs-and-verbosity)
- [Reset & recovery gotchas](#reset--recovery-gotchas)
- [Windows-specific quirks](#windows-specific-quirks)

---

## First, get more detail

- `ariami_cli status` — a live health check: process state, whether the
  dashboard actually answers on its port, setup/auth/music-folder state, and
  the active data directory (`lib/services/server_status_service.dart`).
  Always run this first.
- `ariami_cli stop` then `ariami_cli start --verbose` — re-runs setup/start
  in the foreground with stack traces on fatal errors
  (`lib/server_runner.dart`, `bin/ariami_cli.dart`). This is the single most
  useful diagnostic step for any startup problem, because the background
  daemon's own output usually isn't captured anywhere (see
  [Logs and verbosity](#logs-and-verbosity)).
- Confirm which data directory is actually in play: `ARIAMI_DATA_DIR` if
  set, otherwise `~/.ariami_cli` (`lib/services/cli_state_service.dart`).
  `status` prints the resolved path under `Data:`.

---

## Startup failures (general)

**Symptom:** the process prints something like:

```
ERROR: Ariami server failed to start
<cause line>
```

and exits `1`.

**Likely cause:** this is `ServerRunner`'s catch-all
(`lib/server_runner.dart`, `_formatStartupError`). The `<cause line>` tells
you which of these it is:

| Cause line | Meaning | Fix |
| --- | --- | --- |
| `Port <n> is already in use. Choose another port with --port or free the port.` | You passed an explicit `--port` that's occupied. | See [Port already in use](#port-already-in-use--cant-bind). |
| `Could not bind ports 8080-8099. Free a port or run: ariami_cli start --port 9000` | No port in the fallback range was free. | Same section. |
| `Web UI assets were not found. See the guidance above.` | The Flutter web build (`build/web/`) isn't next to the executable/working directory. | See the detailed "Checked these locations" list the CLI prints just above this line, and `lib/services/web_assets_resolver.dart`. In dev, run `flutter build web -t lib/web/main.dart` from `ariami_cli/`. In a release zip, run the CLI from inside the extracted directory (don't move just the binary). |
| `Permission denied while accessing Ariami data. Check permissions on <dir> and the ARIAMI_DATA_DIR environment variable.` | The data directory (or a file in it) isn't readable/writable by the user running Ariami. | Fix ownership/permissions on that directory, or point `ARIAMI_DATA_DIR` at a directory the current user actually owns. |
| `Cause: Invalid startup configuration: enableV2Api=true requires catalog repository availability. Failed to initialize catalog at <path>` | The catalog database failed to open (commonly: corruption, or a permissions problem on `catalog.db`). | See [Database & config corruption](#database--config-corruption). |
| `Cause: Invalid feature flag configuration: enableDownloadJobs=true requires enableV2Api=true.` | You set `ARIAMI_ENABLE_V2_API=false` (or similar) without also disabling `ARIAMI_ENABLE_DOWNLOAD_JOBS`. | Unset both overrides, or set `ARIAMI_ENABLE_DOWNLOAD_JOBS=false` too. See [`CONFIGURATION.md`](CONFIGURATION.md#feature-flags-advancedinternal). |
| Anything else (`Cause: <error>`) | An unclassified exception — the raw Dart error/exception text. | Re-run with `--verbose` for a stack trace. |

**How to confirm:** re-run the same command with `--verbose` appended (after
`ariami_cli stop` if it's currently backgrounded) — you'll get the full
stack trace under the cause line.

---

## Port already in use / can't bind

**Symptom:** startup fails with a port-binding message, or `status` shows
`Reachable: NO` while the process is running.

**How the fallback actually works** (`ariami_core`'s
`ServerPortPolicy.buildCandidates`, used from `lib/server_runner.dart`):

- If you did **not** pass an explicit `--port`, Ariami tries, in order: the
  previously saved port (if any), then your requested/default port, then
  every port from `8080` through `8099` in sequence, skipping duplicates.
- If you **did** pass an explicit `--port` (`portExplicitlyRequested`),
  fallback is disabled entirely — that exact port is the only candidate.
- `--server-mode` (the background daemon / systemd / Docker path) **always**
  disables fallback, regardless of whether `--port` was explicit, and
  additionally retries the bind with exponential backoff (100ms, 200ms,
  400ms, ... up to 10 attempts) printing
  `Port <n> in use, retrying in <ms>ms (attempt <k>/10)...` — this exists to
  ride out the brief handoff window when a foreground setup process is
  still releasing the port on its way to becoming a background daemon
  (`bin/ariami_cli.dart`, `_executeServerMode`).
- If fallback used a different port than requested, you'll see:
  `Port <attempted> was in use, so Ariami started on <actual>.` followed by
  a reminder to rescan the QR code if you'd already paired a device on the
  old port.

**How to confirm:** `ariami_cli status` prints the actual bound port under
`Local`/`Dashboard`/`Tailscale`. On Linux/macOS, `lsof -i :8080` (or your
port) shows what's holding it.

**Fix:**

- Free the port, or pin a specific free one: `ariami_cli start --port 9000`.
- If running under `--server-mode` (systemd/Docker) and it keeps losing the
  race after 10 retries (~51 seconds of backoff), something else is
  genuinely holding that port — it will exit `1` at that point instead of
  retrying forever.

---

## Music library problems

### Music folder not found / permission denied (setup or `configure`)

**Symptom:** `ariami_cli configure --music-folder <path>` prints
`Error: <message>` with one of:

| `message` | Meaning |
| --- | --- |
| `Path is required` | Empty path. |
| `Path does not exist on the server` | Nothing exists at that path *on the machine running the server* — a very common trap when the path is copy-pasted from a client device instead of typed for the server's own filesystem. |
| `Permission denied: cannot read this folder` | The path exists but the OS user running Ariami can't list its contents. |
| `Path is not a directory` | The path points at a file, not a folder. |

(`ariami_core/lib/services/setup/music_folder_path_helper.dart`.)

**How to confirm:** run `ls -la <path>` (or the platform equivalent) as the
same OS user that runs Ariami — not as yourself, if you run Ariami as a
dedicated service account. In Docker, remember paths inside the container
are `/music`, not whatever the bind-mount source path was on the host.

**Fix:** correct the path, fix ownership/permissions on the host directory,
or (Docker) fix the bind-mount source/permissions — see
[Docker-specific pitfalls](#docker-specific-pitfalls).

### Music folder disappeared after it was already configured

**Symptom:** on `start`, you see:

```
Warning: configured music folder <path> does not exist. Fix the path in the dashboard or reattach the drive.
```

and the initial library scan is **skipped** for that run
(`lib/server_runner.dart`, `_warnIfMissingMusicFolder`). `status` also shows
`Music: <path> (folder missing!)`.

**Likely cause:** an external drive/NAS mount isn't mounted yet at boot, a
Docker bind mount source moved, or the path was renamed.

**Fix:** remount/reattach the drive (or fix the mount at boot before Ariami
starts) and restart Ariami, or point the dashboard/`configure` at the new
path.

### Scan finds zero tracks (or far fewer than expected)

The scanner (`ariami_core/lib/services/library/file_scanner.dart`) has a few
behaviors that commonly explain a surprising zero (or low) track count —
check each of these before assuming something is broken:

1. **Unsupported file extension.** Only these extensions are ever scanned,
   checked case-insensitively:
   `.mp3 .m4a .mp4 .flac .wav .aiff .ogg .opus .wma .aac .alac`. A library of,
   say, `.dsf` or `.ape` files will scan as zero tracks — this is expected,
   not a bug.
2. **Hidden/dot directories are skipped entirely**, and so are files inside
   them — any path component starting with `.` (other than the bare `.`)
   excludes that directory (and everything under it) and every file in it.
   If your whole music folder lives inside a dot-prefixed directory (or a
   sync tool nested it under one, e.g. `.SyncThing`), nothing will be found.
3. **Symlinks are not followed** (`followLinks: false`). A music folder that
   is itself a symlink, or that contains symlinked album folders pointing
   elsewhere, will not have those linked contents scanned.
4. **Permission-denied subdirectories don't fail the whole scan** — they're
   recorded as scan errors and skipped, so a library that's "mostly there
   but missing an album" often means that album's folder isn't readable by
   the Ariami process.

**How to confirm:** check file extensions and directory names by hand
(`find <music folder> -type f | head`), and check ownership/permissions on
any subdirectory that seems to be missing specifically
(`find <music folder> -type d ! -readable`).

**Fix:** convert/rename to a supported extension, move music out of
dot-prefixed directories, replace symlinked folders with real directories or
bind-mount the real target directly, or fix permissions on the affected
subdirectory, then rescan from the dashboard (or restart Ariami).

---

## Clients can't connect

Work through these in order — they cover the large majority of "server runs
fine locally but nothing else can reach it" reports.

### 1. Bind address is localhost-only

If `bind_host` in `config.json` (or an explicit `--host`) is `127.0.0.1` or
`localhost`, the startup banner says so outright:

```
Note:      bound to localhost only — other devices cannot connect.
```

(`lib/services/startup_summary.dart`.) This is intentional when you only
want local access. **Fix:** `ariami_cli start --host 0.0.0.0` (the default)
if you want LAN/Tailscale devices to connect at all.

### 2. Firewall blocking the port

The OS firewall (Windows Defender Firewall, `ufw`/`firewalld` on Linux, etc.)
may be blocking inbound connections to the bound port. **How to confirm:**
from another device, `curl -v http://<server-ip>:<port>/api/ping` — a
connection that hangs/times out (rather than refuses or answers) usually
means a firewall is dropping the packets. **Fix:** allow the port (default
`8080`, or whatever `status` reports) for private/LAN networks.

### 3. Docker networking mode mismatch

This is the single most common Docker connectivity issue, and it's
documented in detail in [`../docker/DOCKER.md`](../docker/DOCKER.md):

- **Linux hosts:** use `--network host` (or `network_mode: host` in
  Compose). Ariami then detects your real LAN/Tailscale IPs directly and
  answers LAN discovery (UDP beacon on port `45420`, mDNS on `5353`) so
  other apps find it without any configuration.
- **Docker Desktop (macOS/Windows):** host networking is not available the
  same way (the container's "host" is really the Docker Desktop VM, not
  your Mac/PC), so you **must** publish the port (`-p 8080:8080`) and set
  `ARIAMI_ADVERTISED_LAN_HOST`/`ARIAMI_ADVERTISED_TAILSCALE_HOST` yourself,
  or clients will be handed the container's internal address in the QR
  code/setup URLs and fail to connect.
- With port mapping (bridge networking) instead of host networking,
  broadcast/multicast traffic (the UDP beacon + mDNS) **cannot cross the
  bridge**, so passive auto-discovery won't work even though the mapped TCP
  port works fine for a manually-entered address or a port-range scan from
  the client's own subnet.

**How to confirm:** `docker inspect --format '{{.NetworkSettings.IPAddress}}' ariami`
vs. the address a client is actually trying — if they don't match a real
host or advertised address, that's the mismatch.

### 4. Advertised address is wrong or missing

If `status`/the setup banner shows no LAN or Tailscale URL at all, or shows
one that isn't reachable from your client, check for a container/NAT
mismatch: set `ARIAMI_ADVERTISED_LAN_HOST` and/or
`ARIAMI_ADVERTISED_TAILSCALE_HOST` to the host machine's real, reachable
addresses (`ARIAMI_ADVERTISED_HOST` is the older single-address shorthand —
prefer the two explicit variables when you want both paths to work). These
only take effect when set; otherwise Ariami auto-detects via network
interface scanning and (if installed) the `tailscale` CLI
(`lib/services/cli_tailscale_service.dart`).

### 5. Reverse proxy / public deployment specifics

If you deliberately expose Ariami publicly through an HTTPS reverse proxy,
`ARIAMI_PUBLIC_ORIGIN` must be an HTTPS-only origin with no path, query,
fragment, or credentials — an invalid value **fails startup**, it doesn't
silently ignore the value. See
[`CONFIGURATION.md`](CONFIGURATION.md#networking-and-deployment) and the
Security sections of `../HEADLESS.md` / `../docker/DOCKER.md` for the full
threat-model reasoning (don't expose the raw HTTP port publicly; only the
proxy's HTTPS port).

---

## Login, pairing, and rate-limiting problems

### "Too many failed auth attempts"

**Symptom:** login or registration returns HTTP 429 with
`Too many failed auth attempts. Try again in <n> minute(s).`

**Cause:** the server rate-limits `/api/auth/login` and `/api/auth/register`
per client IP: **5** failed attempts locks that IP out for **15 minutes**
(`ariami_core`'s `AuthService.maxLoginAttempts` /
`rateLimitCooldown`, enforced in
`http_server_parts/middleware_and_metrics_part.dart`). A `403` from a bad or
expired invite/registration code also counts as a failure, specifically so
invite codes can't be brute-forced without ever tripping the limiter.

**Gotcha behind a reverse proxy:** unless `ARIAMI_TRUST_PROXY_HEADERS=1` is
set, Ariami rate-limits by the **proxy's** IP address (since it ignores
`X-Forwarded-For` from an untrusted source by design) — meaning every client
behind that proxy shares one rate-limit bucket, and one person mistyping
their password five times locks out the whole household. Only set
`ARIAMI_TRUST_PROXY_HEADERS=1` when a reverse proxy you control fronts
Ariami directly and overwrites (not merely appends to) any client-supplied
`X-Forwarded-For` header before forwarding.

**Fix:** wait out the 15-minute window, or (if legitimately behind your own
trusted proxy) set `ARIAMI_TRUST_PROXY_HEADERS=1` so each real client gets
its own bucket.

### No owner account / can't finish setup remotely

Until an owner account exists, the server prints a one-time setup code on
its **own console**:

```
No owner account exists yet.
First-time setup code: XXXX-XXXX
Enter it in the dashboard when creating the owner account from another device (not needed on this machine).
```

(`lib/server_runner.dart`, `_printOwnerBootstrapCodeIfNeeded`.) This code is
required only when creating the *first* account from a browser that is
**not** on the server machine itself (e.g. the CLI web dashboard opened from
your phone on a headless install) — it's what proves you have local console
access. A browser at `http://localhost:<port>` on the server itself does not
need it. **Fix:** read the code from wherever you started the server
(terminal, `journalctl` under systemd, `docker logs` under Docker) and type
it into the dashboard.

### QR code / invite link stopped working

Registration tokens embedded in the dashboard QR code expire **10 minutes**
after being issued (`_registrationTokenTtl` in `ariami_core`'s
`http_server.dart`). **Fix:** refresh/re-open the dashboard's pairing screen
to get a new QR code rather than reusing an old screenshot.

### Rescan the QR code after a port change

If Ariami's fallback logic moved it to a different port than the one a
client last paired with, you'll see
`Rescan the QR code if you previously connected on port <old>.` printed at
startup — that's not optional, the previously generated QR/manual address
literally encodes the old port.

---

## Database & config corruption

### `config.json` is corrupted or unreadable

**Behavior, not a bug:** `CliStateService` swallows any JSON parse error
when reading `config.json` and treats it as an **empty config**
(`lib/services/cli_state_service.dart`, `_readConfig`) — it does not crash,
and it does not warn you. Practically, this means a corrupted `config.json`
silently resets to defaults: setup will look incomplete again, the saved
port/bind host revert to defaults, and the music folder path is forgotten
(even though your library/accounts/catalog are untouched).

**How to confirm:** `cat` the file and check it's valid JSON
(`python3 -m json.tool config.json` or similar).

**Fix:** if it's actually corrupted, there's nothing to repair — either
recreate it by re-running setup (`ariami_cli configure --music-folder ...`
plus a fresh `start`), or restore a backup copy taken before the corruption.

### `users.json` is corrupted or unreadable

**Behavior, not a bug:** the same pattern applies to accounts — a corrupted
or unreadable `users.json` is logged (`UserStore: Error loading users.json:
<error>`) and the in-memory account list starts **empty**, which will look
exactly like "no owner account yet" (the first-time setup code reappears)
even though your library is intact. This is a real risk if you ever hand-edit
or restore a partial copy of that file.

**Fix:** restore `users.json` from backup before doing anything else — the
data isn't actually deleted, it's just unreadable — then restart Ariami.
Only proceed to `ariami_cli reset --factory` if you deliberately want to
throw accounts away and start over.

### Catalog database (`catalog.db`) failed to initialize / corrupted

**Symptom:** the startup error `Invalid startup configuration: enableV2Api=true
requires catalog repository availability. Failed to initialize catalog at
<path>` (see [Startup failures](#startup-failures-general)), or a log line
`[LibraryManager] WARNING: Failed to initialize catalog DB: <error>`
followed by startup actually failing.

**Cause:** SQLite failed to open `catalog.db` — usually corruption from an
unclean shutdown (power loss on a Pi, `kill -9`, a crashed container) or a
permissions problem on the file/directory. The database runs in WAL mode
with a 5-second busy timeout (`ariami_core/lib/services/catalog/
catalog_database.dart`); there is no automatic corruption repair.

**How to confirm:** stop the server, then try opening the database directly:
`sqlite3 ~/.ariami_cli/catalog.db "PRAGMA integrity_check;"` (adjust the
path for your `ARIAMI_DATA_DIR`). Anything other than `ok` confirms
corruption.

**Fix:** stop Ariami, delete `catalog.db` **and its `-wal`, `-shm`, and
`-journal` sidecar files** (all four are removed together by
`ariami_cli reset --factory`, but you can also do it by hand if you want to
keep accounts — `reset --factory` also clears `users.json`/`sessions.json`),
then start Ariami again; it rebuilds the catalog from a fresh library scan.
If you only want to rebuild the catalog and keep accounts, stop the server
first and remove just those four files manually (there's no CLI flag scoped
that narrowly).

---

## Docker-specific pitfalls

All verified against `docker/Dockerfile` and `docker/DOCKER.md`.

- **Runs as an unprivileged, non-root user (uid `10001`), not root.** Only
  `/data` is writable to it; `/opt/ariami` (the app itself) and `/music` are
  read-only for that user.
- **Named volume vs. bind mount for `/data`:** a named Docker volume (as in
  the documented examples) gets the right ownership automatically. A
  **bind-mounted host directory** for `/data` must be made writable by uid
  `10001` yourself: `chown -R 10001 /path/to/data`. Skipping this shows up
  as the generic `Permission denied while accessing Ariami data...` startup
  error above.
- **Music bind mount must be world-readable (or readable by uid 10001).**
  Keep it `:ro` as documented; if the host directory's permissions don't
  allow uid 10001 to read it, you'll get the same "music folder
  missing/permission denied" symptoms as a native install (see
  [Music library problems](#music-library-problems)) — `ls -la` the host
  path and check the "other" permission bits, since the container user has
  no matching host account.
- **Auto-discovery silently doesn't work with port-mapped (bridge)
  networking** — this is expected, not broken (see
  [Clients can't connect](#clients-cant-connect) point 3). Prefer
  `--network host` on Linux; on Docker Desktop, set the advertised-host
  variables and rely on manual entry / the client's own port-range scan.
- **`docker run ... ariami-cli status` "one-off" commands** run in a fresh
  container and won't see a server started in a *different* running
  container — for status/stop against an already-running container, use
  `docker exec ariami /opt/ariami/bin/ariami_cli status` (or `stop`)
  instead, or just `docker stop`/`docker logs`.
- **Healthcheck** (`HEALTHCHECK` in the Dockerfile) polls
  `http://127.0.0.1:8080/api/ping` every 30s. If `docker ps` shows the
  container as `unhealthy`, that's a strong signal the HTTP server itself
  isn't answering — check `docker logs ariami` for the actual startup error
  underneath it.
- **The container's `ARIAMI_CONTAINER=1` and `ARIAMI_DATA_DIR=/data` are
  baked in** by the image (`docker/Dockerfile`) — you don't need to (and
  shouldn't) override `ARIAMI_DATA_DIR` inside the container; change the
  volume mount instead.

---

## Raspberry Pi / arm64 specifics

- **glibc requirement:** Linux/Raspberry Pi builds need glibc **2.35+**
  (Ubuntu 22.04, Debian 12, Raspberry Pi OS **Bookworm** or newer). Older
  Raspberry Pi OS (Bullseye and earlier) is not supported by the released
  binary. **Symptom** of trying anyway: the dynamic linker refusing to run
  the executable (`version 'GLIBC_2.3x' not found` or similar) — that's an
  OS-image problem, not an Ariami bug; upgrade the OS image.
- **Any unrecognized ARM64 Linux box is treated as a Raspberry Pi.**
  `ServerRuntimePolicy.isRaspberryPi()` positively identifies real Pi models
  via `/proc/device-tree/model`/`/proc/cpuinfo`, but conservatively treats
  **any other** Linux ARM host as a Pi too (see
  [`CONFIGURATION.md`](CONFIGURATION.md#runtime-tuning-raspberry-pi--storage-detection)).
  If you're running the arm64 build on, say, an ARM64 NAS or an ARM64 cloud
  VM and see lower-than-expected download concurrency, this is why — there
  is no environment variable to force "not a Pi"; only cache sizing
  (`ARIAMI_STORAGE_PROFILE`) can be overridden independently.
- **Storage type only matters on Linux/Pi**, and is derived from
  `/proc/mounts` (`mmcblk*` ⇒ microSD, `nvme*`/`/dev/sd*` ⇒ fast external).
  If your music/data lives on a USB SSD but Ariami still applies microSD-tier
  (small) cache limits, check that the SSD is actually mounted at a path
  `/proc/mounts` reports with an `nvme`/`sd`-prefixed device — some
  USB-to-SATA/NVMe bridges or LUKS/mapper layers can obscure the underlying
  device name, in which case set `ARIAMI_STORAGE_PROFILE=externalfast`
  explicitly.
- **Bundled native libraries:** Pi release zips (built by
  `build-pi-release-mac.sh`, or from `.github/workflows/cli-artifacts.yml`)
  include `libsonic_transcoder.so` and `libsqlite3.so` next to the
  executable. Always run the CLI **from inside the extracted release
  directory** (via the included `ariami_cli` launcher script) so these are
  found — running just the inner `bin/ariami_cli` binary from somewhere else
  will not find them.
- See `docs/pi-3-performance-findings.md` in the repository root for real
  measured throughput/latency numbers on a Pi 3, including cold vs. warmed
  transcode timings.

---

## Memory & performance on low-end hardware

This is governed entirely by the tables in
[`CONFIGURATION.md`](CONFIGURATION.md#runtime-tuning-raspberry-pi--storage-detection).
In short, on a microSD-backed Raspberry Pi, Ariami deliberately uses a much
smaller transcode cache (384 MB vs. 2048–4096 MB elsewhere), a smaller
artwork cache (96 MB vs. 256 MB), a slower cache-index persist interval (5
minutes vs. 30 seconds), and throttles artwork "touch on cache hit" bookkeeping
(30-minute throttle) — all to reduce microSD write wear and I/O contention.
Concurrency limits are similarly capped (4 concurrent downloads, 4 per
user) on any Pi, tightening further only loosening on fast external
storage.

**Symptom:** downloads/transcodes feel slow or heavily queued on a Pi.
**How to confirm:** the startup log line `Storage profile: <profile>
(music=<type>, state=<type>)` tells you exactly what was detected — a
`microSd` profile on hardware that actually has a fast SSD attached is the
one case worth fixing (see the Raspberry Pi section above); otherwise, this
is expected, intentional behavior for the hardware class, not a bug. The
`docs/pi-3-performance-findings.md` findings in the repository root show
that cold medium/low-quality transcodes are the genuine bottleneck on a Pi
3/4, while original-quality streaming and downloads stay smooth even
alongside other activity.

---

## Transcoding & audio format problems

### Low/medium quality silently plays at original quality

**Symptom:** the startup log shows
`⚠ Sonic not available - audio transcoding disabled (will serve original files)`
instead of `✓ Sonic available - audio transcoding enabled`
(`lib/services/server_media_services_configurator.dart`).

**Cause:** the bundled native transcoding library isn't where Ariami expects
it — `lib/libsonic_transcoder.so` (Linux), `.dylib` (macOS), or
`sonic_transcoder.dll` (Windows), next to the executable, per platform.

**How to confirm:** check that file exists in the `lib/` folder of your
*extracted release directory*, and that you started Ariami via the launcher
script from that directory (not by copying just the binary elsewhere).

**Fix:** re-extract the release zip intact, or (Docker) rebuild the image —
the Dockerfile compiles and copies `libsonic_transcoder.so` into
`/opt/ariami/lib/` itself, so this shouldn't occur in the published image
unless a custom build skipped that stage.

### Artwork thumbnails aren't generated

**Symptom:** the startup log shows
`⚠ FFmpeg not found - artwork thumbnails disabled (original artwork only)`.

**Cause:** FFmpeg isn't installed/on `PATH` for the user running Ariami. The
official Docker image installs `ffmpeg` via `apt-get`
(`docker/Dockerfile`); native installs need it available separately.

**Fix:** install FFmpeg for your platform (or accept original, unresized
artwork — playback and streaming are unaffected either way).

### A particular file "isn't in the library"

See [Scan finds zero tracks](#scan-finds-zero-tracks-or-far-fewer-than-expected)
above — the supported-extension list, hidden-directory skipping, and
symlink-following behavior apply per-file just as much as to a whole empty
library.

---

## Logs and verbosity

- **Foreground (setup mode, or `stop`/`start --verbose` re-runs):** output
  goes straight to the terminal you're in. `--verbose` additionally prints
  stack traces on fatal errors.
- **Background daemon (`ariami_cli start` after setup is complete):** the
  child process is spawned detached
  (`ProcessStartMode.detached`/`setsid` on Linux,
  `lib/services/daemon_service.dart`) with **no connection to its
  stdin/stdout/stderr at all**. In practice this means there generally is no
  captured log file for a plain background `start` — `server.log`
  (referenced by `reset` for cleanup) is not written to by this code path.
  If you need to see why a background start is misbehaving, stop it and run
  `ariami_cli start --verbose` in the foreground instead.
- **Autostart (`ariami_cli autostart enable`):** this is the one path that
  *does* capture output, because the OS-level mechanism itself redirects it:
  the Linux crontab entry appends stdout/stderr to `autostart.log` in the
  data directory, and the macOS LaunchAgent plist sets
  `StandardOutPath`/`StandardErrorPath` to the same file
  (`lib/services/autostart_service.dart`). Check `autostart.log` after a
  reboot if autostart itself seems to have failed.
  Windows autostart (Registry Run key) does not redirect output anywhere.
- **systemd (`--server-mode` under a unit file):** systemd captures stdout/
  stderr itself — use `journalctl -u <unit>` (see the example unit in
  `../HEADLESS.md`).
- **Docker:** the container's main process runs `--server-mode` in the
  foreground under Docker's own process supervision, so `docker logs
  ariami` has everything.
- Raise verbosity with `--verbose` on `start` (foreground/first-run) or when
  manually invoking `--server-mode`. There is no separate log-level
  environment variable in this codebase — `--verbose` is the only knob.

---

## Reset & recovery gotchas

- `reset` (either scope) **stops the server first** if it's running, and
  aborts with `ERROR: Could not stop the running server. Run "ariami_cli
  stop" and try again.` (exit `1`) if that fails — it will not touch files
  while the database is still open.
- Both scopes require typing `RESET` (exact, case-sensitive) unless `-y`/
  `--yes` is passed — there is no way to accidentally reset by mistyping a
  flag.
- The configured music folder is **never** a deletion target, and the reset
  engine actively refuses to delete anything that equals, contains, or is
  nested inside it — even a misconfigured data directory can't take your
  music with it. If a path is skipped for this reason, you'll see
  `• Skipped <path> (protected music library path).` in the summary.
- `reset --factory` also disables start-on-boot (equivalent to
  `autostart disable`) since there's no point restarting into an unconfigured
  server automatically.
- If a particular path can't be removed (permissions, file in use), the
  summary lists it under `! Could not remove <path>: <error>` rather than
  failing the whole operation silently — read that list; it tells you
  exactly what's left over.

---

## Windows-specific quirks

- **`SIGTERM` cannot be watched on Windows** — attempting to would throw
  `SignalException` (OS error 50). Ariami only listens for `SIGINT`
  (Ctrl+C) there (`lib/services/server_lifecycle_service.dart`); `stop`
  instead uses `taskkill /F` against the recorded PID, which is a hard kill
  rather than the graceful shutdown Unix gets via `SIGTERM`.
  (An older version of the CLI used to crash outright trying to watch
  SIGTERM on Windows — this is already fixed; if you see that specific
  crash, you're on a stale build.)
- Use `.\ariami_cli.bat` (not `./ariami_cli`) — the Windows release ships
  `bin\ariami_cli.exe` behind a `.bat` launcher (`ariami_cli-launcher.bat`).
- Start-on-boot uses the current user's
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` registry key
  (value name `AriamiCLI`) — this only runs when that user logs in, unlike
  the Linux/macOS mechanisms which don't require an active session.
- If Windows Defender SmartScreen warns about an unrecognized publisher,
  choose "More info" → "Run anyway", and allow the firewall prompt for
  private networks if you want LAN devices to connect (see `SETUP.txt`).
