# Ariami Core Documentation

Developer documentation for the `ariami_core` package — the shared,
platform-agnostic Dart library that powers `ariami_cli`, `ariami_desktop`,
and `ariami_mobile`. Everything here was written by reading the actual Dart
source under [`../lib`](../lib) and the tests under [`../test`](../test); file
paths are linked throughout so you can verify any claim directly.

For the package's own quick-start summary, see [`../README.md`](../README.md)
(package overview, usage snippet, `dart test` / `dart analyze` commands).

## Contents

- **[OVERVIEW.md](OVERVIEW.md)** — What Ariami Core is, its role as the
  shared server/library engine, what it provides at a glance, and how
  `ariami_cli`, `ariami_desktop`, and `ariami_mobile` each depend on it.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — A full walk of the `lib/`
  directory tree: every service directory, the key classes in each file, the
  `LibraryManager` singleton and its `part` files, the `AriamiHttpServer`
  singleton and its `http_server_parts/`, feature flags, and the WebSocket
  message vocabulary.
- **[API_REFERENCE.md](API_REFERENCE.md)** — The complete HTTP route table
  (grouped by area, with auth/feature-flag gating noted) and the `/api/ws`
  WebSocket message types, read directly from
  `router_registration_part.dart`.
- **[DATA_AND_PERSISTENCE.md](DATA_AND_PERSISTENCE.md)** — Every file and
  SQLite database `ariami_core` creates (catalog database schema and
  migrations, listening-stats schema, the JSON-file auth/cache stores, and
  why pins/playlist-edits/playlist-images are deliberately kept separate
  from the catalog).
- **[TESTING.md](TESTING.md)** — How to run tests and analysis, the shape of
  `test/`, the in-process HTTP test helper, and what to check before
  changing shared behavior that every consuming app relies on.

## Also in this package (not duplicated here)

- **[`../README.md`](../README.md)** — the package's own top-level overview
  and usage guide.
- **[`../PLAYLIST_DETECTION.md`](../PLAYLIST_DETECTION.md)** — the detailed
  rules for how the scanner decides what is an album, an explicit playlist,
  an auto-imported playlist, or an advisory suggestion.

## Scope note

This documentation covers `ariami_core` only, as consumed by the public
parts of the Ariami monorepo: `ariami_cli` (headless/CLI server),
`ariami_desktop` (the desktop server GUI), `ariami_mobile` (mobile client),
and the `sonic` submodule (native transcoding). It does not describe any
other, non-public client applications.
