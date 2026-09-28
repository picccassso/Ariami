# What is Ariami Mobile?

Ariami Mobile is the iOS/Android streaming client for a self-hosted Ariami
music server. It is a Flutter app (`ariami_mobile`) that connects over your
local network, or over [Tailscale](https://tailscale.com) when you're away
from home, to an **Ariami Desktop app/server** (macOS/Windows/Linux), an
**Ariami CLI / headless server** (Raspberry Pi, Linux, macOS, Windows, or
Docker), or a server you expose through your own HTTPS public origin. The
server owns your music files; the phone streams, caches, and optionally
downloads from it.

This document is a factual tour of what's in the code under `lib/`. Every
claim below points at a source file so you can check it yourself.

## Who it's for

Anyone running their own Ariami server who wants to listen on a phone: at
home over Wi‑Fi, or remotely over Tailscale. Accounts, playlists, and
listening history all live on the server you run. Connection state,
credentials, and caches live on the phone and on the server you pair it
with, and the app sends no telemetry to anyone.

The mobile client and the core library (`ariami_core`) are free and open
source.

## How it discovers and connects to a server

Setup starts at `lib/screens/welcome_screen.dart`, which routes to
`/setup/tailscale` (`lib/screens/setup/tailscale_check_screen.dart`). That
screen explains the two ways to reach a server (same Wi‑Fi network, or
Tailscale for remote access) and offers to open the Tailscale app-store
listing if it isn't detected
(`lib/services/mobile_tailscale_service.dart`). Tailscale is optional; you
can continue to the scanner regardless of its status.

From there the app can learn about a server two ways:

1. **QR code scan** (`lib/screens/setup/qr_scanner_screen.dart`, via the
   `mobile_scanner` package). The desktop/CLI server displays a QR code
   encoding a JSON payload (host, port, optional LAN/Tailscale addresses,
   auth state, and sometimes a short-lived registration token). It is
   parsed and strictly validated by
   `lib/utils/qr_payload_parser.dart`: every field is type- and
   range-checked before a `ServerInfo` is built, and error messages never
   echo the scanned payload back (it can carry a token).
2. **Manual entry** (`lib/screens/setup/manual_server_entry_screen.dart`),
   for when a QR code isn't available. You type a host[:port] (for example
   `192.168.1.50:8080` or `https://myserver.example.com`), parsed by
   `lib/utils/server_address_parser.dart`. The app then calls the server's
   public `/api/server-info` endpoint to discover its name, version, and
   auth mode, and optionally accepts an invite code for account creation.

Both flows converge on `lib/screens/setup/server_connection_router.dart`,
which decides where to go next based on the server's reported state:

- Server has registered users (`authRequired && !legacyMode`): sign in at
  `LoginScreen`.
- Server has no users yet (`legacyMode`): create the first (owner) account
  at `RegisterScreen`.
- No auth required: connect immediately and continue to the permissions
  screen.

Once connected, the app can juggle up to three addresses for the same
server (`server` (primary), `lanServer`, and `tailscaleServer` in
`lib/models/server_info.dart`), and a background `EndpointResolver`
(`lib/services/api/endpoint_resolver.dart`) prefers the LAN address whenever
it's reachable, falling back to the Tailscale/primary address otherwise, and
re-probes every 15 seconds or on network changes. A server reached through
an explicit HTTPS `publicOrigin` keeps that origin: the resolver never
downgrades it to a cleartext LAN or Tailscale address. A saved connection
also survives app restarts: server address, session, and device ID are
persisted (`lib/services/api/connection/connection_persistence_manager.dart`,
`flutter_secure_storage` for the session token), so the app reconnects
automatically the next time it launches.

## What it does

- **Streams music** from the server over HTTP, with a stream-quality picker
  per network type (Wi‑Fi vs. mobile data): see
  `lib/models/quality_settings.dart` and
  `lib/services/quality/quality_settings_service.dart`.
- **Downloads songs for offline playback**, tracked in a persistent queue
  with retries, pause/resume, and a background transfer backend on Android
  (`lib/services/download/`).
- **Plays audio in the background** with lock-screen/notification controls
  via `audio_service` + `just_audio` (`lib/services/audio/audio_handler.dart`).
- **Casts and remote-controls playback** via Google Cast
  (`lib/services/cast/chrome_cast_service.dart`) and **Ariami Connect**, a
  cross-device playback handoff/mirroring system built on
  `package:ariami_core/services/connect`
  (`lib/services/ariami_connect_controller.dart`).
- **Keeps the library in sync** with the server over a WebSocket connection
  (`lib/services/api/websocket_service.dart`) that pushes library, playlist,
  and pin updates live, plus pull-to-refresh
  (`lib/screens/main/library/library_controller_sync.dart`).
- **Manages playlists**, both device-local playlists and (when signed in)
  server-synced playlists with non-destructive edits
  (`lib/services/playlist_service*.dart`).
- **Browses the library** with artist pages, genre filters, pinned albums
  and playlists, and a Liked Songs playlist
  (`lib/screens/artist_detail_screen.dart`,
  `lib/services/library/library_genre_index.dart`).
- **Tracks listening stats** (song/artist/album play counts and time) stored
  locally in SQLite and, for signed-in accounts, mirrored to the server for
  cross-device stats (`lib/services/stats/`).
- **Suggests new music** through Last.fm-backed discovery when you turn it
  on (`lib/screens/settings/music_discovery_screen.dart`).

## What it needs from the server

Ariami Mobile is a pure client. It talks to the Ariami server's HTTP API
(`/api/...`, see `lib/services/api/api_client.dart`) for
connect/auth/library/stream/download endpoints, and to its WebSocket
endpoint (`/api/ws`) for live updates. The server scans the filesystem,
builds and syncs the library, and does any transcoding; the phone streams,
caches, or downloads the result. Your music library stays on the server,
apart from the local song cache and any files you explicitly download.
