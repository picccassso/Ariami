# Testing Guide

## Running tests

From the package root:

```bash
cd ariami_core
dart test
```

Static analysis:

```bash
dart analyze
```

[`analysis_options.yaml`](../analysis_options.yaml) includes
`package:lints/recommended.yaml` and additionally enables `avoid_print`,
`prefer_single_quotes`, and `always_declare_return_types`.

Test-only dependencies, from [`pubspec.yaml`](../pubspec.yaml):
`test: ^1.31.1`, `stream_channel: ^2.1.4`, plus `lints: ^6.1.0` for analysis.

## Layout

`test/` mirrors `lib/`, plus a top-level `test/integration/` for
cross-service tests:

```
test/
├── credited_artist_splitter_test.dart
├── listening_event_outbox_test.dart
├── listening_event_tracker_test.dart
├── listening_stats_models_test.dart
├── listening_stats_store_test.dart
├── period_stats_overlay_test.dart
├── integration/
│   ├── download_benchmark_test.dart
│   ├── multi_user_stream_test.dart
│   ├── phase3_scanner_change_pipeline_test.dart
│   └── v2_sync_multi_user_test.dart
├── models/
│   ├── connect_models_test.dart
│   ├── scan_diagnostics_test.dart
│   ├── server_origin_test.dart
│   └── sync_models_test.dart
├── services/
│   ├── artwork/artwork_service_cache_policy_test.dart
│   ├── auth_service_test.dart
│   ├── session_store_test.dart
│   ├── stream_tracker_test.dart
│   ├── catalog/ (catalog_database_test.dart, catalog_repository_test.dart, catalog_writer_test.dart)
│   ├── connect/ (connect_hub_test.dart, connect_client_integration_test.dart,
│   │             connect_clear_queue_integration_test.dart, remote_playback_test.dart)
│   ├── discovery/ (discovery_browser_test.dart, discovery_responder_test.dart, dns_wire_test.dart)
│   ├── library/ (17 files — scanner, album grouping/art detection, change processor,
│   │             duplicate detector, M3U parser, metadata cache/extractor, natural path
│   │             order, playlist decisions/classifier, scan behavior audit, etc.)
│   ├── license/ (license_file_store_test.dart, license_key_activator_test.dart)
│   ├── pins/pinned_item_store_test.dart
│   ├── playlists/ (created_playlist_id_test.dart, playlist_edit_store_test.dart,
│   │               playlist_image_store_test.dart)
│   ├── reset/reset_service_test.dart
│   ├── search/library_search_engine_test.dart
│   ├── server/ (18 files — connection manager, device names, download jobs, and a
│   │           large `http_server_*_test.dart` group covering auth/users, avatars,
│   │           CLI-web auth, license, listening-reset, music-folder setup, owner
│   │           bootstrap, pins, playlist suggestions, port fallback, server-info,
│   │           and v2 endpoints — plus network/port-policy/response-compression/
│   │           streaming/tailscale tests)
│   ├── setup/music_folder_path_helper_test.dart
│   ├── stats/ (spotify_reset_test.dart, spotify_import/ — history parser, track
│   │           matcher, event builder)
│   └── transcoding/ (transcode_slots_policy_test.dart,
│                      transcoding_service_cache_policy_test.dart)
└── utils/mojibake_repair_test.dart
```

## Testing an `AriamiHttpServer` in-process

[`test/services/server/http_server_test_support.dart`](../test/services/server/http_server_test_support.dart)
provides `startHttpTestServer(server, {advertisedIp, bindAddress})`, which
binds port `0` (an OS-assigned ephemeral port) directly rather than probing a
free port and racing another process for it — the doc comment notes this
exists specifically to avoid that race — and returns the actual bound port
via `server.getServerInfo()['port']`. The many `http_server_*_test.dart`
files under `test/services/server/` use this helper to exercise real routes
end-to-end against a live `AriamiHttpServer()` singleton instance.

Because `AriamiHttpServer`, `LibraryManager`, `AuthService`, and
`StreamTracker` are singletons, tests that touch them need to reset relevant
state between cases — `AuthService.resetForTesting()`, and
`AriamiHttpServer.initializeAuth(..., forceReinitialize: true)`, are the
mechanisms visible in `lifecycle_and_config_part.dart` for this. `LibraryManager`
similarly exposes `setLibraryForTesting(...)` to inject a `LibraryStructure`
directly.

## Integration tests

`test/integration/` covers behavior that spans multiple services rather than
one unit:

- **`multi_user_stream_test.dart`** — concurrent streaming across multiple
  authenticated users (`UserStore`, `SessionStore`, `ConnectionManager`,
  `StreamTracker` together).
- **`phase3_scanner_change_pipeline_test.dart`** — the full scan →
  catalog-write → incremental-change pipeline, using a real
  `CatalogDatabase`/`CatalogRepository` with feature flags enabled.
- **`v2_sync_multi_user_test.dart`** — the `/api/v2/*` sync routes against a
  live `AriamiHttpServer`, using `http_server_test_support.dart`.
- **`download_benchmark_test.dart`** — download-path performance/behavior
  under load.

## What to check before changing shared behavior

Because every consuming app (`ariami_cli`, `ariami_desktop`, `ariami_mobile`)
depends on the exact same singleton services, a behavior change in
`ariami_core` affects every host at once. When editing:

- **Playlist detection** — read [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md)
  first; the auto-import/suggestion thresholds it documents are covered by
  `test/services/library/library_scanner_auto_import_test.dart`,
  `library_scanner_approved_playlist_test.dart`,
  `library_scanner_playlist_test.dart`, and `playlist_folder_classifier_test.dart`.
- **Catalog schema** — any change to
  [`catalog_migrations.dart`](../lib/services/catalog/catalog_migrations.dart)
  must be additive/forward-only (see `CatalogMigrations.currentVersion`) and
  covered by `test/services/catalog/catalog_database_test.dart`.
- **Listening stats rollups** — bump
  `ListeningStatsStore.rollupSchemaVersion` when changing derivation logic so
  existing databases rebuild their rollups on next open; see
  `test/listening_stats_store_test.dart` and
  `test/credited_artist_splitter_test.dart`.
- **HTTP routes** — new routes should be added to the appropriate
  `_registerXxxRoutes` method in
  [`router_registration_part.dart`](../lib/services/server/http_server_parts/router_registration_part.dart)
  and reflected in [`API_REFERENCE.md`](API_REFERENCE.md).
