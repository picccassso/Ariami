Basic Music App (BMA)

BMA is a cross-platform personal music system built with Flutter.
It lets you host and stream your own music library across devices.

The setup includes:

-Desktop App (macOS, Linux, Windows): acts as a local server that indexes your music and shares it through Tailscale.

-Mobile App (Android, iOS): connects to the desktop server, lets you browse, play, and manage your library.

Features:

- Syncs your music library between desktop and mobile
- Album and playlist management with metadata-based organization
- Real-time updates when your music folder changes
- Duplicate filtering
- Offline playback and streaming stats
- Simple, Spotify-like UI with library, search, and settings tabs

Tech stack:

-Flutter (cross-platform)
-Tailscale (secure device-to-device connectivity)
-Server-client architecture (desktop = server, mobile = client)