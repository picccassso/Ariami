# Configuration Reference

Everything below is read directly from `lib/services/cli_state_service.dart`,
`lib/services/container_environment.dart`,
`lib/services/server_feature_flag_service.dart`, and
`lib/services/server_runtime_policy.dart`. If a key or variable is not listed
here, the CLI's own configuration code does not read it.

## Data directory

The Ariami data directory is:

- `$ARIAMI_DATA_DIR`, if that environment variable is set and non-empty; else
- `~/.ariami_cli` (`$HOME` on Linux/macOS, `%USERPROFILE%` on Windows), or
  `./.ariami_cli` if neither is set.

(`CliStateService.getConfigDir()`.) Use the **same** `ARIAMI_DATA_DIR` value
for every invocation (`start`, `stop`, `status`, `reset`, `configure`,
`autostart`) that should act on one particular install. Each command reads
it fresh from the environment.

### Files inside the data directory

| Path | Written by | Purpose |
| --- | --- | --- |
| `config.json` | `CliStateService` | Setup completion flag, music folder path, saved server port, bind host, transcode slot override, public account-picker setting, LAN/Tailscale endpoint aliases. |
| `users.json` | `ariami_core`'s `UserStore` | User account records (hashed passwords, no plaintext). Chmod'd `600` on Unix; parent directory chmod'd `700`. |
| `sessions.json` | `ariami_core`'s auth/session store | Active web/mobile sessions. |
| `catalog.db` (+ `-wal`, `-shm`, `-journal`) | `ariami_core`'s `CatalogDatabase` (SQLite, WAL mode) | Persistent library catalogue. |
| `metadata_cache.json` | `ariami_core`'s `LibraryManager`/`MetadataCache` | Library metadata cache, keyed off the same base path as the catalogue. |
| `music_discovery.json` | `ariami_core`'s `HouseholdMusicDiscoveryStore` | Household-wide music discovery settings (the Last.fm API key used by signed-in clients). |
| `artwork_cache/` | `ArtworkService` | Generated artwork thumbnails. |
| `transcoded_cache/` | `TranscodingService` | Generated audio transcode cache. |
| `ariami.pid` | `DaemonService` | PID of the background daemon, used by `status`/`stop`. |
| `server.json` | `DaemonService` | Runtime server state: port, PID, `started_at` timestamp (plus the bind host on normal background starts). |
| `server.log` | *(reserved, rarely populated; see below)* | Cleared by `reset` if present. The normal `start`/`--server-mode` path never writes to it. |
| `autostart.log` | `AutostartService` (crontab/LaunchAgent redirection) | Boot output, only when start-on-boot is enabled through `ariami_cli autostart`. |

> **`server.log` in practice:** background daemons are spawned with Dart's
> `ProcessStartMode.detached` (`lib/services/daemon_service.dart`), which
> gives the child no connection to the parent's stdin/stdout/stderr. The CLI
> itself never redirects that output into `server.log`, so in normal
> `ariami_cli start` background use the file usually will not exist or will
> stay empty. See
> [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#logs-and-verbosity) for where
> startup output actually goes and how to capture it.

`reset --setup` clears `config.json`, `server.json`, `server.log`, and
`ariami.pid` only. `reset --factory` additionally clears `users.json`,
`sessions.json`, `music_discovery.json`, `metadata_cache.json`,
`autostart.log`, `catalog.db` (with its `-wal`/`-shm`/`-journal` sidecars),
`artwork_cache/`, and `transcoded_cache/` (`lib/commands/reset_command.dart`,
`lib/services/cli_reset_plan.dart`).

### Reset scopes

| Scope | Flag | Removes | Keeps |
| --- | --- | --- | --- |
| Setup/config only | `--setup` | `config.json`, `server.json`, `server.log`, `ariami.pid` | Catalogue database, accounts, sessions, caches, `music_discovery.json` |
| Factory reset | `--factory` | Everything above, plus `users.json`, `sessions.json`, `music_discovery.json`, `metadata_cache.json`, `autostart.log`, `catalog.db` (+ sidecars), `artwork_cache/`, `transcoded_cache/` | Nothing Ariami-owned; also disables start-on-boot |

In both scopes, the reset engine (`ariami_core`'s `ResetService`) refuses to
delete a target that equals, contains, or is contained by your configured
music folder path, so even a misconfigured data directory nested inside
your music library can't take your music with it
(`ariami_core/lib/services/reset/reset_service.dart`).

## `config.json` keys

All keys are read/written by `CliStateService`. Missing or unparseable
keys/files are treated as "not set" rather than causing an error (see
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#database--config-corruption)).

| Key | Type | Default when absent | Set by |
| --- | --- | --- | --- |
| `setup_completed` | bool | `false` | End of the first-run web wizard. |
| `music_folder_path` | string | *(unset)* | The web wizard, `configure --music-folder`, or `music-folder set`. |
| `server_port` | int | *(unset, falls back to `8080` or the `--port`/`ARIAMI_PORT` given on a first run)* | The first successful bind. Later `start` runs reuse this value (see [`CLI_REFERENCE.md`](CLI_REFERENCE.md#start)). |
| `bind_host` | string | `0.0.0.0` | An explicit `--host` on `start`, or `--host` under `--server-mode`. |
| `transcode_slots` | int | *(unset, auto-selected: `6` on desktop and other non-Pi hosts, `5` on a Pi 5, `4` on a Pi 4, `3` on a Pi 3 or an unrecognised ARM Linux host; minimum `1`)* | The web dashboard's transcode slots dialog. Requires a server restart to apply. |
| `public_user_picker` | bool | `false` | The web dashboard's privacy switch for the pre-auth account picker. It stays off by default because, while on, any device on the LAN/tailnet can list account usernames before signing in. |
| `lan_server_alias` | string | *(unset)* | The web dashboard's display alias for the LAN URL. |
| `tailscale_server_alias` | string | *(unset)* | The web dashboard's display alias for the Tailscale URL. |

`CliStateService` also reads the older camelCase spellings
`lanServerAlias`/`tailscaleServerAlias` as fallbacks, and removes them the
next time aliases are saved.

## Environment variables

### Networking and deployment

| Variable | Effect |
| --- | --- |
| `ARIAMI_DATA_DIR` | Overrides the data directory (see above). |
| `ARIAMI_PORT` | Port the server binds when `--port` is absent. It counts as explicitly requested, so the `8080` to `8099` fallback scan is disabled. On a first run the value is saved; later `start` runs reuse the saved port. An invalid value fails startup with `ARIAMI_PORT must be a port number between 1 and 65535`. |
| `ARIAMI_ADVERTISED_HOST` | Single-address override for the host Ariami advertises in setup URLs, `/api/server-info`, and QR codes. Useful in containers. The LAN/Tailscale-specific overrides below take precedence for their own endpoint when both are set. |
| `ARIAMI_ADVERTISED_LAN_HOST` | Overrides the LAN host advertised for same-network devices. |
| `ARIAMI_ADVERTISED_TAILSCALE_HOST` | Overrides the Tailscale host advertised for tailnet devices. |
| `ARIAMI_ADVERTISED_PORT` | Port clients should connect on when something remaps the published port, for example `-p 2000:8080`. It does not change the port Ariami binds. A value outside `1` to `65535` is ignored with a startup warning. |
| `ARIAMI_PUBLIC_ORIGIN` | HTTPS origin exposed by a reverse proxy you control, e.g. `https://review.ariami.xyz`. Must be origin-only (no path/query/fragment/credentials) and HTTPS; an invalid value fails startup outright (`ariami_core`'s `normalizeSecurePublicOrigin`). |
| `ARIAMI_CONTAINER` | Set to `1`/`true` to mark the process as containerized. Docker images set this automatically (`docker/Dockerfile`); it is also inferred automatically when `/.dockerenv` exists. |
| `ARIAMI_TRUST_PROXY_HEADERS` | Set to `1` only when a reverse proxy **you control** fronts Ariami: trusts `X-Forwarded-For` for per-client login rate limiting. Leave unset otherwise, since a direct client can forge that header. |

### Runtime tuning (storage detection)

| Variable | Effect |
| --- | --- |
| `ARIAMI_STORAGE_PROFILE` | Overrides automatic storage-type detection used for cache sizing on a host treated as a Raspberry Pi. Accepted values (case-insensitive): `microsd`/`micro_sd`/`micro-sd`/`sd` for the microSD profile; `externalfast`/`external_fast`/`external-fast`/`ssd`/`fast` for the fast-external profile; `unknown`/`auto` (or anything unrecognised, which logs a warning) falls back to auto-detection. On a non-Pi host the cache policy ignores the profile, so the override has no effect there. See `lib/services/server_runtime_policy.dart`. |

See
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#memory--performance-on-low-end-hardware)
for exactly how storage type and Raspberry Pi detection change concurrency
and cache limits, including a real gotcha with non-Pi ARM64 boards.

### Feature flags (advanced/internal)

These gate rollout of newer server-side features and are read once at
startup by `ServerFeatureFlagService`
(`lib/services/server_feature_flag_service.dart`). Accepted truthy values
for all of them: `1`, `true`, `yes`, `on` (case-insensitive); anything else
is treated as unset/false.

| Variable | Default | Notes |
| --- | --- | --- |
| `ARIAMI_ENABLE_V2_API` | `true` | Enables the catalog-backed v2 API and catalogue persistence. |
| `ARIAMI_ENABLE_CATALOG_WRITE` | `false` | Independent of v2 API; resolves `true` when v2 API is enabled regardless of this flag. |
| `ARIAMI_ENABLE_CATALOG_READ` | `false` | Same relationship as catalogue write. Requires v2 API, see below. |
| `ARIAMI_ENABLE_ARTWORK_PRECOMPUTE` | `false` | Enables background artwork precomputation. |
| `ARIAMI_ENABLE_DOWNLOAD_JOBS` | `true` | **Requires** `ARIAMI_ENABLE_V2_API=true`, see below. |
| `ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB` | `true` | Scopes API auth for the CLI's own web dashboard. |
| `ARIAMI_ENABLE_CONNECT_PROTOCOL_V3` | `true` | Lets clients that offer Connect protocol v3 negotiate it. When off, peers fall back to v2 with no client redeployment. |
| `ARIAMI_ENABLE_PUBLIC_USER_PICKER` | `false` | Forces the pre-auth account picker on regardless of the persisted `public_user_picker` config value. It's an owner privacy override rather than a rollout flag, so it is not part of the flags struct above. |

**Invariants enforced at startup:** two flag combinations are rejected
outright. If `ARIAMI_ENABLE_DOWNLOAD_JOBS` resolves `true` while
`ARIAMI_ENABLE_V2_API` resolves `false`, the server refuses to start with:

```
Invalid feature flag configuration: enableDownloadJobs=true requires enableV2Api=true.
```

The same rule applies to `ARIAMI_ENABLE_CATALOG_READ=true`:

```
Invalid feature flag configuration: enableCatalogRead=true requires enableV2Api=true.
```

Because v2 API and download jobs both default to `true`, the first only
bites if you explicitly set `ARIAMI_ENABLE_V2_API=false` without also
disabling download jobs. Catalogue read defaults to `false`, so the second
only bites if you enable catalogue read while v2 API is off. Under default
settings neither can happen. Most operators never need to touch this
section; it exists for advanced/internal use.

## Runtime tuning: Raspberry Pi & storage detection

`ServerRuntimePolicy` (`lib/services/server_runtime_policy.dart`) detects, on
every start:

- **Raspberry Pi**: only ever considered on Linux, and only when
  `Platform.version` mentions `arm`/`aarch64`. It then reads
  `/proc/device-tree/model` or `/proc/cpuinfo` for a Raspberry Pi model
  string, and additionally checks specifically for `"raspberry pi 5"` to
  distinguish Pi 5 from Pi 3/4. **Important:** any Linux ARM host it can't
  positively identify is still conservatively treated as a Raspberry Pi
  (`isRaspberryPi()` returns `true` for unrecognised ARM Linux, on purpose).
  If you're running the arm64 build on a non-Pi ARM SBC or an ARM VM, you
  will get Pi-tuned (lower) concurrency and cache limits, with no way to
  force "not a Pi". Only `ARIAMI_STORAGE_PROFILE` can adjust the cache half
  of that tuning.
- **Storage type** (Pi only): reads `/proc/mounts` to find the device backing
  your music folder and your data directory separately. A device path
  containing `mmcblk` is classified `microSd`; `nvme` or `/dev/sd*` is
  classified `fastExternal`; anything else is `unknown`.

These feed two independent tables:

**Download concurrency limits** (`selectDownloadLimits`). These come only
from the platform/storage detection above:

| Platform | maxConcurrent | maxQueue | maxConcurrentPerUser | maxQueuePerUser |
| --- | --- | --- | --- | --- |
| macOS (non-Pi) | 30 | 400 | 10 | 200 |
| Other non-Pi (Linux/Windows) | 10 | 120 | 3 | 50 |
| Pi, fast external storage | 6 | 80 | 4 | 30 |
| Pi 5, microSD/unknown | 4 | 50 | 4 | 20 |
| Pi 3/4, microSD/unknown | 4 | 50 | 4 | 20 |

**Cache policy** (`selectCachePolicy`). The storage *profile* half of this
can be forced with `ARIAMI_STORAGE_PROFILE` on a Pi-class host:

| Profile | Transcode cache | Artwork cache | Index persist interval | Touch artwork on cache hit |
| --- | --- | --- | --- | --- |
| macOS/Windows (non-Pi) | 4096 MB | 256 MB | 30s | yes, no throttle |
| Other non-Pi | 2048 MB | 256 MB | 30s | yes, no throttle |
| Pi, fast external (Pi 5) | 2048 MB | 256 MB | 30s | yes, no throttle |
| Pi, fast external (Pi 3/4) | 1024 MB | 256 MB | 30s | yes, no throttle |
| Pi, microSD/unknown | 384 MB | 96 MB | 5 minutes | no, throttled to 30 min |

The startup log prints the resolved profile every time, e.g.:

```
Storage profile: microSd (music=microSd, state=microSd)
```

so you can confirm what was actually detected without guessing.

## See also

- [`CLI_REFERENCE.md`](CLI_REFERENCE.md) for the flags that set some of
  these values on the command line.
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for what happens when these
  files or values are missing, wrong, or corrupted.
- [`../HEADLESS.md`](../HEADLESS.md) and
  [`../docker/DOCKER.md`](../docker/DOCKER.md) for deployment-oriented
  walkthroughs of the networking variables above.
