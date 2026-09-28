# Ariami CLI Documentation

This is the documentation set for `ariami_cli`, the headless/server variant
of Ariami. Everything here is checked against the Dart source in `bin/` and
`lib/`, the Dockerfile in `docker/`, and the launcher scripts in this
package, so the flags, paths, ports, and behaviours match the code.

## Start here

- **[`OVERVIEW.md`](OVERVIEW.md)**: what Ariami CLI is, who it's for, how it
  relates to `ariami_core` and to the Ariami Mobile client, and what
  platforms it targets.
- **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)**: the centrepiece of this
  set. A symptom → likely cause → how to confirm → fix walkthrough covers
  startup failures, port conflicts, music library problems, connectivity,
  auth/pairing, database corruption, Docker pitfalls, Raspberry Pi
  specifics, performance, transcoding, and logging.

## Reference

- **[`CLI_REFERENCE.md`](CLI_REFERENCE.md)**: every command and flag, taken
  directly from the argument parser, plus exit codes.
- **[`CONFIGURATION.md`](CONFIGURATION.md)**: the data directory layout,
  every `config.json` key, every environment variable, and the Raspberry
  Pi/storage-based runtime tuning tables.
- **[`INSTALLATION.md`](INSTALLATION.md)**: a decision-tree guide that helps
  you pick the right install/deployment path and links to the detailed guide
  for it.
- **[`FAQ.md`](FAQ.md)**: short, source-verified answers to common
  questions.

## Shared behaviour documented in Core

- **[`ariami_core/docs/LISTENING_STATS.md`](../../ariami_core/docs/LISTENING_STATS.md)**:
  what counts as a play and as listened time, how that differs from
  Spotify's counting, and the full Spotify Extended Streaming History import
  pipeline. The CLI's web dashboard exposes the same import and removal
  (`lib/web/services/spotify_import_service.dart`), and the engine behind it
  lives in `ariami_core`, so the rules are identical to the desktop app's.

## Existing guides in this package

These guides already live alongside this `docs/` folder, so the reference
docs above link into them where relevant instead of repeating them:

- [`../HEADLESS.md`](../HEADLESS.md): the primary SSH/Raspberry Pi/NAS/
  homelab install and operations guide.
- [`../README.md`](../README.md): package-level quick start.
- [`../REBUILD.md`](../REBUILD.md): building from source, rebuilding the
  web UI, and cross-compiling Linux releases.
- [`../SETUP.txt`](../SETUP.txt): condensed plain-text install/usage sheet.
- [`../docker/DOCKER.md`](../docker/DOCKER.md): Docker/Compose build,
  run, networking, and security notes.
