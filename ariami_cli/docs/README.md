# Ariami CLI Documentation

This is the documentation set for `ariami_cli`, the headless/server variant
of Ariami. Everything here is verified against the actual Dart source in
`bin/` and `lib/`, the Dockerfile in `docker/`, and the launcher scripts in
this package — no invented flags, paths, ports, or behaviors.

## Start here

- **[`OVERVIEW.md`](OVERVIEW.md)** — what Ariami CLI is, who it's for, how
  it relates to `ariami_core` and to the Ariami Mobile client, and what
  platforms it targets.
- **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** — the centerpiece of this
  set: symptom → likely cause → how to confirm → fix, for startup failures,
  port conflicts, music library problems, connectivity, auth/pairing,
  database corruption, Docker pitfalls, Raspberry Pi specifics,
  performance, transcoding, and logging.

## Reference

- **[`CLI_REFERENCE.md`](CLI_REFERENCE.md)** — every command and flag,
  taken directly from the argument parser, plus exit codes.
- **[`CONFIGURATION.md`](CONFIGURATION.md)** — the data directory layout,
  every `config.json` key, every environment variable, and the Raspberry
  Pi/storage-based runtime tuning tables.
- **[`INSTALLATION.md`](INSTALLATION.md)** — a decision-tree guide to
  picking the right install/deployment path and linking to the detailed
  guide for it.
- **[`FAQ.md`](FAQ.md)** — short, source-verified answers to common
  questions.

## Existing guides in this package

These already exist alongside this `docs/` folder and are not duplicated
here — the reference docs above link into them where relevant:

- [`../HEADLESS.md`](../HEADLESS.md) — the primary SSH/Raspberry Pi/NAS/
  homelab install and operations guide.
- [`../README.md`](../README.md) — package-level quick start.
- [`../REBUILD.md`](../REBUILD.md) — building from source, rebuilding the
  web UI, and cross-compiling Raspberry Pi releases.
- [`../SETUP.txt`](../SETUP.txt) — condensed plain-text install/usage sheet.
- [`../docker/DOCKER.md`](../docker/DOCKER.md) — Docker/Compose build,
  run, networking, and security notes.
