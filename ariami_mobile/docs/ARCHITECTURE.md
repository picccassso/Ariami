# Client architecture and protocol

A short technical note on how Ariami Mobile is put together and how it talks
to the server, for readers who want to go deeper than the troubleshooting
guide. Everything here is drawn from `lib/services/api/` and
`lib/services/api/connection/`.

## Shared core

The mobile app depends on `ariami_core` (`path: ../ariami_core` in
`pubspec.yaml`), the same package used by the other Ariami clients, for
protocol models and shared logic — e.g. `ServerOrigin` normalization
(`package:ariami_core/models/server_origin.dart`, used by the QR/manual
address parsers), the Ariami Connect client
(`package:ariami_core/services/connect/connect_client.dart`), and the
listening-event counting rules used by the stats service
(`package:ariami_core/ariami_core.dart` → `ListeningEventTracker`). The
mobile-specific code in `lib/` is the Flutter UI, platform integration
(audio, downloads, permissions), and local persistence (SQLite, secure
storage) built on top of that shared core.

## HTTP API

All requests go through `ApiClient` (`lib/services/api/api_client.dart`),
which targets `<baseUrl>/api` where `baseUrl` is either `http://<host>:<port>`
or an explicit HTTPS `publicOrigin` (`lib/models/server_info.dart`). The
default per-request timeout is **10 seconds**; connection-restore attempts
after an app restart use a tighter **3-second** timeout so a dead saved
server doesn't block startup.

Endpoints called by the client (grep `lib/services/api/api_client.dart` for
the full request bodies):

- **Connection lifecycle** — `/ping`, `/connect`, `/disconnect`
- **Auth** — `/auth/register`, `/auth/login`, `/auth/logout`, `/me`,
  `/me/avatar`
- **Discovery** — `/server-info` (public, unauthenticated — used during
  setup before a session exists)
- **Library** — `/albums`, `/albums/{id}`, `/songs`, `/songs/{id}`
- **Playback** — `/stream-ticket` (short-lived token exchange before
  streaming), `/stream-warmup`, `/stream/{songId}` (the actual audio bytes),
  `/download-ticket`
- **Sync/misc** — `/pins`, `/pins/import`, `/playlists/edits`,
  `/v2/download-jobs` (+ `/{id}`, `/{id}/cancel`), `/v2/listening/events`,
  `/v2/listening/summary`, `/v2/listening/reset`

Authenticated requests carry `Authorization: Bearer <sessionToken>`
(`AuthManager.authHeaders` in
`lib/services/api/connection/auth_manager.dart`); the token is persisted in
`flutter_secure_storage`, not `SharedPreferences`.

## Real-time updates

`WebSocketService` (`lib/services/api/websocket_service.dart`) connects to
`<wsUrl>/api/ws` (`wsUrl` derived from `baseUrl` via
`websocketOriginFor()` in `ariami_core`) and is used for push notifications
of library changes, playlist edits, and pin changes
(`WsMessageType` in `lib/models/websocket_models.dart`), rather than
polling. It pings every 30 seconds and reconnects 5 seconds after any
unexpected drop. A close code of `4001` or `4002` is treated specially as a
server-driven session invalidation (forced sign-out) rather than a network
error, and skips the reconnect loop in favor of routing straight to sign-in.

## Connection module breakdown

`ConnectionService` (`lib/services/api/connection_service.dart`) is a facade
over several single-responsibility modules under
`lib/services/api/connection/`, per its own header comment:

- `ConnectionStateManager` — core state and streams
- `AuthManager` — session token storage/retrieval and session-expiry events
- `ServerInfoManager` — server metadata and LAN/Tailscale endpoint resolution
- `ConnectionLifecycleManager` — connect/disconnect/restore-on-launch logic
- `HeartbeatManager` — 30s health-check ping, 3-failure tolerance before
  declaring the connection lost, and the auto-reconnect loop while offline
- `WebSocketHandler` — wraps `WebSocketService` for the connection layer
- `DeviceInfoManager` — persistent device ID/name sent on every `/connect`
- `ConnectionPersistenceManager` — `SharedPreferences` (server info) +
  `flutter_secure_storage` (session token)
- `EndpointSwitchHandler` — reacts to `EndpointResolver` telling it the
  active LAN/Tailscale address should change, verifying reachability before
  committing to the switch and rolling back on failure

`EndpointResolver` (`lib/services/api/endpoint_resolver.dart`) is what
actually decides LAN vs. Tailscale: it re-probes the configured LAN address
with a 500ms TCP connect every 15 seconds (and on every network-type
change), preferring it whenever reachable and falling back to the
Tailscale/primary address otherwise. A server configured with an explicit
HTTPS `publicOrigin` is exempted from this switching entirely — that trust
boundary is fixed once established (`ServerInfoManager.resolvePreferredServerInfo`).

## Local persistence

- **`sqflite`** — the local library-sync store (`lib/database/`), download
  queue state, cache index, and listening stats.
- **`SharedPreferences`** — most non-secret preferences (quality settings,
  offline-mode flag, cache limit, etc.) via a small synchronous wrapper
  (`lib/utils/shared_preferences_cache.dart`) that's pre-loaded at startup
  to avoid first-frame flicker.
- **`flutter_secure_storage`** — session token and other auth secrets only.

## Playback pipeline

`PlaybackManager` (`lib/services/playback_manager.dart`, split into
`*_streaming_impl.dart`, `*_queue_impl.dart`, `*_casting_impl.dart`,
`*_connect_impl.dart`, `*_lifecycle_impl.dart`, `*_persistence_impl.dart`)
decides *where* audio for the current song comes from — server stream,
downloaded file, cache, or (for remote playback) Chromecast/Ariami Connect —
and hands a resolved URL to `AriamiAudioHandler`
(`lib/services/audio/audio_handler.dart`), which wraps `just_audio` +
`audio_service` for actual playback, media-session integration, and
lock-screen controls. See `docs/TROUBLESHOOTING.md` → "Playback stalls or
won't start" for the concrete stream-vs-fallback decision logic and timeout.
