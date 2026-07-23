# What is Ariami Core?

`ariami_core` (package name `ariami_core`, see [`pubspec.yaml`](../pubspec.yaml)) is
the shared, platform-agnostic Dart library at the center of the Ariami
monorepo. It has **no Flutter dependency** — it is pure Dart (`environment.sdk:
^3.5.0` in `pubspec.yaml`) — so it can run anywhere the Dart VM runs, including
headless servers with no display and no Flutter engine.

Ariami itself is a self-hosted music server: one machine scans a music folder,
serves it over HTTP/WebSocket, and any number of client apps on the same
network (or over Tailscale) connect to stream from it. `ariami_core` is the
engine that every one of those server-hosting apps embeds; it is not a
runnable app by itself.

## Role in the monorepo

The repository root README and the individual app packages describe four
public pieces built on top of this library:

- **`ariami_cli`** — a headless/CLI server (`description: CLI version of
  Ariami for headless servers`, [`ariami_cli/pubspec.yaml`](../../ariami_cli/pubspec.yaml)).
  It depends on `ariami_core` via a path dependency and its
  [`lib/server_runner.dart`](../../ariami_cli/lib/server_runner.dart) directly
  instantiates and wires up `AriamiHttpServer()` and `LibraryManager()` from
  this package. It adds its own CLI argument parsing, a served Flutter-web
  dashboard (`lib/web/`), and OS-level daemon/service management — none of
  which live in `ariami_core`.
- **`ariami_desktop`** — the desktop server GUI (`description: "Ariami Desktop
  - Music streaming server with GUI"`,
  [`ariami_desktop/pubspec.yaml`](../../ariami_desktop/pubspec.yaml)). It is a
  Flutter desktop app that hosts the same `ariami_core` server stack behind a
  native settings/dashboard UI, again via a path dependency.
- **`ariami_mobile`** — the mobile client (`description: "Ariami Mobile -
  Music streaming client"`,
  [`ariami_mobile/pubspec.yaml`](../../ariami_mobile/pubspec.yaml)). Unlike the
  two server hosts above, it is primarily a *consumer* of the HTTP/WebSocket
  API `ariami_core` exposes, but it also depends on `ariami_core` directly
  (path dependency) to reuse shared models and the deterministic
  [`library_search_engine.dart`](../lib/services/search/library_search_engine.dart)
  so search ranking behaves identically across apps.
- **`sonic`** — a git submodule (see [`../.gitmodules`](../.gitmodules) at the
  repo root) providing the native Sonic library used for MP3 → AAC
  transcoding. `ariami_core`'s
  [`lib/services/transcoding/transcoding_service.dart`](../lib/services/transcoding/transcoding_service.dart)
  loads it through Dart FFI
  (`lib/services/transcoding/src/transcoding_service_ffi.dart`).

All three Dart/Flutter apps add `ariami_core` the same way, in their own
`pubspec.yaml`:

```yaml
dependencies:
  ariami_core:
    path: ../ariami_core
```

## What it actually provides

Everything below is exported from the single library entry point,
[`lib/ariami_core.dart`](../lib/ariami_core.dart), and grouped by directory
under `lib/`:

- **An HTTP + WebSocket server** — [`services/server/http_server.dart`](../lib/services/server/http_server.dart)
  (`AriamiHttpServer`, singleton) builds a `shelf`/`shelf_router` router
  covering setup, auth, library, streaming, download, listening-stats, pins,
  playlists, Connect (remote playback), admin, and a `/api/ws` WebSocket
  upgrade route. See [`API_REFERENCE.md`](API_REFERENCE.md) for the full
  endpoint list.
- **Music metadata extraction** — [`services/library/metadata_extractor.dart`](../lib/services/library/metadata_extractor.dart)
  reads ID3/Vorbis tags via the `dart_tags` package, plus a hand-written pure
  Dart MP3 duration parser
  ([`services/library/mp3_duration_parser.dart`](../lib/services/library/mp3_duration_parser.dart))
  that avoids pulling in a native MP3 decoder just to find track length.
- **Library scanning and organization** — recursive file discovery
  ([`services/library/file_scanner.dart`](../lib/services/library/file_scanner.dart)),
  isolate-parallel scanning
  ([`services/library/library_scanner_isolate.dart`](../lib/services/library/library_scanner_isolate.dart)),
  album grouping/compilation detection
  ([`services/library/album_builder.dart`](../lib/services/library/album_builder.dart),
  `album_grouping.dart`, `album_identity.dart`), duplicate detection
  ([`services/library/duplicate_detector.dart`](../lib/services/library/duplicate_detector.dart)),
  a real-time filesystem watcher and change pipeline
  ([`services/library/folder_watcher.dart`](../lib/services/library/folder_watcher.dart),
  `change_processor.dart`), and the playlist-detection system documented in
  [`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md).
- **Models** — request/response and domain types under
  [`lib/models/`](../lib/models) (albums, songs, library structure, scan
  results, auth, Connect, sync/v2, listening stats, WebSocket messages, etc.).
- **Services** organized by domain under [`lib/services/`](../lib/services):
  `auth/`, `catalog/`, `connect/`, `discovery/`, `library/`, `license/`,
  `pins/`, `playlists/`, `reset/`, `search/`, `server/`, `setup/`, `stats/`,
  `transcoding/`, `artwork/`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the
  full walk-through.

## Why a shared, Flutter-free core

The existing [`../README.md`](../README.md) and the code agree on the
motivation: the same server logic needs to run identically whether it is
hosted from a Flutter desktop GUI or from a bare CLI process on a headless
box (e.g. a Raspberry Pi — `ariami_cli`'s
[`lib/services/server_lifecycle_service.dart`](../../ariami_cli/lib/services/server_lifecycle_service.dart)
and `server_runner.dart` explicitly branch on Pi detection for cache/download
tuning). Keeping `ariami_core` pure Dart means:

- It has no Flutter engine to start, so it starts faster and uses less memory
  as a background/daemon process.
- The exact same `AriamiHttpServer`, `LibraryManager`, `AuthService`, etc. run
  under both `ariami_cli` and `ariami_desktop` — there is one server
  implementation, not two that must be kept in sync.
- `ariami_mobile` can import the same models and the same search engine as
  the servers without pulling in server-side code it doesn't run.

## Versioning

Per [`pubspec.yaml`](../pubspec.yaml), `ariami_core` is currently at
`version: 5.0.0`. The same number is exposed at runtime as `kAriamiVersion` in
[`lib/app_version.dart`](../lib/app_version.dart), which documents itself as
needing to stay in sync with `ariami_core/pubspec.yaml` and
`ariami_cli/pubspec.yaml`.
