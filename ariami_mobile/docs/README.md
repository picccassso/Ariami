# Ariami Mobile documentation

Documentation for the `ariami_mobile` package — the iOS/Android streaming
client for a self-hosted Ariami server. Everything here is verified directly
against the source in `lib/`, `ios/Runner/Info.plist`,
`android/app/src/main/AndroidManifest.xml`, and `pubspec.yaml`; each claim
cites the file it came from so you can check it yourself.

For a quick summary and basic build commands, see the package's top-level
[`../README.md`](../README.md). This folder goes deeper.

## Contents

- **[OVERVIEW.md](OVERVIEW.md)** — What Ariami Mobile is, who it's for, and
  how it discovers and connects to an Ariami server.
- **[SETUP.md](SETUP.md)** — Step-by-step first-run setup guide, screen by
  screen.
- **[FEATURES.md](FEATURES.md)** — Feature walkthrough grounded in the real
  screens and services under `lib/`.
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — The centerpiece of this
  folder: symptom → likely cause → how to confirm → fix, covering
  connection/pairing failures, Wi‑Fi/cellular drops, iOS local-network
  permission, Android cleartext networking, playback stalls, background
  playback, downloads/offline mode, storage, artwork, library sync, and how
  to gather logs or reset the app.
- **[BUILDING.md](BUILDING.md)** — Building from source: prerequisites,
  the vendored `just_audio` equalizer fork, and Android/iOS signing notes.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — How the client talks to the
  server: the HTTP API, the WebSocket real-time channel, the connection
  module breakdown, and local persistence.

## Scope

This documents the `ariami_mobile` client only.
