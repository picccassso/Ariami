# HTTP and WebSocket API Surface

This is the route table `AriamiHttpServer` actually registers, read from
[`lib/services/server/http_server_parts/router_registration_part.dart`](../lib/services/server/http_server_parts/router_registration_part.dart).
Handler implementations live in the sibling `*_handlers_part.dart` files
under [`http_server_parts/`](../lib/services/server/http_server_parts).

Routes marked **protected** go through `_handleProtectedV2Request`
(implemented in
[`middleware_and_metrics_part.dart`](../lib/services/server/http_server_parts/middleware_and_metrics_part.dart)):
if no users are registered yet the server is in legacy/open mode and the
handler runs unauthenticated; once at least one account exists, the request
needs either a session already resolved into `request.context['session']` by
upstream middleware, or an `Authorization: Bearer <sessionToken>` header that
validates against `AuthService`.

Routes registered only when `AriamiFeatureFlags.enableV2Api` is true are
marked **(v2 flag)**; the download-job routes additionally require
`enableDownloadJobs` and are marked **(v2 flag + download-jobs flag)**.

## Core

| Method | Path | Notes |
|---|---|---|
| GET | `/api/ping` | Liveness check |
| GET | `/api/tailscale/status` | Tailscale status via the host's callback |
| GET | `/api/server-info` | Server metadata (version, auth mode, endpoints) |
| POST | `/api/server-info/refresh` | Re-resolve advertised network endpoints |

## Setup and stats

| Method | Path | Notes |
|---|---|---|
| GET | `/api/setup/status` | First-run setup status |
| GET | `/api/setup/music-folder/suggestions` | Candidate music-folder paths |
| POST | `/api/setup/music-folder/validate` | Validate a candidate path |
| POST | `/api/setup/music-folder` | Set the configured music folder |
| POST | `/api/setup/start-scan` | Kick off a full library scan |
| GET | `/api/setup/scan-status` | Scan progress + diagnostics |
| POST | `/api/setup/complete` | Mark first-run setup complete |
| POST | `/api/setup/transition-to-background` | Hand off to background/daemon mode (host-supplied callback) |
| GET | `/api/stats` | General server stats |

## Auth and admin

| Method | Path | Notes |
|---|---|---|
| POST | `/api/auth/register` | Create the first/next account |
| GET | `/api/auth/users` | Pre-auth account picker list (only when the owner has enabled it — off by default) |
| GET | `/api/auth/user-avatar/<username>` | Pre-auth avatar image for the picker |
| POST | `/api/auth/login` | Password login (rate-limited: 5 attempts / 15 min per device, per `AuthService`) |
| POST | `/api/auth/logout` | Revoke the caller's session |
| GET | `/api/me` | Current account info |
| GET, PUT, DELETE | `/api/me/avatar` | Manage the caller's profile picture |
| GET, PUT, DELETE | `/api/license` | Opaque client license file relay (`LicenseFileStore`) |
| POST | `/api/stream-ticket` | Issue a short-lived stream ticket |
| POST | `/api/stream-warmup` | Pre-warm a transcode/stream before playback starts |
| POST | `/api/download-ticket` | Issue a short-lived download ticket |
| GET | `/api/admin/users` | List accounts (admin) |
| GET | `/api/admin/connected-clients` | Currently connected clients |
| GET | `/api/admin/user-activity` | Per-user activity rows (`UserActivityRow`) |
| GET | `/api/admin/registration-token` | One-time token for inviting a new account |
| GET | `/api/admin/invite-code` | Human-typeable invite code (unambiguous alphabet, e.g. no `0/1/I/L/O/U`) |
| GET, POST | `/api/admin/user-picker` | Read/set whether the pre-auth account picker is enabled |
| POST | `/api/admin/create-user` | Admin-create an account |
| POST | `/api/admin/kick-client` | Force-disconnect a client |
| POST | `/api/admin/change-password` | Change a user's password |
| POST | `/api/admin/delete-user` | Delete an account |
| GET, POST | `/api/admin/transcode-slots` | Read/override transcode concurrency slots |

## Library and artwork (v1)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/albums` | Full album list |
| GET | `/api/albums/<albumId>` | Album detail with songs |
| GET | `/api/songs` | Full song list |
| GET | `/api/artwork/<albumId>` | Album artwork (lazily extracted, cached) |
| GET | `/api/song-artwork/<songId>` | Standalone-song artwork |

## Connection (legacy client presence)

| Method | Path | Notes |
|---|---|---|
| POST | `/api/connect` | Register client presence with `ConnectionManager` |
| POST | `/api/disconnect` | Deregister client presence |

This is distinct from **Ariami Connect** (remote playback rendezvous), which
runs entirely over the `/api/ws` WebSocket and `AriamiConnectHub` — see
[`ARCHITECTURE.md`](ARCHITECTURE.md#servicesconnect--ariami-connect-remote-playback).

## Streaming and download

| Method | Path | Notes |
|---|---|---|
| GET | `/api/stream/<path\|.*>` | Stream audio (HTTP range requests supported; transcoding by `QualityPreset` query param) |
| GET | `/api/download/<path\|.*>` | Download the full audio file |

## Listening statistics (v2, always registered)

Registered unconditionally — not gated behind `enableV2Api` — because these
are session-scoped and independent of the catalog repository. All
**protected**.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v2/listening/events` | Upload a batch of `ListeningEvent`s (idempotent by client-generated event ID) |
| GET | `/api/v2/listening/summary` | `ListeningStatsSummary` |
| GET | `/api/v2/listening/daily` | Daily totals |
| GET | `/api/v2/listening/recent` | Recently played |
| GET | `/api/v2/listening/day` | Single-day breakdown |
| GET | `/api/v2/listening/period` | Range query (`StatsRangeKind`: all/today/day/week/month/year) |
| GET | `/api/v2/listening/artists` | Artist rollups (credited-artist aware) |
| GET | `/api/v2/listening/albums` | Album rollups |
| POST | `/api/v2/listening/reset` | Clear a user's listening history |

## Pins (always registered, all protected)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/pins` | List pinned items |
| POST | `/api/pins` | Add a pin |
| DELETE | `/api/pins/<type>/<targetId>` | Remove a pin |
| POST | `/api/pins/import` | Bulk-import pins |

## Playlist suggestions (always registered; not session-protected — same authorization as setup)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/playlists/suggestions` | Pending suggestions + recorded decisions |
| POST | `/api/playlists/suggestions/decision` | `{folderPath, decision: "import"\|"ignore"\|"reset"}` — see [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md) |

## Playlist edits (always registered, all protected)

Server-side overlay edits on top of folder/M3U-derived playlists — never
mutates the catalog.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/playlists/edits` | List the caller's playlist edits |
| PUT | `/api/playlists/<playlistId>/edit` | Upsert an edit (reorder/add/remove songs) |
| DELETE | `/api/playlists/<playlistId>/edit` | Clear an edit (revert to base) |
| GET | `/api/playlists/<playlistId>/image` | Fetch a custom cover image |
| PUT | `/api/playlists/<playlistId>/image` | Set a custom cover image |
| DELETE | `/api/playlists/<playlistId>/image` | Remove a custom cover image |

## V2 sync API (v2 flag)

Only registered when `AriamiFeatureFlags.enableV2Api` is true. All protected.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v2/bootstrap` | Full-catalog snapshot at the current sync token (`V2BootstrapResponse`) |
| GET | `/api/v2/albums` | Paged album list from the catalog DB |
| GET | `/api/v2/songs` | Paged song list |
| GET | `/api/v2/playlists` | Paged playlist list |
| GET | `/api/v2/changes` | Incremental change feed since a token (`V2ChangesResponse`) |

## Download jobs (v2 flag + download-jobs flag)

Only registered when both `enableV2Api` and `enableDownloadJobs` are true.
All protected. Backed by `DownloadJobService` and the catalog repository.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v2/download-jobs` | Create a batch download job |
| GET | `/api/v2/download-jobs/<jobId>` | Job status |
| GET | `/api/v2/download-jobs/<jobId>/items` | Per-item status |
| POST | `/api/v2/download-jobs/<jobId>/cancel` | Cancel a job |

## WebSocket — `GET /api/ws`

A single upgrade route (`websocket_and_static_part.dart` +
`router_registration_part.dart`). The server pings every 30 seconds
(`pingInterval`) to detect dead TCP connections (e.g. a device losing power
without sending a close frame). An unauthenticated socket must send an
`identify` message within 20 seconds
(`_webSocketIdentifyTimeout`) or it is evicted; a given client IP may hold at
most 8 unidentified sockets at once (`_maxPendingWebSocketsPerIp`) so an
unauthenticated peer can't pile up connections.

Message `type` values (`WsMessageType` in
[`models/websocket_models.dart`](../lib/models/websocket_models.dart)):

- `identify` — client → server, sent right after connecting (`deviceId`,
  optional `deviceName`/`sessionToken`/`clientType`).
- `library_updated` — server → client, includes `albumCount`/`songCount`.
- `sync_token_advanced` — server → client, `{latestToken, reason}` telling a
  v2 client it should call `/api/v2/changes`.
- `song_added` / `album_added` / `song_removed` / `album_removed` — server →
  client, incremental library change notifications.
- `server_shutdown` — server → client.
- `ping` / `pong` — application-level keepalive (in addition to the
  protocol-level WebSocket ping).
- `client_connected` / `client_disconnected` — server → client, includes
  `clientCount` and the affected `deviceName`.
- `listening_stats_updated` — server → client, another device's listening
  activity changed the caller's stats.
- `pins_changed` — server → client, the caller's pins changed on another
  device.
- `playlist_edits_changed` — server → client, the caller's playlist edits
  changed on another device.

Ariami Connect (remote-playback control) also runs over this same socket
once identified, using its own message vocabulary
(`AriamiConnectMessageType` in
[`models/connect_models.dart`](../lib/models/connect_models.dart)) — see
[`ARCHITECTURE.md`](ARCHITECTURE.md#servicesconnect--ariami-connect-remote-playback).
