# Feature walkthrough

A tour of what's implemented in `lib/`, grouped by screen/service, with the
source file for each claim so you can verify it.

## Setup and connection

| Feature | Where |
|---|---|
| Tailscale detection (VPN interface check: `tun`/`tailscale` on Android, `utun` on iOS) with install links | `lib/services/mobile_tailscale_service.dart`, `lib/screens/setup/tailscale_check_screen.dart` |
| QR pairing scanner with torch toggle and camera-permission recovery UI | `lib/screens/setup/qr_scanner_screen.dart` |
| Manual server address entry with optional invite code | `lib/screens/setup/manual_server_entry_screen.dart` |
| Login / first-account registration, matching the server's auth mode | `lib/screens/login_screen.dart`, `lib/screens/register_screen.dart` |
| "Already signed in elsewhere" takeover confirmation before overwriting another device's session | `lib/screens/login_screen.dart` (`_confirmOtherDeviceTakeover`) |
| Post-setup permission requests (notifications, storage/media) with a skip path | `lib/screens/setup/permissions_screen.dart`, `lib/services/permissions_service.dart` |
| Connection diagnostics: active address, LAN address, Tailscale address, port, route label, retry button | `lib/screens/settings/connection_settings_screen.dart` |
| One-tap "Disconnect Server" that forgets the server, signs out, and deletes local downloads/caches | `lib/utils/server_disconnect.dart` |

## Library and playlists

- Library sections for Albums, Songs, and Playlists, with grid/list view
  toggle and multi-select (`lib/screens/main/library/`).
- Search across the library (`lib/screens/main/search_screen.dart`,
  `lib/services/search_service.dart`).
- Local (device-only) playlists, plus server-synced playlists with
  non-destructive edits (rename, reorder, add/remove songs) that survive a
  server library rescan (`lib/services/playlist_service_server_edits_impl.dart`).
- "Add to playlist" and playlist creation flows
  (`lib/screens/playlist/add_to_playlist_screen.dart`,
  `lib/screens/playlist/create_playlist_screen.dart`).
- Live library updates over WebSocket (new/removed songs, playlist edits,
  pin changes) without needing to manually refresh, plus pull-to-refresh as
  a fallback (`lib/screens/main/library/library_controller_sync.dart`).
- "Clean Up Playlists" tool that finds and removes playlist entries for
  songs no longer on the server (`lib/screens/main/settings_screen.dart`,
  `_cleanUpUnavailableSongs`).
- Backup/restore of playlists and stats to a JSON file, with merge or
  replace import modes (`lib/services/import_export_service.dart`,
  `lib/screens/settings/import_export_screen.dart`).

## Playback

- Background playback with lock-screen/notification controls, built on
  `audio_service` and a `just_audio`-based handler
  (`lib/services/audio/audio_handler.dart`).
- Gapless playback: the next track is preloaded into the same native
  playlist as the current one so there's no Dart-side gap at the boundary
  (`lib/services/audio/gapless_playback_service.dart`,
  `AriamiAudioHandler.loadSong`).
- Queue management, shuffle, and repeat modes
  (`lib/services/audio/shuffle_service.dart`,
  `lib/models/repeat_mode.dart`, `lib/screens/queue_screen.dart`).
- A 5-band graphic equalizer with built-in presets (Flat, Bass Boost, Treble
  Boost, Rock, Pop, Jazz, Classical, Vocal, Electronic) and a custom curve,
  implemented natively on both platforms — `AndroidEqualizer` on Android and
  a vendored `DarwinEqualizer` fork of `just_audio` on iOS/macOS
  (`lib/services/audio/equalizer_service.dart`,
  `ariami_mobile/third_party/just_audio`).
- Automatic fallback to a downloaded/cached copy if a stream fails to start
  within 8 seconds and an on-device copy exists — see
  `docs/TROUBLESHOOTING.md` → "Playback stalls or won't start".
- Chromecast support and **Ariami Connect** (cross-device playback transfer
  and mirroring between your own signed-in clients), unified behind one
  output picker button in the player
  (`lib/services/cast/chrome_cast_service.dart`,
  `lib/services/ariami_connect_controller.dart`,
  `lib/widgets/player/player_output_button.dart`).

## Streaming quality and network awareness

- Independent quality presets for Wi‑Fi and mobile data (High/original,
  Medium 128 kbps, Low 64 kbps), plus a separate quality for downloads
  (`lib/models/quality_settings.dart`,
  `lib/screens/settings/quality_settings_screen.dart`).
- Network-type detection (Wi‑Fi vs. mobile vs. none) drives automatic
  quality switching (`lib/services/quality/network_monitor_service.dart`).
- Optional "prefer local/cached files when online" toggle so a phone with
  downloads doesn't re-stream what it already has
  (`QualitySettings.preferLocalWhenOnline`).

## Downloads and offline mode

- Persistent download queue with automatic retry (up to 3 attempts) and
  backoff tuned to the failure (longer backoff for HTTP 429/503, shorter for
  500, fixed 5s for network errors) — `lib/models/download_task.dart`,
  `lib/services/download/download_manager_transfer_impl.dart`.
- Pause/resume across app restarts, connection loss, and app backgrounding,
  with a recovery prompt on next launch or reconnect
  (`lib/main.dart`, `lib/screens/settings/downloads/downloads_screen.dart`).
- A native background-transfer backend on Android
  (`lib/services/download/native_download_service.dart`) so downloads
  continue after the app leaves the foreground, using a WorkManager-backed
  foreground service (`android/app/src/main/AndroidManifest.xml`).
- "Cooler Downloads" mode that paces bulk downloads to reduce heat/battery
  drain at the cost of speed
  (`lib/screens/settings/downloads/widgets/cooler_downloads_card.dart`).
- LRU eviction for the automatic song *cache* (streamed songs cached for
  replay) once it exceeds its configured limit (default 500 MB) — this is
  separate from explicit *downloads*, which are never auto-evicted
  (`lib/database/cache_database.dart`, `lib/services/cache/cache_manager.dart`).
- Manual offline mode toggle, plus automatic "auto-offline" when the
  connection is lost, both surfaced with a status label in Settings
  (`lib/services/offline/offline_playback_service.dart`).

## Stats

- Per-song, per-artist, and per-album listening stats stored locally in
  SQLite, using a shared counting rule from `ariami_core`: a play counts once
  cumulative listening reaches 30 seconds or half the track (whichever is
  smaller); short songs under 30s that finish naturally always count as one
  play (`lib/services/stats/streaming_stats_service.dart`).
- For signed-in accounts, stats are mirrored to the server so they sync
  across that account's other devices (`lib/services/stats/account_stats_service.dart`).
- A stats screen with overview metrics and period selection
  (`lib/screens/settings/stats/streaming_stats_screen.dart`).

## Account and device

- Multi-user login when the server has authentication enabled, with a
  per-account device list and rename support via Ariami Connect
  (`lib/screens/main/settings_screen.dart`, `_showRenameDeviceDialog`).
- Profile picture upload/change/remove, synced from the server
  (`lib/services/profile_image_service.dart`,
  `lib/screens/settings/profile_screen.dart`).
- A full local-data reset that clears downloads, cache, playlists, stats,
  and preferences in one action — see
  `lib/utils/app_local_data_reset.dart` and
  `docs/TROUBLESHOOTING.md` → "Reset the app".
