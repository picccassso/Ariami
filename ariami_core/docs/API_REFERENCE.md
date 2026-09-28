# HTTP and WebSocket API Surface

This is the route table `AriamiHttpServer` actually registers, read from
[`lib/services/server/http_server_parts/router_registration_part.dart`](../lib/services/server/http_server_parts/router_registration_part.dart).
Handler implementations live in the sibling `*_handlers_part.dart` files
under [`http_server_parts/`](../lib/services/server/http_server_parts).

## Authentication

An `Authorization: Bearer <sessionToken>` header is resolved by the auth
middleware into `request.context['session']`. A fixed set of paths is public:
`/api/ping`, `/api/server-info`, `/api/setup/status`, `/api/auth/login`,
`/api/auth/register`, `/api/auth/users`, `/api/auth/user-avatar/<username>`,
`/api/tailscale/*`, and `/api/ws`. The remaining `/api/setup/*` routes and
the playlist-suggestion routes are reachable without a session only while
no account exists yet (first-run setup). After that they need a session,
and the routes that change setup, start scans, or read and record playlist
decisions need the owner (admin) account. Endpoint aliases follow the same
first-run-versus-admin rule. The `auth/users` and `auth/user-avatar` picker
routes answer only when the owner has enabled the account picker.

Routes marked **protected** go through `_handleProtectedV2Request`
(implemented in
[`middleware_and_metrics_part.dart`](../lib/services/server/http_server_parts/middleware_and_metrics_part.dart)).
They require at least one registered account, so before an owner exists they
answer `401`. Once accounts exist, the request needs either a session
already resolved into `request.context['session']`, or an
`Authorization: Bearer <sessionToken>` header that validates against
`AuthService`.

Routes registered only when `AriamiFeatureFlags.enableV2Api` is true are
marked **(v2 flag)**; the download-job routes additionally require
`enableDownloadJobs` and are marked **(v2 flag + download-jobs flag)**.

## Core

| Method | Path | Notes |
|---|---|---|
| GET | `/api/ping` | Liveness check; returns version, hostname, and music availability |
| GET | `/api/tailscale/status` | Tailscale status via the host's callback |
| GET | `/api/server-info` | Server metadata (version, auth mode, endpoints, port, download limits) |
| POST | `/api/server-info/refresh` | Re-resolve advertised network endpoints |
| POST | `/api/server-info/aliases` | Set LAN/Tailscale display aliases (admin once users exist; open during first-run) |

## Setup and stats

| Method | Path | Notes |
|---|---|---|
| GET | `/api/setup/status` | First-run setup status |
| GET | `/api/setup/music-folder/suggestions` | Candidate music-folder paths |
| POST | `/api/setup/music-folder/validate` | Validate a candidate path |
| POST | `/api/setup/music-folder` | Set the configured music folder (admin once users exist) |
| POST | `/api/setup/start-scan` | Kick off a full library scan (admin once users exist) |
| GET | `/api/setup/scan-status` | Scan progress + diagnostics (suggestions, failed files) |
| POST | `/api/setup/complete` | Mark first-run setup complete (admin once users exist) |
| POST | `/api/setup/transition-to-background` | Hand off to background/daemon mode (host-supplied callback; admin once users exist) |
| GET | `/api/stats` | General server stats (library counts, connected clients and users, auth mode) |

## Auth and admin

| Method | Path | Notes |
|---|---|---|
| POST | `/api/auth/register` | Create an account. The first account becomes the owner and needs a local/loopback request, a registration token, or the console bootstrap code; later accounts need a valid registration token. Passwords are 10+ characters |
| GET | `/api/auth/users` | Pre-auth account picker list (only when the owner has enabled it, off by default) |
| GET | `/api/auth/user-avatar/<username>` | Pre-auth avatar image for the picker (404 while the picker is off) |
| POST | `/api/auth/login` | Password login. Requires `username`, `password`, `deviceId`, and `deviceName`; accepts `allowOtherDeviceTakeover`. Rate-limited: 5 attempts / 15 min per client address and username |
| POST | `/api/auth/logout` | Revoke the caller's session |
| GET | `/api/me` | Current account info |
| GET, PUT, DELETE | `/api/me/avatar` | Manage the caller's profile picture (JPEG/PNG, 5 MB max) |
| GET | `/api/license` | Read the stored licence files (any signed-in device) |
| PUT, DELETE | `/api/license` | Store another licence file / remove them all (admin) |
| GET | `/api/music-discovery/config` | Household Last.fm API key (any signed-in device) |
| PUT, DELETE | `/api/music-discovery/config` | Set (optionally `onlyIfMissing`) / remove the household key (admin) |
| POST | `/api/stream-ticket` | Issue a short-lived stream ticket for `{songId, quality?}` |
| POST | `/api/stream-warmup` | Queue up to 3 transcodes ahead of playback (`{songIds, quality?}`) |
| POST | `/api/download-ticket` | Issue a short-lived download ticket for `{songId, quality?, format?}`; format is `aac`, `m4a`, or `opus` |
| GET | `/api/admin/users` | List accounts (admin) |
| GET | `/api/admin/connected-clients` | Currently connected clients (admin) |
| GET | `/api/admin/user-activity` | Per-user activity rows (`UserActivityRow`) (admin) |
| GET | `/api/admin/registration-token` | One-time token for inviting a new account (admin) |
| GET | `/api/admin/invite-code` | Human-typeable invite code (admin) |
| GET, POST | `/api/admin/user-picker` | Read/set whether the pre-auth account picker is enabled (admin) |
| POST | `/api/admin/create-user` | Admin-create an account (admin) |
| POST | `/api/admin/kick-client` | Force-disconnect a client (admin) |
| POST | `/api/admin/change-password` | Change a user's password (admin) |
| POST | `/api/admin/delete-user` | Delete an account (admin; the last admin is protected) |
| GET, POST | `/api/admin/transcode-slots` | Read/override transcode concurrency slots; POST accepts `{slots}` or `{reset: true}` (admin) |
| GET | `/api/admin/host-controls` | Host controls snapshot (CLI only; 503 when the host registered no callbacks) |
| POST | `/api/admin/autostart` | Toggle start-at-boot `{enabled}` (CLI only; admin) |
| POST | `/api/admin/reset` | Run a `setup` or `factory` reset (CLI only; admin) |

## Library and artwork (v1)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/albums` | Empty stub kept for compatibility; use `/api/v2/albums` when the v2 flag is on |
| GET | `/api/albums/<albumId>` | Album detail with songs (session required) |
| GET | `/api/songs` | Empty stub kept for compatibility; use `/api/v2/songs` when the v2 flag is on |
| GET | `/api/artwork/<albumId>` | Album artwork, lazily extracted and cached; `?size=thumbnail` or `full`. Accepts a session or a stream token minted for a song on the album |
| GET | `/api/song-artwork/<songId>` | Standalone-song artwork; same auth, with a stream token that must match the song |

## Connection (legacy client presence)

| Method | Path | Notes |
|---|---|---|
| POST | `/api/connect` | Register client presence with `ConnectionManager` (session) |
| POST | `/api/disconnect` | Deregister client presence (session) |

This is distinct from **Ariami Connect** (remote playback rendezvous), which
runs entirely over the `/api/ws` WebSocket and `AriamiConnectHub`; see
[`ARCHITECTURE.md`](ARCHITECTURE.md#servicesconnect--ariami-connect-remote-playback).

## Streaming and download

| Method | Path | Notes |
|---|---|---|
| GET | `/api/stream/<path\|.*>` | Stream audio for a song ID. Requires a `streamToken` bound to that song and `quality`; supports HTTP range requests. `high` (default) streams the original file, `medium` transcodes to 128 kbps AAC, `low` to 64 kbps AAC |
| GET | `/api/download/<path\|.*>` | Download the full audio file for a song ID. Requires a `streamToken` or `downloadToken` bound to song, quality, and format; `format=aac\|m4a\|opus`; supports range requests |

## Listening statistics (always registered)

Registered unconditionally, not gated behind `enableV2Api`, because these
are session-scoped and independent of the catalogue repository. All
**protected**.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v2/listening/events` | Upload a batch of `ListeningEvent`s (idempotent by client-generated event ID) |
| GET | `/api/v2/listening/summary` | `ListeningStatsSummary` |
| GET | `/api/v2/listening/daily` | Daily totals (`days`, default 120, max 400) |
| GET | `/api/v2/listening/recent` | Recently played (`days`, default 7) |
| GET | `/api/v2/listening/day` | Single-day breakdown (`date=yyyy-mm-dd`) |
| GET | `/api/v2/listening/period` | Range query (`from`/`to` local days, max 1100 days) |
| GET | `/api/v2/listening/artists` | Artist rollups (credited-artist aware) |
| GET | `/api/v2/listening/albums` | Album rollups |
| GET | `/api/v2/listening/import-status` | Spotify import status for the calling account |
| POST | `/api/v2/listening/reset` | Clear the caller's history; `{"source": "spotify"}` removes only imported events |

## Pins (always registered, all protected)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/pins` | List pinned items, with display names and `missing` flags |
| POST | `/api/pins` | Add a pin `{type: "album"\|"playlist", targetId}` |
| DELETE | `/api/pins/<type>/<targetId>` | Remove a pin |
| POST | `/api/pins/import` | Bulk-import pins `{pins, replace?}`; entries are objects or legacy `"type:id"` strings |

## Hidden items (always registered, all protected)

Hiding is a browsing preference, not a permission: it only says what a
client should leave out of its library lists.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/hidden` | List hidden items, with display names and `missing` flags |
| POST | `/api/hidden` | Hide one `{type, targetId}` or a batch `{items: [...]}`; `type` is `album`, `playlist`, or `artist` |
| DELETE | `/api/hidden/<type>/<targetId>` | Unhide an item |

## Playlist suggestions (always registered; same authorization as the setup routes)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/playlists/suggestions` | Pending suggestions + recorded decisions + `isScanning` |
| POST | `/api/playlists/suggestions/decision` | `{folderPath, decision: "import"\|"ignore"\|"reset"}`; import triggers a rescan. See [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md) |

## Playlist edits (always registered, all protected)

Server-side overlay edits on top of folder/M3U-derived playlists. They
never mutate the catalogue.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/playlists/edits` | List the caller's playlist edits, with their cover images |
| PUT | `/api/playlists/<playlistId>/edit` | Upsert an edit `{songIds, baseSnapshot, name?}` |
| DELETE | `/api/playlists/<playlistId>/edit` | Clear an edit (revert to base) |
| GET, PUT, DELETE | `/api/playlists/<playlistId>/image` | Fetch, set (JPEG/PNG/WebP), or remove a custom cover image |

## Artist images (always registered, all protected)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v2/artists/images` | List the caller's custom artist images |
| GET | `/api/artists/<artistName>/image` | Serve the image bytes (404 when none is stored) |
| PUT | `/api/artists/<artistName>/image` | Store or replace the image (JPEG/PNG/WebP) |
| DELETE | `/api/artists/<artistName>/image` | Remove the image |

## V2 sync API (v2 flag)

Only registered when `AriamiFeatureFlags.enableV2Api` is true. All protected.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v2/bootstrap` | Catalogue snapshot at the current sync token (`V2BootstrapResponse`); `limit` defaults to 100 (max 500) and `cursor` continues |
| GET | `/api/v2/albums` | Paged album list from the catalogue DB (`cursor`, `limit`) |
| GET | `/api/v2/songs` | Paged song list (`cursor`, `limit`) |
| GET | `/api/v2/playlists` | Paged playlist list (`cursor`, `limit`) |
| GET | `/api/v2/changes` | Incremental change feed since a token (`V2ChangesResponse`); `limit` defaults to 200 (max 1000) |

## Download jobs (v2 flag + download-jobs flag)

Only registered when both `enableV2Api` and `enableDownloadJobs` are true.
All protected. Backed by `DownloadJobService` and the catalogue repository.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v2/download-jobs` | Create a batch download job |
| GET | `/api/v2/download-jobs/<jobId>` | Job status |
| GET | `/api/v2/download-jobs/<jobId>/items` | Per-item status (`cursor`, `limit`) |
| POST | `/api/v2/download-jobs/<jobId>/cancel` | Cancel a job |

## WebSocket - `GET /api/ws`

A single upgrade route (`websocket_and_static_part.dart` +
`router_registration_part.dart`). The server pings every 30 seconds
(`pingInterval`) to detect dead TCP connections (e.g. a device losing power
without sending a close frame). An unauthenticated socket must send an
`identify` message within 20 seconds
(`_webSocketIdentifyTimeout`) or it is closed with code 4008; a given client
IP may hold at most 8 unidentified sockets at once
(`_maxPendingWebSocketsPerIp`), and further upgrades get a 429. Once at
least one account exists, `identify` must carry a valid `sessionToken` or
the socket is closed with code 4001; during first-run it identifies without
one. An `identify` with `clientType` of `desktop`, `mobile`, or `tv` also
registers that device with Ariami Connect.

Message `type` values (`WsMessageType` in
[`models/websocket_models.dart`](../lib/models/websocket_models.dart)):

- `identify`: client to server, sent right after connecting (`deviceId`,
  optional `deviceName`/`sessionToken`/`clientType`).
- `library_updated`: server to client, includes `albumCount`/`songCount`.
- `sync_token_advanced`: server to client, `{latestToken, reason}` telling a
  v2 client it should call `/api/v2/changes`.
- `song_added` / `album_added` / `song_removed` / `album_removed`: server to
  client, incremental library change notifications.
- `server_shutdown`: server to client.
- `ping` / `pong`: application-level keepalive (in addition to the
  protocol-level WebSocket ping).
- `client_connected` / `client_disconnected`: server to client, includes
  `clientCount` and the affected `deviceName`.
- `listening_stats_updated`: server to client, another device's listening
  activity changed the caller's stats.
- `pins_changed`: server to client, the caller's pins changed on another
  device.
- `hidden_changed`: server to client, the caller's hidden items changed on
  another device.
- `playlist_edits_changed`: server to client, the caller's playlist edits
  changed on another device.
- `artist_images_changed`: server to client, the caller's custom artist
  images changed on another device.
- `endpoint_aliases_changed`: server to client, the owner changed the
  LAN/Tailscale display aliases.

Ariami Connect (remote-playback control) also runs over this same socket
once identified, using its own message vocabulary
(`AriamiConnectMessageType` in
[`models/connect_models.dart`](../lib/models/connect_models.dart)); see
[`ARCHITECTURE.md`](ARCHITECTURE.md#servicesconnect--ariami-connect-remote-playback).
