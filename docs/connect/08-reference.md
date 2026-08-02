# Reference tables

## Constants

### Payload limits

| Limit | Value |
|---|---|
| Max raw frame | 8 MiB (8388608 bytes) |
| Max queue length | 5000 |
| Max track fields | 20 |
| Max track field-name length | 40 |
| Track string caps | `id`/`albumId`/`modifiedTime` 64, `genre` 256, `title`/`album`/`artist`/`albumArtist` 512, other 1024 |
| Global string max | 2048 |
| Max `commandId` length | 128 |
| Max `sourceId` length | 512 |
| Max device display name | 40 |
| JSON max depth / map keys / key length | 7 / 32 / 64 |
| `positionMs`, `durationMs` | 0 … 86400000 (24 h) |
| `volume` | 0.0 … 1.0 |
| `currentIndex` | -1 … 4999 |

### Server timings

| Setting | Value |
|---|---|
| Command timeout | 10 s |
| Max command deliveries | 4 |
| Max pending commands per session | 64 |
| Retained completed results | 256 |
| Transfer timeout | 30 s |
| Stale-peer timeout | 90 s |
| Stale-peer sweep interval | 30 s |
| Owner reclaim grace | 0 (immediate failover) |
| Recent-controller window | 120 s |
| Idle session retention | 30 min |
| Server WebSocket ping | 30 s |
| Identify deadline | 20 s |
| Max unidentified sockets per IP | 8 |
| Presence heartbeat eviction | 60 s |

### Client timings

| Setting | Value |
|---|---|
| Ping interval | 20 s |
| Connect timeout | 8 s |
| Welcome watchdog | 5 s |
| Liveness watchdog | 60 s |
| Backoff reset after | 60 s of received traffic |
| Refresh / dispose close timeout | 1 s each |
| Progress publish interval | 1 s |
| Command ack timeout | 4 s |
| Max command attempts | 4 |
| Completed transfer-id memory | 256 |
| Handled command-result memory | 256 |
| Seek / semantic threshold | > 1500 ms position delta |
| Reconnect backoff | `min(30, 1 << min(attempt, 5))` s |

### Ticket TTLs

| Ticket | TTL |
|---|---|
| Stream | `max(duration + 10min, 20min)`, capped at 2 h |
| Download | flat 2 h |
| Session token | 30 days, sliding |
| Registration token / invite code | 10 min, single use |

---

## Enums

**Protocol versions:** `2`, `3`. Advertised in preference order `[3, 2]`.

**`clientType` (wire):** `desktop`, `mobile`, `tv`. Nothing else joins the hub.
(`dashboard` exists for presence only.)

**Repeat modes:** `off`, `all`, `one`.

**Transfer phases:** `prepare`, `commit`, `cancel`.

**Cancel reasons:** `timeout`, `superseded`, `stale_owner`, `state_changed`,
`rejected`, `disconnect`, `owner_reclaimed`.

**Commands:** `play`, `pause`, `toggle`, `next`, `previous`, `seek`,
`set_volume`, `toggle_shuffle`, `cycle_repeat`, `play_queue_index`,
`play_context`, `remove_queue_index`, `insert_queue_track`, `clear_queue`.

**`sourceId`:** free-form opaque string, ≤ 512 chars. No closed enum exists; the
convention in use looks like `playlist:<id>`.

---

## WebSocket close codes

| Code | Reason | Origin | Action |
|---|---|---|---|
| 1000 | `Client closed` / `Refreshing Connect state` | client | normal |
| 1001 | `Connect transport disconnected` | client | reconnect |
| 4000 | `Replaced by a newer connection` | hub, duplicate `(userId, deviceId)` | **stop reconnecting** |
| 4000 | `Connection timed out` | hub stale sweep | reconnect |
| 4000 | server shutdown | server | reconnect |
| 4001 | `Authentication required` | server | **stop**, sign in again |
| 4001 | `Session expired or invalid` | server | **stop**, sign in again |
| 4001 | `Session expired or revoked` | server, mid-connection revalidation | **stop**, sign in again |
| 4002 | `Disconnected by admin` | admin API | reconnect |
| 4008 | `Identify timeout` | server, 20 s | fix the handshake |

Code 4000 is overloaded. The reference client distinguishes them by
substring-matching `"replaced"` in the reason — fragile, but that is the current
contract.

---

## Error codes

`E` = `connect_error.code`, `R` = `connect_command_result.code`,
`C` = synthesised client-side.

| Code | | Meaning / action |
|---|---|---|
| `INVALID_PAYLOAD` | E | Shape guard failed (depth, size, key count). Fix the payload |
| `UNSUPPORTED_MESSAGE` | E | Unknown `connect_*` type, or `connect_queue` on v2 |
| `INVALID_STATE` | E | `connect_state` failed validation |
| `INVALID_QUEUE` | E | `connect_queue` failed validation |
| `INVALID_NAME` | E | Rename normalised to empty |
| `MESSAGE_TOO_LARGE` | E/C | Frame over 8 MiB. Split the work |
| `DEVICE_OFFLINE` | E | Handoff target missing or not playback-capable |
| `NO_SESSION` | E | Nothing to transfer |
| `STALE_OWNER_EPOCH` | E | Handoff epoch mismatch. Wait for the next broadcast, retry |
| `TRANSFER_TIMEOUT` | E | Target silent for 30 s |
| `TRANSFER_SUPERSEDED` | E | A newer device choice replaced this handoff. Benign |
| `TRANSFER_STATE_CHANGED` | E | Queue or semantic generation moved during prepare. Retry |
| `TRANSFER_FAILED` | E | Target refused; message comes from the target |
| `INVALID_COMMAND_ID` | R | Empty or over 128 chars |
| `COMMAND_ID_COLLISION` | R | Id reused by another device or for different work. Mint a fresh one |
| `UNKNOWN_COMMAND` | R | `retry:true` for an id the hub no longer holds. Replay the full payload |
| `UNSUPPORTED_COMMAND` | R | Not in the allowlist, or the active device didn't advertise it |
| `INVALID_ARGUMENTS` | R | Argument validation failed |
| `PLAY_CONTEXT_TOO_LARGE` | R | Same, for `play_context`. Send a smaller context |
| `COMMAND_OVERFLOW` | R | 64 already pending. Back off |
| `COMMAND_TIMEOUT` | R | No result in 10 s |
| `COMMAND_RETRY_EXHAUSTED` | R/C | 4 attempts without an ack |
| `STALE_OWNER` | R | Ownership changed before or during the command. Refresh, reissue |
| `COMMAND_RETRY_UNSUPPORTED` | C | Hub can't dedupe; command dropped rather than risking double execution |
| `COMMAND_FAILED` | C | Default when the hub returns `ok:false` with no code |
| `CONNECT_ERROR` | C | Default for a `connect_error` with no code |
| *(none)* | R | "The active playback device is offline." — the one failure with no code |

---

## HTTP endpoints a Connect client uses

### Auth

| Endpoint | Notes |
|---|---|
| `POST /api/auth/login` | → `{userId, username, sessionToken, expiresAt}`. 409 = signed in elsewhere |
| `POST /api/auth/register` | Owner bootstrap or invite token required |
| `GET /api/auth/users` | Public account list (may be disabled) |
| `POST /api/auth/logout` | Revokes the session and all its tickets |
| `GET /api/me` | Bearer required |

Token goes in `Authorization: Bearer <token>` on HTTP, in the `identify` body on
the WebSocket, and as `?streamToken=` on media.

### Media

| Endpoint | Notes |
|---|---|
| `POST /api/stream-ticket` | `{songId, quality}` → `{streamToken, expiresAt}`. 410 `SONG_NOT_FOUND` |
| `GET /api/stream/<songId>?streamToken=` | Range-capable. `quality` omitted for high |
| `POST /api/download-ticket` | Flat 2 h ticket |
| `GET /api/download/<songId>?downloadToken=` | |
| `GET /api/artwork/<albumId>?size=` | Bearer or matching streamToken |
| `GET /api/song-artwork/<songId>` | Same |
| `POST /api/stream-warmup` | Optional; up to 3 song ids |

### Library (v2, gated behind a server setting that defaults off)

| Endpoint | Notes |
|---|---|
| `GET /api/v2/bootstrap?limit=&cursor=` | Albums, songs, playlists + `syncToken` |
| `GET /api/v2/albums` / `songs` / `playlists` | Single-entity pages |
| `GET /api/v2/changes?since=&limit=` | Incremental sync |

`GET /api/albums` and `GET /api/songs` (v1) are **empty stubs**.
`GET /api/albums/<albumId>` is real.

### Discovery and status

| Endpoint | Notes |
|---|---|
| `GET /api/ws` | The Connect WebSocket. Public path; auth is in `identify` |
| `GET /api/server-info` | Public. LAN + Tailscale + public origin, port, version |
| `GET /api/ping` | Public liveness probe |
| `GET /api/tailscale/status` | Public |

LAN auto-discovery: UDP `ARIAMI_DISCOVER_V1` → port 45420, multicast
239.255.90.90; mDNS `_ariami._tcp.local`. Ports 8080 preferred, 8081–8099
fallback.

### CORS

Origin-echo only, for loopback or the same host:port. No credentials, no exposed
headers. **Cross-origin browser clients are effectively unsupported** — write a
native or server-side client.

---

## Source map

| Concern | File |
|---|---|
| Wire models, validation, all limits | `ariami_core/lib/models/connect_models.dart` |
| Envelope, identify, ping | `ariami_core/lib/models/websocket_models.dart` |
| Hub: ownership, routing, failover | `ariami_core/lib/services/connect/connect_hub.dart` |
| Reference client state machine | `ariami_core/lib/services/connect/connect_client.dart` |
| Mirror position extrapolation | `ariami_core/lib/services/connect/remote_playback.dart` |
| WebSocket mount, auth, close codes | `ariami_core/lib/services/server/http_server_parts/websocket_and_static_part.dart` |
| Route table | `ariami_core/lib/services/server/http_server_parts/router_registration_part.dart` |
| Stream ticket TTL and scoping | `ariami_core/lib/services/server/stream_tracker.dart` |
| Session tokens | `ariami_core/lib/services/auth/session_store.dart` |
| Cross-client contract fixture | `ariami_core/test/fixtures/connect/v2_contract.json` |
| Fault coverage matrix | `ariami_core/test/fixtures/connect/fault_matrix.json` |
| P0 traffic measurements | `ariami_core/test/fixtures/connect/p0_measurements.json` |

For a worked example of wiring the client into a playback engine, see
`ariami_mobile/lib/services/ariami_connect_controller.dart` and
`ariami_mobile/lib/services/playback_manager_connect_impl.dart`.
