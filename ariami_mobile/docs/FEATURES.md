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
| "Already signed in elsewhere" takeover confirmation before signing the other device out | `lib/screens/login_screen.dart` (`_confirmOtherDeviceTakeover`) |
| Post-setup permission requests (notifications, and storage/media on Android) with a skip path | `lib/screens/setup/permissions_screen.dart`, `lib/services/permissions_service.dart` |
| Connection diagnostics: active address, LAN address, Tailscale address, port, route label, retry button | `lib/screens/settings/connection_settings_screen.dart` |
| "Disconnect Server" action (with confirmation) that forgets the server, signs out, and deletes local downloads/caches | `lib/utils/server_disconnect.dart` |
| Server music-health banner when the server's music folder is unavailable, empty, or failed its scan | `lib/widgets/music_availability_banner.dart`, `MusicAvailability` in `ariami_core` |

## Library and playlists

- Library sections for Albums, Songs, and Playlists, with grid/list view
  toggle, a combined mixed view, a downloaded-only filter, and multi-select
  (`lib/screens/main/library/`, `lib/screens/main/library/modals/library_options_sheet.dart`).
- Genre filter bar built from track metadata
  (`lib/services/library/library_genre_index.dart`,
  `lib/screens/main/library/widgets/genre_filter_bar.dart`).
- Artist pages with top songs and albums, plus custom artist photos that
  sync to your account (`lib/screens/artist_detail_screen.dart`,
  `lib/services/artist_image_service.dart`).
- Pin albums and playlists to the top, and like songs into a Liked Songs
  playlist (`lib/services/library/library_pin_storage.dart`,
  `lib/services/playlist_service_liked_songs_impl.dart`).
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
- Gapless playback, with a toggle in Playback settings: the next track is
  preloaded into the same native playlist as the current one so there's no
  Dart-side gap at the boundary (`lib/services/audio/gapless_playback_service.dart`,
  `lib/screens/settings/playback_settings_screen.dart`, `AriamiAudioHandler.loadSong`).
- Queue screen with reorder, remove, clear, and undo
  (`lib/screens/queue_screen.dart`).
- Shuffle and repeat modes
  (`lib/services/audio/shuffle_service.dart`,
  `lib/models/repeat_mode.dart`).
- A 5-band graphic equalizer with built-in presets (Flat, Bass Boost, Treble
  Boost, Rock, Pop, Jazz, Classical, Vocal, Electronic) and saved user
  presets, implemented natively on both platforms: `AndroidEqualizer` on
  Android and a vendored `DarwinEqualizer` fork of `just_audio` on iOS/macOS
  (`lib/services/audio/equalizer_service.dart`,
  `third_party/just_audio`).
- Automatic fallback to a downloaded/cached copy if a stream fails to start
  within 8 seconds and an on-device copy exists
  (`lib/services/playback_manager_streaming_impl.dart`, `_streamStartStallTimeout`).
- Queue-shaping options in Playback settings: play button follows playback,
  keep the queue when tapping a song, and stack Play Next after existing
  picks (`lib/screens/settings/playback_settings_screen.dart`).
- Google Cast support and **Ariami Connect** (cross-device playback transfer
  and mirroring between your own signed-in clients), unified behind one
  output picker button in the player
  (`lib/services/cast/chrome_cast_service.dart`,
  `lib/services/ariami_connect_controller.dart`,
  `lib/widgets/player/player_output_button.dart`).

## Streaming quality and network awareness

- Independent quality presets for Wi‑Fi and mobile data (High/original,
  Medium 128 kbps, Low 64 kbps), plus a separate download quality with its
  own Original, High (192 kbps), Medium (128 kbps), and Low (64 kbps)
  options (`lib/models/quality_settings.dart`,
  `lib/screens/settings/quality_settings_screen.dart`).
- Network-type detection (Wi‑Fi vs. mobile vs. none) drives automatic
  quality switching (`lib/services/quality/network_monitor_service.dart`).
- Optional "prefer local/cached files when online" toggle so a phone with
  downloads doesn't re-stream what it already has
  (`QualitySettings.preferLocalWhenOnline`,
  `lib/services/offline/offline_playback_service.dart`).

## Downloads and offline mode

- Persistent download queue that retries a failed download up to three
  times, with backoff tuned to the failure (longer backoff for HTTP
  429/503, shorter for 500, fixed 5s for network errors)
  (`lib/models/download_task.dart`,
  `lib/services/download/download_manager_transfer_impl.dart`).
- Pause/resume across app restarts, connection loss, and app backgrounding,
  with recovery cards on next launch or reconnect
  (`lib/main.dart`, `lib/screens/settings/downloads/downloads_screen.dart`).
- A native background-transfer backend on Android
  (`lib/services/download/native_download_service.dart`) so downloads
  continue after the app leaves the foreground, using a WorkManager-backed
  foreground service (`android/app/src/main/AndroidManifest.xml`,
  `android/app/src/main/kotlin/app/ariami/mobile/AriamiDownloadWorker.kt`).
- "Cooler Downloads" mode that paces bulk downloads to reduce heat/battery
  drain at the cost of speed
  (`lib/screens/settings/downloads/widgets/cooler_downloads_card.dart`).
- LRU eviction for the automatic song *cache* (streamed songs cached for
  replay) once it exceeds its configured limit (default 500 MB). This is
  separate from explicit *downloads*, which are never auto-evicted
  (`lib/database/cache_database.dart`, `lib/services/cache/cache_manager.dart`).
- Manual offline mode toggle, plus automatic "auto-offline" when the
  connection is lost, both surfaced with a status label in Settings
  (`lib/services/offline/offline_playback_service.dart`).

## Stats, discovery, and history

- Per-song, per-artist, and per-album listening stats stored locally in
  SQLite, using a shared counting rule from `ariami_core`: a play counts once
  cumulative listening reaches 30 seconds or half the track (whichever is
  smaller); short songs under 30s that finish naturally always count as one
  play (`lib/services/stats/streaming_stats_service.dart`).
- For signed-in accounts, stats are mirrored to the server so they sync
  across that account's other devices (`lib/services/stats/account_stats_service.dart`).
- A stats screen with overview metrics and a period selector (Day, Week,
  Month, Year, All) across songs, artists, and albums
  (`lib/screens/settings/stats/streaming_stats_screen.dart`).
- A Recently Played screen grouped by day
  (`lib/screens/settings/recently_played_screen.dart`).
- Optional music discovery powered by Last.fm: exploration tags, a mix
  choice, a household API key shared through the server or a per-device key,
  and an optional built-in key supplied at build time via the
  `ARIAMI_LASTFM_API_KEY` dart-define
  (`lib/screens/settings/music_discovery_screen.dart`).

## Account and device

- Multi-user login when the server has authentication enabled, with device
  rename via Ariami Connect (the Connect picker lists the devices signed in
  to the account) (`lib/screens/main/settings_screen.dart`,
  `_showRenameDeviceDialog`, `lib/widgets/player/ariami_connect_button.dart`).
- Profile picture upload/change/remove, synced from the server
  (`lib/services/profile_image_service.dart`,
  `lib/screens/settings/profile_screen.dart`).
- Ariami TV licence activation from the phone, with the licence relayed to
  the server. The section is hidden on iOS, so it's Android only in
  practice (`lib/screens/settings/tv_license_screen.dart`,
  `lib/services/license/tv_license_service.dart`).
- A full local-data reset that clears downloads, cache, playlists, stats,
  and preferences in one action. See
  `lib/utils/app_local_data_reset.dart` and
  `docs/TROUBLESHOOTING.md` → "Gathering logs and resetting app state".
