# Data & Persistence Layer

`ariami_core` itself never chooses where its data files live — the hosting
app (`ariami_cli` or `ariami_desktop`) picks a config directory and passes
explicit file paths in (e.g. `LibraryManager.setCachePath(...)`,
`AriamiHttpServer.initializeAuth(usersFilePath: ..., sessionsFilePath: ...)`).
What follows is what `ariami_core` itself creates *relative to* those paths,
read from the actual initialization code.

## Files derived from the metadata-cache path

`LibraryManager.setCachePath(cachePath)`
([`lib/services/library/library_manager.dart`](../lib/services/library/library_manager.dart))
takes one JSON file path (conventionally `metadata_cache.json`) and derives
everything else from its parent directory:

| Path (relative to the cache file's directory) | Purpose |
|---|---|
| the cache file itself | `MetadataCache` — per-file mtime/size-validated tag cache for fast rescans |
| `artwork_cache/` | `ArtworkService` precomputed artwork-size variants |
| `playlist_decisions.json` | `PlaylistDecisionStore` — import/ignore/reset decisions on suggested playlist folders |
| `catalog.db` | `CatalogDatabase` — the SQLite v2 sync catalog (see below) |

## Files derived from the users-file path

`AriamiHttpServer.initializeAuth(usersFilePath: ..., sessionsFilePath: ...)`
([`lib/services/server/http_server_parts/lifecycle_and_config_part.dart`](../lib/services/server/http_server_parts/lifecycle_and_config_part.dart))
takes the users JSON file path and derives sibling paths from its parent
directory:

| Path (relative to the users file's directory) | Purpose |
|---|---|
| the users file itself | `UserStore` — accounts (bcrypt-hashed passwords) |
| the sessions file (separate argument) | `SessionStore` — sessions, 30-day sliding TTL |
| `user_avatars/` | profile picture storage |
| `device_names.json` | `DeviceNameStore` — user-chosen device display names |
| `listening_stats.db` | `ListeningStatsStore` — per-account listening history (see below) |
| `pinned_items.db` | `PinnedItemStore` — account-scoped pinned albums/playlists |
| `playlist_edits.db` | `PlaylistEditStore` — account-scoped playlist edits |
| `playlist_images.db` | `PlaylistImageStore` — custom playlist cover images |
| `client_license.txt` | `LicenseFileStore` — opaque client-uploaded license file |

Each of these stores is initialized independently and failures are logged
and swallowed rather than blocking server startup — code comments in
`lifecycle_and_config_part.dart` note this explicitly for each one (e.g.
"Failure here must never block auth/startup: stats endpoints will report 503
until the store becomes available").

Auth secrets get extra hardening:
[`utils/secure_file_permissions.dart`](../lib/utils/secure_file_permissions.dart)
best-effort `chmod`-restricts the users/sessions files and their parent
directory on Unix platforms (a no-op on Windows, where per-user profile ACLs
already scope access).

## The catalog database (`catalog.db`)

Opened by [`CatalogDatabase`](../lib/services/catalog/catalog_database.dart)
with `PRAGMA journal_mode=WAL`, `synchronous=NORMAL`, `temp_store=MEMORY`,
`busy_timeout=5000`, `cache_size=-8192`. Schema migrations are forward-only
and versioned via SQLite's `PRAGMA user_version`
([`CatalogMigrations`](../lib/services/catalog/catalog_migrations.dart),
`currentVersion = 5`):

- **v1** creates the base schema:
  - `albums (id, title, artist, year, cover_art_key, song_count, duration_seconds, updated_token, is_deleted)`
  - `songs (id, file_path UNIQUE, title, artist, album_id, duration_seconds, track_number, file_size_bytes, modified_epoch_ms, bitrate_kbps, artwork_key, updated_token, is_deleted)`
  - `playlists (id, name, song_count, updated_token, is_deleted)`
  - `playlist_songs (playlist_id, song_id, position, updated_token)`
  - `artwork_variants (artwork_key, variant, mime_type, byte_size, etag, last_modified_epoch_ms, storage_path, updated_token)`
  - `library_changes (token AUTOINCREMENT, entity_type, entity_id, op, payload_json, occurred_epoch_ms, actor_user_id)` — the append-only log that backs `/api/v2/changes`
  - `download_jobs (job_id, user_id, status, quality, download_original, created_epoch_ms, updated_epoch_ms)`
  - `download_job_items (job_id, item_order, song_id, status, error_code, retry_after_epoch_ms)`
  - plus indexes on `songs(album_id, is_deleted, updated_token)`, `albums(is_deleted, updated_token)`, `library_changes(token)`, `download_jobs(user_id, status)`
- **v2** rebuilds `playlist_songs` with `position` as part of its primary
  key (`PRIMARY KEY (playlist_id, position)`), migrating existing rows.
- **v3** adds `playlists.duration_seconds`.
- **v4** adds `songs.bitrate_kbps`.
- **v5** scrubs invisible/control characters (including NUL terminators left
  by NUL-padded ID3v1 fields) out of previously-written `title`/`artist`
  text on `songs` and `albums`, and `name` on `playlists`, via
  [`utils/text_sanitizer.dart`](../lib/utils/text_sanitizer.dart)'s
  `sanitizeTagText`. Done in Dart (not pure SQL) because SQLite string
  functions treat an embedded NUL as a terminator.

`CatalogWriter` ([`services/catalog/catalog_writer.dart`](../lib/services/catalog/catalog_writer.dart))
upserts from a `LibraryStructure` snapshot and appends the corresponding rows
to `library_changes`. `CatalogRepository`
([`services/catalog/catalog_repository.dart`](../lib/services/catalog/catalog_repository.dart))
is the read side used by `AriamiV2Handlers` and `DownloadJobService`.
`LibraryManager.createCatalogRepository()` is the only way callers obtain a
`CatalogRepository`, and only returns a non-null instance once the catalog
database has actually initialized and either `enableCatalogRead` or
`enableV2Api` is on.

## The listening-stats database (`listening_stats.db`)

Opened by
[`ListeningStatsStore`](../lib/services/stats/listening_stats_store.dart)
(`PRAGMA journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout=5000`).
Raw events are the source of truth; every other table is a disposable,
rebuildable rollup (tracked by `rollup_schema_version` in
`listening_stats_meta`, currently `2`; a stale version triggers a full
rebuild from `listening_events` on startup):

- `listening_events (event_id PK, user_id, device_id, song_id, play_id, listened_ms, plays, occurred_at, tz_offset_min, received_at, song_title, song_artist, album_id, album, album_artist, source_kind, playlist_id, client_kind)`
  — keyed by the client-generated `event_id` so retried/replayed uploads
  never double-count. A unique index on `(user_id, play_id)` (where
  `plays > 0 AND play_id IS NOT NULL`) is a second line of defense: even a
  buggy client re-sending the same play under a fresh `event_id` can only
  register one play per `(user, play_id)`.
- `listening_song_rollups (user_id, song_id, play_count, listened_ms, first_played, last_played, song_title, song_artist, album_id, album, album_artist)` — PK `(user_id, song_id)`
- `song_artist_credits (user_id, song_id, artist_key, artist_display, ordinal)` — derived per-credited-artist split of a song's display artist string (see `CreditedArtistSplitter`); the raw display string on events/rollups is never modified
- `listening_artist_rollups (user_id, artist_key, artist_display, play_count, listened_ms, first_played, last_played)` — PK `(user_id, artist_key)`; every credited artist receives the *full* play/listened-time of an event, never a divided share
- `listening_album_rollups (user_id, album_key, album, album_artist, play_count, listened_ms, first_played, last_played)` — PK `(user_id, album_key)`
- `listening_daily_rollups (user_id, local_day, dim, dim_key, play_count, listened_ms, display, display_extra)` — PK `(user_id, local_day, dim, dim_key)`; a generic local-day grain so any period view (day/week/month/year) is just a range query over these rows — no separate month/year tables. Baseline (Spotify) imports are excluded, since they compress history into a single moment.
- `listening_stats_meta (key PK, value)` — schema-version bookkeeping

## Other durable account data (kept separate from the catalog on purpose)

The pins, playlist-edits, and playlist-images stores each own their own
SQLite database (`pinned_items.db`, `playlist_edits.db`,
`playlist_images.db`) specifically so a library rescan — which rewrites the
catalog — can never remove this account-scoped data:

- [`PinnedItemStore`](../lib/services/pins/pinned_item_store.dart)
- [`PlaylistEditStore`](../lib/services/playlists/playlist_edit_store.dart)
  (`PlaylistEdit`)
- [`PlaylistImageStore`](../lib/services/playlists/playlist_image_store.dart)
  (`PlaylistImageInfo`)

Playlist edits are reconciled against the live catalog at read time by
[`reconcilePlaylistSongIds`](../lib/services/playlists/playlist_edit_reconcile.dart),
not by mutating stored state.

## JSON-file stores

A few smaller, lower-write-volume pieces of state are plain JSON files rather
than SQLite, each with its own atomic-write queue to avoid temp-file rename
collisions:

- `UserStore` (users file) and `SessionStore` (sessions file) — see
  [`services/auth/`](../lib/services/auth).
- `MetadataCache` (`metadata_cache.json`) — per-file cached tags.
- `PlaylistDecisionStore` (`playlist_decisions.json`) — playlist
  suggestion decisions, keyed by absolute folder path (see
  [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md)).
- `DeviceNameStore` (`device_names.json`) — user-chosen device names.

## What `ResetService` is allowed to touch

[`services/reset/reset_service.dart`](../lib/services/reset/reset_service.dart)
never derives paths itself — a caller builds an explicit `ResetPlan` (files,
directories, SQLite database paths) and `ResetService.execute` only removes
exactly those leaf paths, refusing anything that overlaps the configured
music folder (`musicFolderPathGuard`). `ResetScope.setupOnly` vs.
`ResetScope.factoryReset` is a caller-side distinction (a smaller vs. larger
plan), not something `ResetService` decides on its own.
