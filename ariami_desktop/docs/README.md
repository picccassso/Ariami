# Ariami Desktop Documentation

Documentation for the `ariami_desktop` package: the graphical, self-hosted
music **server** app for macOS, Windows, and Linux. This is developer and
operator documentation for this package specifically. For the project as a
whole, see the repository root `README.md` and `GUIDE.md`, and for a quick
start with this package, see `../README.md`.

## Contents

- **[OVERVIEW.md](OVERVIEW.md)**: what Ariami Desktop is (a GUI
  music-streaming server), who it's for, what it does, the desktop platforms
  it builds for, and how it relates to `ariami_core` and the client apps.
- **[FEATURES.md](FEATURES.md)**: a walkthrough of the real screens, tabs,
  and dialogs: the setup wizard, the four-tab dashboard (Overview, Activity,
  Users, Server), Ariami TV licence activation, and the Spotify import and
  removal flows.
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: symptom, likely cause, how to
  confirm it, and the fix, covering launch and crash issues, server start and
  port binding, folder selection and library scanning, macOS entitlements and
  permissions, Windows firewall, Linux dependencies, transcoding, phone
  pairing and network issues, Tailscale, owner/account/password errors
  (including a client-versus-server password-length mismatch), rate limiting,
  Spotify import failures, the system tray, where logs and data live, and
  resetting or reinstalling.
- **[BUILDING.md](BUILDING.md)**: building from source, with prerequisites
  per platform (macOS, Windows, Linux), the Rust-based Sonic transcoder
  submodule, and running tests.
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: how this GUI layer drives the
  `ariami_core` server engine, what the desktop-specific services add, and
  how the dashboard talks to its own embedded server over plain HTTP.

## Scope

These documents cover only `ariami_desktop`, the GUI server app in this
repository. See its own description in `ariami_desktop/pubspec.yaml`:

> Ariami Desktop - Music streaming server with GUI

Every claim here is grounded in and cites real file paths under
`ariami_desktop/` (or the sibling `ariami_core/` package where the desktop app
calls into shared logic), so you can verify anything against the source.
