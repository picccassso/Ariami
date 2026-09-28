# Ariami Mobile

Mobile client for Ariami. Streams music from Ariami Desktop, CLI, or Docker servers.

## Features

- Stream and download music for offline playback, with a manual offline mode and automatic auto-offline on connection loss
- Background playback with lock screen controls, and gapless playback between tracks
- Queue management, shuffle, repeat, and play next
- 5-band equalizer with nine built-in presets and your own saved curves (native on both Android and iOS)
- Google Cast (Chromecast) and **Ariami Connect** (playback transfer/mirroring between your own signed-in clients)
- Playlist creation and management, including server-synced playlists with non-destructive edits
- Search across albums, songs, and playlists
- Artist pages with custom artist photos that sync to your account
- Pin favourite albums and playlists, and keep a Liked Songs playlist
- QR code scanning for easy server connection, with manual address entry and invite codes as a fallback
- User authentication (login/register) when the server has auth enabled
- Automatic quality switching based on network type (WiFi vs mobile data)
- Option to prefer local/cached files when connected to the server
- Listening stats for songs, albums, and artists, synced to your account
- Theming: system/light/dark, preset or custom accent colours, and cover-art-derived colours
- Backup and restore of playlists and stats to a JSON file
- Ariami TV licence activation (Android only)

## Building

Build from inside a full checkout of the monorepo: this package depends on
`ariami_core` by relative path and will not resolve on its own.

```bash
cd ariami_mobile
flutter pub get
flutter run                 # Development
flutter build apk           # Android
flutter build appbundle     # Android (Play Store)
flutter build ios           # iOS
```

`flutter pub get` also picks up the two vendored forks in `third_party/`: a
`just_audio` fork that adds the iOS/macOS equalizer, and a
`flutter_chrome_cast` fork that accepts receiver audio tracks without a
`trackContentType`. See [docs/BUILDING.md](docs/BUILDING.md) for
prerequisites and signing notes.

## Usage

1. Launch the app and tap through the welcome and network-check screens
2. Scan the QR code from your Ariami server, or enter its address manually
3. If auth is required, create an account or log in
4. Grant notification and storage permissions when prompted (both skippable)
5. Browse and stream your music library

## Documentation

Deeper docs live in [`docs/`](docs/README.md): an
[overview](docs/OVERVIEW.md), a [feature walkthrough](docs/FEATURES.md), a
[first-run setup guide](docs/SETUP.md), [architecture
notes](docs/ARCHITECTURE.md), [build instructions](docs/BUILDING.md), and a
detailed [troubleshooting guide](docs/TROUBLESHOOTING.md).
