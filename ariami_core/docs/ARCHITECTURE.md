# Architecture / Module Map

This walks the real `lib/` tree and explains what each part does. Paths are
relative to [`ariami_core/`](..). The public export surface is defined in
[`lib/ariami_core.dart`](../lib/ariami_core.dart); a few internal files (e.g.
`.part.dart` files) are implementation details of an exported class and are
noted as such.

```
lib/
├── ariami_core.dart          # library entry point / exports
├── app_version.dart          # kAriamiVersion
├── models/                   # plain data/contract classes, no I/O
├── services/
│   ├── artwork/               # artwork resize + cache
│   ├── auth/                  # accounts, sessions, login
│   ├── catalog/                # SQLite catalog DB (v2 sync source of truth)
│   ├── connect/                # "Ariami Connect" remote-playback rendezvous
│   ├── discovery/              # LAN/mDNS server discovery beacon
│   ├── library/                # scanning, metadata, playlists, watcher
│   ├── license/                # opaque client license file relay
│   ├── pins/                   # account-scoped pinned albums/playlists
│   ├── playlists/              # server-side playlist edits + cover images
│   ├── reset/                  # factory-reset / setup-reset file deletion
│   ├── search/                 # shared search ranking engine
│   ├── server/                 # AriamiHttpServer + supporting services
│   ├── setup/                  # music-folder path validation helper
│   ├── stats/                  # listening-history event log + rollups
│   └── transcoding/             # Sonic-backed MP3→AAC transcoding
└── utils/                     # small text/permission helpers
```

## `models/`

Pure data classes (requests, responses, domain entities) with `toJson`/
`fromJson` where relevant — no I/O, no singletons. Grouped by concern:

| File | Contents |
|---|---|
| [`album.dart`](../lib/models/album.dart) | `Album` |
| [`song_metadata.dart`](../lib/models/song_metadata.dart) | `SongMetadata` |
| [`library_structure.dart`](../lib/models/library_structure.dart) | `LibraryStructure` — albums + standalone songs, the in-memory library shape |
| [`folder_playlist.dart`](../lib/models/folder_playlist.dart) | `FolderPlaylist` (folder-derived playlists; `generateId(folderPath)`) |
| [`playlist_suggestion.dart`](../lib/models/playlist_suggestion.dart) | `PlaylistSuggestion` — advisory playlist candidates from `PlaylistFolderClassifier` |
| [`scan_result.dart`](../lib/models/scan_result.dart) | `ScanProgress`, `ScanResult`, `ScanError`, `ScanErrorType` |
| [`scan_diagnostics.dart`](../lib/models/scan_diagnostics.dart) | `ScanFailedFile`, `ScanDiagnostics` (auto-imported playlist folders, malformed M3Us, etc.) |
| [`file_change.dart`](../lib/models/file_change.dart) | `FileChangeType`, `FileChange`, `LibraryUpdate` (watcher output) |
| [`api_models.dart`](../lib/models/api_models.dart) | v1 REST contracts: `ConnectRequest/Response`, `AlbumModel`, `SongModel`, `PlaylistModel`, `LibraryResponse`, `AlbumDetailResponse`, `ApiError`, `ErrorResponse`, `ApiErrorCodes` |
| [`sync_models.dart`](../lib/models/sync_models.dart) | v2 sync contracts: `V2EntityType`, `V2ChangeOperation`, `V2PageInfo`, `V2BootstrapResponse`, `V2ChangeEvent`, `V2ChangesResponse` |
| [`auth_models.dart`](../lib/models/auth_models.dart) | `RegisterRequest/Response`, `LoginRequest/Response`, `LogoutRequest/Response`, `StreamTicketRequest/Response`, `DownloadTicketRequest/Response`, `User`, `Session`, `AuthErrorCodes` |
| [`connect_models.dart`](../lib/models/connect_models.dart) | `AriamiConnectMessageType`, `AriamiConnectCommand`, `AriamiConnectDevice`, `AriamiPlaybackSnapshot` |
| [`websocket_models.dart`](../lib/models/websocket_models.dart) | `WsMessageType`, `WsMessage` base type and the concrete message classes below |
| [`download_job_models.dart`](../lib/models/download_job_models.dart) | Multi-item batch download job contracts (`DownloadJobCreateRequest/Response`, `DownloadJobStatusResponse`, `DownloadJobItemResponse`, statuses, error codes) |
| [`listening_stats_models.dart`](../lib/models/listening_stats_models.dart) | `ListeningEvent`, rollup types (`ListeningSongRollup`, `ListeningArtistRollup`, `ListeningAlbumRollup`, `ListeningDailyTotal`), `ListeningStatsSummary`, `ListeningPeriodStats` |
| [`pinned_item.dart`](../lib/models/pinned_item.dart) | `PinnedItem` |
| [`user_activity_row.dart`](../lib/models/user_activity_row.dart) | `UserActivityRow` (admin user-activity view) |
| [`quality_preset.dart`](../lib/models/quality_preset.dart) | `QualityPreset` enum (`high`/`medium`/`low`; medium=128kbps AAC, low=64kbps AAC) |
| [`artwork_size.dart`](../lib/models/artwork_size.dart) | `ArtworkSize` enum |
| [`server_origin.dart`](../lib/models/server_origin.dart) | HTTPS public-origin parsing/normalization helper used by `setPublicOrigin` |
| [`feature_flags.dart`](../lib/models/feature_flags.dart) | `AriamiFeatureFlags` — see [Feature flags](#feature-flags) below |

### WebSocket message types

[`websocket_models.dart`](../lib/models/websocket_models.dart) defines
`WsMessageType` constants and typed wrappers for a subset of them
(`LibraryUpdatedMessage`, `SyncTokenAdvancedMessage`, `IdentifyMessage`,
`SongAddedMessage`, `AlbumAddedMessage`, `PingMessage`, `PongMessage`,
`ClientConnectedMessage`, `ClientDisconnectedMessage`). The full set of type
strings the server/clients exchange over `/api/ws`:

`identify`, `library_updated`, `sync_token_advanced`, `song_added`,
`album_added`, `song_removed`, `album_removed`, `server_shutdown`, `ping`,
`pong`, `client_connected`, `client_disconnected`, `listening_stats_updated`,
`pins_changed`, `playlist_edits_changed`.

## `services/library/` — scanning, metadata, and playlist detection

- [`file_scanner.dart`](../lib/services/library/file_scanner.dart) —
  `FileScanner`. Recursively walks a folder for audio files; supported
  extensions (`supportedExtensions`): `.mp3`, `.m4a`, `.mp4`, `.flac`, `.wav`,
  `.aiff`, `.ogg`, `.opus`, `.wma`, `.aac`, `.alac`.
- [`metadata_extractor.dart`](../lib/services/library/metadata_extractor.dart)
  (+ `metadata_extractor/*.part.dart`) — `MetadataExtractor`. Reads ID3/Vorbis
  tags via `dart_tags`, extracts artwork and probes files; split into
  `metadata_extractor_metadata.part.dart`, `_artwork.part.dart`,
  `_probes.part.dart`.
- [`mp3_duration_parser.dart`](../lib/services/library/mp3_duration_parser.dart)
  — `Mp3DurationParser`, a pure-Dart CBR/VBR MP3 duration reader that copes
  with large ID3 tags containing embedded artwork, without a native decoder.
- [`metadata_cache.dart`](../lib/services/library/metadata_cache.dart) —
  `CachedMetadataEntry` + a JSON-file cache (mtime/size validated) so rescans
  skip re-reading tags for unchanged files.
- [`album_builder.dart`](../lib/services/library/album_builder.dart) —
  `AlbumBuilder`, plus `resolveAlbumArtworkSources` (prefers a folder sidecar
  image, falls back to lazy embedded-artwork extraction).
- [`album_grouping.dart`](../lib/services/library/album_grouping.dart) —
  shared album-artist resolution rules used by both `AlbumBuilder` and
  `ChangeProcessor` (album artist tag wins unless it looks like a YouTube
  channel name derived from the track artist, e.g. `"EminemMusic"`).
- [`album_identity.dart`](../lib/services/library/album_identity.dart) —
  `generateAlbumId(title, artist)`, a stable hash-based album ID.
- [`album_art_detection.dart`](../lib/services/library/album_art_detection.dart)
  — sidecar cover-art filename matching (`cover.jpg`, etc.) and album
  directory inference from song paths.
- [`duplicate_detector.dart`](../lib/services/library/duplicate_detector.dart)
  — `DuplicateGroup` + hash/metadata-based duplicate detection.
- [`library_scanner_isolate.dart`](../lib/services/library/library_scanner_isolate.dart)
  — runs a full scan on a background `Isolate` so scanning never blocks the
  server event loop; also where playlist auto-import/suggestion logic is
  invoked during a full scan.
- [`folder_watcher.dart`](../lib/services/library/folder_watcher.dart) +
  [`change_processor.dart`](../lib/services/library/change_processor.dart) —
  `FolderWatcher` (wraps the `watcher` package) emits `FileChange`s;
  `ChangeProcessor` turns them into incremental `LibraryStructure` updates
  without a full rescan.
- [`m3u_playlist_parser.dart`](../lib/services/library/m3u_playlist_parser.dart)
  — `M3uParseResult` + parser for `.m3u`/`.m3u8` (comments/blank lines
  ignored, relative/absolute/`file://` entries resolved, `http(s)://` stream
  entries skipped, order preserved, duplicates de-duplicated).
- [`natural_path_order.dart`](../lib/services/library/natural_path_order.dart)
  — `compareNaturalPath`, numeric-aware sort (`2 < 10 < 100`) for playlist
  entry ordering.
- [`playlist_folder_classifier.dart`](../lib/services/library/playlist_folder_classifier.dart)
  — `PlaylistFolderClassifier`, the suggestion/auto-import heuristics
  (album/artist diversity thresholds, playlist-like name matching) described
  in full in [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md).
- [`playlist_decision_store.dart`](../lib/services/library/playlist_decision_store.dart)
  — `PlaylistFolderDecision` (`import`/`ignore`/`reset`) persisted to
  `playlist_decisions.json`.
- [`library_playlist_builder.dart`](../lib/services/library/library_playlist_builder.dart)
  — turns `FolderPlaylist` + M3U + suggestion-import data into the
  playlists attached to a `LibraryStructure`.
- [`library_manager.dart`](../lib/services/library/library_manager.dart) (+
  `library_manager/*.part.dart`) — see below.

### `LibraryManager` (singleton)

[`library_manager.dart`](../lib/services/library/library_manager.dart) defines
the `LibraryManager` singleton (`factory LibraryManager() => _instance`), the
main library coordinator. Its behavior is split across `part` files under
[`library_manager/`](../lib/services/library/library_manager):

- `library_manager_scanning.part.dart` — `scanMusicFolder(...)`, orchestrates
  `LibraryScannerIsolate` and updates `_library`/`_lastScanTime`.
- `library_manager_api.part.dart` — `toApiJson`, `toApiJsonWithDurations`,
  `getAlbumDetail` — builds v1 REST JSON from the in-memory library.
- `library_manager_catalog.part.dart`, `_catalog_artwork.part.dart`,
  `_catalog_changes.part.dart`, `_catalog_duration_updates.part.dart`,
  `_catalog_records.part.dart` — write scan/watcher results into the SQLite
  catalog database via `CatalogWriter` when catalog persistence is enabled
  (see [Feature flags](#feature-flags)).
- `library_manager_duration.part.dart` — lazy/duration-warm-up extraction and
  the `LruCache` (defined in the main file) backing artwork/duration/song
  caches.
- `library_manager_cache.part.dart` — metadata-cache clearing for "force
  rescan".

`LibraryManager` also owns O(1) lookup indexes (`_songById`, `_songPathById`,
`_songAlbumIdById`) rebuilt after every scan/update, and exposes
`createCatalogRepository()` which returns a `CatalogRepository` (or `null` if
catalog persistence isn't initialized/enabled) — this is how `AriamiHttpServer`
and `DownloadJobService` reach the catalog DB.

## `services/catalog/` — the v2 sync source of truth

- [`catalog_database.dart`](../lib/services/catalog/catalog_database.dart) —
  `CatalogDatabase`, opens `catalog.db` (WAL mode, `synchronous=NORMAL`) and
  runs `CatalogMigrations.migrate`.
- [`catalog_migrations.dart`](../lib/services/catalog/catalog_migrations.dart)
  — forward-only schema migrations, `currentVersion = 5`. See
  [`DATA_AND_PERSISTENCE.md`](DATA_AND_PERSISTENCE.md) for the table list.
- [`catalog_writer.dart`](../lib/services/catalog/catalog_writer.dart) —
  `CatalogWriter`, upserts albums/songs/playlists/playlist-songs/artwork
  variants from a `LibraryStructure` and appends rows to `library_changes`
  (the token log that powers `/api/v2/changes`).
- [`catalog_repository.dart`](../lib/services/catalog/catalog_repository.dart)
  — `CatalogRepository` and record types (`CatalogAlbumRecord`, etc.); the
  read-side query API used by `AriamiV2Handlers` and `DownloadJobService`.

## `services/server/` — the HTTP/WebSocket server

- [`http_server.dart`](../lib/services/server/http_server.dart) —
  `AriamiHttpServer` (singleton). Declares state (feature flags, singletons
  it owns, in-memory maps) and stitches together its behavior from `part`
  files under [`http_server_parts/`](../lib/services/server/http_server_parts):
  - `lifecycle_and_config_part.dart` — `start`/`startWithPortFallback`/`stop`,
    `initializeAuth` (wires up `AuthService`, `DeviceNameStore`,
    `ListeningStatsStore`, `PinnedItemStore`, `PlaylistEditStore`,
    `PlaylistImageStore`, `LicenseFileStore` — see
    [`DATA_AND_PERSISTENCE.md`](DATA_AND_PERSISTENCE.md)), and the various
    `setXxxCallback` hooks a host app registers (music-folder callbacks,
    Tailscale status, transcode-slot overrides, etc.).
  - `router_registration_part.dart` — builds the `shelf_router.Router`; the
    canonical route list (see [`API_REFERENCE.md`](API_REFERENCE.md)).
  - `middleware_and_metrics_part.dart` — auth/rate-limit middleware wrapping,
    request metrics.
  - `auth_handlers_part.dart`, `admin_handlers_part.dart` — register/login/
    logout/me/avatar, and owner/admin endpoints (user management, kicking
    clients, transcode slots, invite codes).
  - `setup_and_stats_handlers_part.dart` — first-run setup flow
    (music-folder validate/set, start-scan, scan-status, mark-complete) and
    `/api/stats`.
  - `listening_stats_handlers_part.dart`, `pins_handlers_part.dart`,
    `playlist_edits_handlers_part.dart`, `playlist_suggestions_handlers_part.dart`
    — the account-data endpoint groups.
  - `library_and_artwork_handlers_part.dart` — `/api/albums`, `/api/songs`,
    `/api/artwork/<id>`, `/api/song-artwork/<id>`.
  - `stream_and_download_handlers_part.dart` — `/api/stream/...`,
    `/api/download/...`, including transcoding and range-request handling.
  - `media_ticket_handlers_part.dart` — `/api/stream-ticket`,
    `/api/stream-warmup`, `/api/download-ticket`.
  - `download_jobs_handlers_part.dart` — the `/api/v2/download-jobs*` group.
  - `connection_handlers_part.dart` — `/api/connect`, `/api/disconnect`
    (legacy client presence registration, distinct from Connect/remote
    playback).
  - `license_handlers_part.dart` — `/api/license` GET/PUT/DELETE.
  - `websocket_and_static_part.dart` — the `/api/ws` upgrade handler and
    static web-asset serving.
  - `http_server_limiters.dart` (not a `part of http_server.dart` split by
    topic, but a sibling file) — weighted-fair download concurrency limiter
    and a simple per-user limiter used for artwork requests.
- [`connection_manager.dart`](../lib/services/server/connection_manager.dart)
  — `ConnectionManager`, an in-memory map of connected clients + listener
  callbacks for connect/disconnect notifications.
- [`streaming_service.dart`](../lib/services/server/streaming_service.dart) —
  `StreamingService.streamFile`, serves a file with HTTP `Range` support
  (`RangeHeader.parse`), polling for still-growing files.
- [`stream_tracker.dart`](../lib/services/server/stream_tracker.dart) —
  `StreamTracker` (singleton), issues/tracks short-lived stream and download
  tickets and active-stream state; `StreamDelivery` distinguishes `http`
  streams from `direct` (local file playback on the server host itself, so
  stream accounting still covers it).
- [`device_name_store.dart`](../lib/services/server/device_name_store.dart) —
  persists user-chosen device display names (`device_names.json`), overlaid
  on whatever name a client self-reports.
- [`download_job_service.dart`](../lib/services/server/download_job_service.dart)
  — `DownloadJobService`, backs the v2 batch-download-job endpoints, reading
  from `CatalogRepository`.
- [`metrics_service.dart`](../lib/services/server/metrics_service.dart) —
  `AriamiMetricsService`, aggregates server metrics into periodic structured
  log summaries (default 60s interval).
- [`network_endpoint_monitor.dart`](../lib/services/server/network_endpoint_monitor.dart)
  — `NetworkEndpoints` (Tailscale IP / LAN IP) + a monitor that notifies on
  change.
- [`response_compression.dart`](../lib/services/server/response_compression.dart)
  — gzip-compresses JSON API responses when the client advertises support.
- [`server_port_policy.dart`](../lib/services/server/server_port_policy.dart)
  — `PortBindingException` and the port-fallback policy (try the preferred
  port, fall back within a scanned range).
- [`tailscale_path_diagnostics.dart`](../lib/services/server/tailscale_path_diagnostics.dart)
  — shells out to the `tailscale` CLI (via an injectable process runner) for
  status/diagnostics.
- [`v2_handlers.dart`](../lib/services/server/v2_handlers.dart) —
  `AriamiV2Handlers` (`handleBootstrap`, `handleAlbums`, `handleSongs`,
  `handlePlaylists`, `handleChanges`), reading from a `CatalogRepository`.

## `services/auth/`

- [`auth_service.dart`](../lib/services/auth/auth_service.dart) —
  `AuthService` (singleton): `register`, `login` (with a per-key rate limiter,
  `maxLoginAttempts`/`rateLimitCooldown = 15 minutes`), `logout`,
  `validateSession`, session/device management, `changePassword`,
  `deleteUserById`. Throws `AuthException(code, message)` on failure.
- [`user_store.dart`](../lib/services/auth/user_store.dart) — `UserStore`,
  JSON-file-backed user accounts (bcrypt-hashed passwords via the `bcrypt`
  package), O(1) in-memory maps, atomic writes, case-insensitive username
  index.
- [`session_store.dart`](../lib/services/auth/session_store.dart) —
  `SessionStore`, JSON-file-backed sessions with a sliding
  `defaultTtl = Duration(days: 30)` and periodic (5-minute) expiry cleanup.

Per the existing [`../README.md`](../README.md): if no users are registered
the server runs in legacy/open mode; once the first user registers,
authentication becomes required (`_authRequired`/`_legacyMode` in
`AriamiHttpServer`, updated by `updateAuthMode()`).

## `services/connect/` — Ariami Connect (remote playback)

- [`connect_hub.dart`](../lib/services/connect/connect_hub.dart) —
  `AriamiConnectHub`, an in-memory, authenticated WebSocket rendezvous: peers
  register with `(userId, deviceId, deviceName, clientType)`; a
  `disconnectGracePeriod` (3s) lets a briefly-dropped controller reconnect
  before another device takes over, and relayed commands time out after
  `commandTimeout` (10s) if the target device never answers. Playback state
  itself stays owned by clients — after a server restart, the active device
  simply republishes it.
- [`connect_client.dart`](../lib/services/connect/connect_client.dart) — the
  client-side counterpart used by apps that want to *control* or *mirror*
  another device's playback over Connect.
- [`remote_playback.dart`](../lib/services/connect/remote_playback.dart) —
  `RemotePlaybackSnapshot`-style read-only view of another device's queue/
  track/progress so a controller's UI can mirror it and route every action
  through Connect commands.

Connect message/command vocabulary lives in
[`models/connect_models.dart`](../lib/models/connect_models.dart)
(`AriamiConnectMessageType`: `connect_hello`, `connect_welcome`,
`connect_devices`, `connect_state`, `connect_command`,
`connect_command_result`, `connect_transfer`, `connect_transfer_result`,
`connect_rename`, `connect_error`; `AriamiConnectCommand`: `play`, `pause`,
`toggle`, `next`, `previous`, `seek`, `set_volume`, `toggle_shuffle`,
`cycle_repeat`, `play_queue_index`, and a queue-replace command). Connect
messages intentionally never carry stream URLs or session tokens — every
playback device requests its own short-lived stream ticket.

## `services/discovery/` — LAN/mDNS server discovery

- [`discovery_protocol.dart`](../lib/services/discovery/discovery_protocol.dart)
  — shared constants: UDP beacon port `45420`, multicast group
  `239.255.90.90`, probe message `ARIAMI_DISCOVER_V1`, mDNS service type
  `_ariami._tcp.local`.
- [`discovery_responder.dart`](../lib/services/discovery/discovery_responder.dart)
  — `DiscoveryResponder`, runs on the server: answers UDP beacon probes
  unicast and advertises over mDNS/DNS-SD so routers' mDNS reflectors can
  carry discovery across VLANs; every failure is logged and swallowed so
  discovery can never break the server itself.
- [`discovery_browser.dart`](../lib/services/discovery/discovery_browser.dart)
  — the client-side counterpart that listens for beacon replies/mDNS
  announcements.
- [`dns_wire.dart`](../lib/services/discovery/dns_wire.dart) — a minimal
  DNS/mDNS wire-format codec (RFC 6762/6763), enough to encode/decode what
  the beacon and mDNS advertiser need.

## `services/stats/` — listening history

- [`listening_stats_store.dart`](../lib/services/stats/listening_stats_store.dart)
  (+ `listening_stats_store/*.dart` parts: `schema.dart`,
  `event_ingestion.dart`, `queries.dart`, `rollup_maintenance.dart`) —
  `ListeningStatsStore`, the server-side SQLite-backed event log and
  rollups. Raw events (`listening_events`) are the source of truth; every
  rollup table is disposable and rebuildable. See
  [`DATA_AND_PERSISTENCE.md`](DATA_AND_PERSISTENCE.md) for the schema.
- [`listening_event_tracker.dart`](../lib/services/stats/listening_event_tracker.dart)
  — client-side `ListeningTrackInfo` + play-action tracking logic.
- [`listening_event_outbox.dart`](../lib/services/stats/listening_event_outbox.dart)
  — durable client-side queue of events awaiting upload (survives restarts
  and offline periods).
- [`listening_stats_syncer.dart`](../lib/services/stats/listening_stats_syncer.dart)
  — drains a `ListeningEventOutbox` to the server.
- [`period_stats_overlay.dart`](../lib/services/stats/period_stats_overlay.dart)
  — display-only merge of server-confirmed stats with still-pending outbox
  events, so an offline UI doesn't freeze on stale numbers.
- [`stats_local_day.dart`](../lib/services/stats/stats_local_day.dart) —
  `statsLocalDay(occurredAtMs, tzOffsetMinutes)`, the shared day-bucketing
  function.
- [`stats_range.dart`](../lib/services/stats/stats_range.dart) —
  `StatsRangeKind` (`all`, `today`, `day`, `week`, `month`, `year`).
- [`credited_artist_splitter.dart`](../lib/services/stats/credited_artist_splitter.dart)
  — `CreditedArtist` + splitting a raw display-artist string (e.g. `"Kanye
  West, Big Sean, Pusha T, 2 Chainz"`) into individually-credited artists;
  every credited artist gets the *full* play/listened-time credit, never a
  divided share.
- [`spotify_import/`](../lib/services/stats/spotify_import) — importing
  Spotify's "Extended Streaming History" export:
  `spotify_import_models.dart`, `spotify_history_parser.dart` (parses the
  export), `library_track_matcher.dart` (matches Spotify tracks to local
  library songs), `spotify_event_builder.dart` (turns matches into
  `ListeningEvent`s), `spotify_importer.dart` (`SpotifyImporter`, the
  parse → match → build facade; chunks output at the server's 500-events-
  per-POST cap).

## `services/transcoding/`

- [`transcoding_service.dart`](../lib/services/transcoding/transcoding_service.dart)
  (+ `src/*.dart` parts: `_environment`, `_process`, `_cache`, `_models`,
  `_ffi`) — `TranscodingService`: transcodes MP3 → AAC via the Sonic native
  library (loaded through Dart FFI in `transcoding_service_ffi.dart`),
  separate concurrency limits for streaming vs. download requests, a
  JSON-index-backed LRU disk cache, failure backoff for repeatedly-failing
  files, and an `ffprobe` fast path to skip unnecessary transcodes.
  `TranscodeRequestType` distinguishes `streaming` from `download`.
- [`transcode_slots_policy.dart`](../lib/services/transcoding/transcode_slots_policy.dart)
  — policy for how many transcode "slots" (concurrent transcodes) a host
  should allow, including admin overrides.

## `services/artwork/`

- [`artwork_service.dart`](../lib/services/artwork/artwork_service.dart) —
  `ArtworkService`, resizes/compresses album artwork into cached size
  variants (also used by `LibraryManager` to precompute variants at scan
  time when `enableArtworkPrecompute` is on).

## `services/pins/`, `services/playlists/`, `services/license/` — account data

These three own SQLite databases that are deliberately **separate from the
catalog database** so a library rescan can never remove user data (see
[`DATA_AND_PERSISTENCE.md`](DATA_AND_PERSISTENCE.md)):

- [`pins/pinned_item_store.dart`](../lib/services/pins/pinned_item_store.dart)
  — `PinnedItemStore`, account-scoped pinned albums/playlists.
- [`playlists/playlist_edit_store.dart`](../lib/services/playlists/playlist_edit_store.dart)
  — `PlaylistEditStore`/`PlaylistEdit`, account-scoped edits (reordering,
  song add/remove) layered over folder-derived playlists without mutating
  the catalog.
- [`playlists/playlist_edit_reconcile.dart`](../lib/services/playlists/playlist_edit_reconcile.dart)
  — `reconcilePlaylistSongIds`, merges a base (catalog) song-ID list with a
  user's edit against the currently-live song set.
- [`playlists/created_playlist_id.dart`](../lib/services/playlists/created_playlist_id.dart)
  — identity scheme for playlists a client created from scratch (no catalog
  base entry — an empty base snapshot stored purely as a playlist edit, so it
  syncs across a user's devices the same way).
- [`playlists/playlist_image_store.dart`](../lib/services/playlists/playlist_image_store.dart)
  — `PlaylistImageStore`/`PlaylistImageInfo`, custom per-playlist cover
  images.
- [`license/license_file_store.dart`](../lib/services/license/license_file_store.dart)
  — `LicenseFileStore`, persists a small opaque client-uploaded license file
  that the server relays verbatim (never inspects) to other devices; clients
  verify it themselves.
- [`license/license_key_activator.dart`](../lib/services/license/license_key_activator.dart)
  — calls an external license-activation HTTP endpoint (base URL overridable
  via `--dart-define=ARIAMI_LICENSE_WORKER=...`).

## `services/reset/`

- [`reset_service.dart`](../lib/services/reset/reset_service.dart) —
  `ResetService`/`ResetPlan`. `ResetScope.setupOnly` clears only setup/config
  and pairing state; `ResetScope.factoryReset` clears all Ariami-owned data
  (database, accounts, sessions, caches, setup state) — but a `ResetPlan`
  only ever lists explicit leaf files/directories/SQLite DBs to remove, never
  walks to a parent directory, and never touches the user's music files
  (`musicFolderPathGuard` blocks any overlap).

## `services/search/`

- [`library_search_engine.dart`](../lib/services/search/library_search_engine.dart)
  — the ranking engine: `SearchMatchTier` (`exact` > `fieldPrefix` >
  `tokenPrefix` > `substring` > `fuzzy` > transliteration/keyboard-layout
  match), used so every consuming app ranks search results identically.
- [`search_normalizer.dart`](../lib/services/search/search_normalizer.dart) —
  text normalization: lowercasing, diacritic folding, Cyrillic
  transliteration, keyboard-layout correction (e.g. `rbyj` → `кино`).
- [`search.dart`](../lib/services/search/search.dart) — barrel export of the
  two files above.

## `services/setup/`

- [`music_folder_path_helper.dart`](../lib/services/setup/music_folder_path_helper.dart)
  — `MusicFolderPathError` enum + validation for a candidate music-library
  path (empty/missing/etc.) used by the setup endpoints.

## `utils/`

- [`mojibake_repair.dart`](../lib/utils/mojibake_repair.dart) — repairs
  UTF-8-decoded-as-Latin-1 "mojibake" in tag text (e.g. `Ã¡` → `á`), a common
  side effect of legacy ID3v1 fields.
- [`text_sanitizer.dart`](../lib/utils/text_sanitizer.dart) —
  `sanitizeTagText`, strips invisible control/format characters (including
  NUL terminators from padded ID3v1 fields) and trims tag text.
- [`secure_file_permissions.dart`](../lib/utils/secure_file_permissions.dart)
  — `SecureFilePermissions`, best-effort `chmod`-based hardening (Unix only;
  no-op on Windows) for files/directories holding auth secrets.

## Feature flags

[`models/feature_flags.dart`](../lib/models/feature_flags.dart) defines
`AriamiFeatureFlags`, all defaulting to `false`:

- `enableV2Api` — registers the `/api/v2/*` sync routes.
- `enableCatalogWrite` / `enableCatalogRead` — whether `LibraryManager`
  writes to / reads from the SQLite catalog database.
- `enableArtworkPrecompute` — precompute artwork size variants at scan time.
- `enableDownloadJobs` — registers the `/api/v2/download-jobs*` routes
  (only takes effect when `enableV2Api` is also on).
- `enableApiScopedAuthForCliWeb` — narrows the CLI web dashboard's own
  session to API-only scope.

Hosts (e.g. `ariami_cli`'s `ServerFeatureFlagService`) load these from the
environment and pass them to `AriamiHttpServer.setFeatureFlags(...)` and
`LibraryManager.setFeatureFlags(...)`.

## Singletons

Three services use the singleton pattern (`factory X() => _instance`), so
every part of a hosting app that calls `LibraryManager()`,
`AriamiHttpServer()`, `AuthService()`, or `StreamTracker()` gets the same
instance:

- `LibraryManager` ([`lib/services/library/library_manager.dart`](../lib/services/library/library_manager.dart))
- `AriamiHttpServer` ([`lib/services/server/http_server.dart`](../lib/services/server/http_server.dart))
- `AuthService` ([`lib/services/auth/auth_service.dart`](../lib/services/auth/auth_service.dart))
- `StreamTracker` ([`lib/services/server/stream_tracker.dart`](../lib/services/server/stream_tracker.dart))
