# Ariami Desktop Documentation

Documentation for the `ariami_desktop` package: the graphical, self-hosted
music **server** app for macOS, Windows, and Linux. This is developer/operator
documentation for this package specifically — for the project as a whole, see
the repository root `README.md` and `GUIDE.md`, and for the package's own
quick-start, see `../README.md` (the existing top-level README for this
package, left as-is).

## Contents

- **[OVERVIEW.md](OVERVIEW.md)** — What Ariami Desktop actually is (a GUI
  music-streaming *server*, not a playback client), who it's for, what it
  does, the desktop platforms it builds for, and how it relates to
  `ariami_core` and the mobile client.
- **[FEATURES.md](FEATURES.md)** — A walkthrough of the real screens, tabs,
  and dialogs: the setup wizard and the four-tab dashboard (Overview,
  Activity, Users, Server).
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — The centerpiece of this
  documentation set. Symptom → likely cause → how to confirm → fix, covering
  launch/crash issues, server start and port binding, folder selection and
  library scanning, macOS entitlements/permissions, Windows firewall,
  Linux dependencies, transcoding, phone pairing and network issues,
  Tailscale, owner/account/password errors (including a real client-vs-server
  password-length mismatch), rate limiting, Spotify import failures, the
  system tray, where logs and data actually live, and resetting/reinstalling.
- **[BUILDING.md](BUILDING.md)** — Building from source: prerequisites per
  platform (macOS, Windows, Linux), the optional Rust-based Sonic transcoder
  submodule, and running tests.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — How this GUI layer drives the
  `ariami_core` server engine: what the desktop-specific services add, and
  why the dashboard talks to its own embedded server over plain HTTP rather
  than calling into it directly.

## Scope

This documentation covers only `ariami_desktop` — the GUI server app in this
repository (see its own description in `ariami_desktop/pubspec.yaml`:
*"Ariami Desktop - Music streaming server with GUI"*).

Every claim in these documents is grounded in and cited to real file paths
under `ariami_desktop/` (or the sibling `ariami_core/` package where the
desktop app calls into shared logic), so you can verify anything here against
the actual source.
