# Ariami Core

Platform-agnostic core library for Ariami. Contains shared business logic and services used by the desktop, mobile, TV, and CLI apps.

## Overview

Ariami Core is a pure Dart package (no Flutter dependencies) that provides music library management, catalog persistence, HTTP server functionality, discovery, authentication, listening statistics, and data models for the Ariami ecosystem. This package enables both GUI (desktop) and headless (CLI) server deployments to share the same core functionality.

Detailed developer documentation lives in [`docs/`](docs/README.md) — architecture walk-through, the full HTTP/WebSocket API reference, persistence and schema details, listening stats, and testing notes. Playlist folder detection is documented separately in [`PLAYLIST_DETECTION.md`](PLAYLIST_DETECTION.md).

## Architecture Role

- Shared by the Ariami apps via path dependency
- Pure Dart implementation (no Flutter runtime required)
- Enables headless server deployment on minimal hardware
- Provides consistent API and behavior across all server types

## Library Services

Located in `services/library/`:

- **file_scanner.dart** - Recursively scans directories for audio files with support for multiple formats
- **metadata_extractor.dart** - Extracts ID3 and Vorbis tags using dart_tags package (split across `metadata_extractor/` part files for metadata, artwork, and format probes)
- **metadata_cache.dart** - Caches extracted metadata for faster rescanning
- **album_builder.dart** / **album_grouping.dart** / **album_identity.dart** - Groups songs into albums with multi-artist compilation detection and stable album identity
- **album_art_detection.dart** - Locates folder-level artwork alongside audio files
- **duplicate_detector.dart** - Identifies duplicate files via file hash and metadata comparison
- **library_manager.dart** - Main library coordinator (singleton pattern), implemented across `library_manager/` part files for scanning, caching, duration handling, and catalog integration
- **library_scanner_isolate.dart** - Isolate-based parallel scanning for performance
- **folder_watcher.dart** - Monitors file system for changes and triggers updates
- **change_processor.dart** - Processes file additions, modifications, and deletions in real-time
- **mp3_duration_parser.dart** - Pure Dart MP3 duration parser that handles large ID3 tags with embedded album art
- **library_playlist_builder.dart**, **m3u_playlist_parser.dart**, **playlist_folder_classifier.dart**, **playlist_decision_store.dart** - Folder- and `.m3u`-based playlist detection, with high-confidence folders auto-imported and medium-confidence folders surfaced as suggestions
- **natural_path_order.dart** - Human-friendly ordering of paths and filenames

## Catalog Services

Located in `services/catalog/`:

- **catalog_database.dart** - SQLite catalog database lifecycle wrapper (pure Dart `sqlite3`)
- **catalog_migrations.dart** - Forward-only schema migrations
- **catalog_repository.dart** - Read access to album, song, and artwork records
- **catalog_writer.dart** - Batched writes from scan results into the catalog

Catalog read and write paths are gated behind feature flags (see [Feature Flags](#feature-flags)).

## Server Services

Located in `services/server/`:

- **http_server.dart** - Shelf-based HTTP server with REST endpoints, WebSocket support, and static file serving (singleton pattern). Route handlers are split across `http_server_parts/` by area: auth, admin, library and artwork, streaming and downloads, download jobs, media tickets, playlist edits and suggestions, pins, listening stats, license, connections, setup/stats, middleware and metrics, lifecycle/config, and router registration
- **connection_manager.dart** - Tracks connected clients, sessions, per-device identification, and heartbeat monitoring
- **device_name_store.dart** - Persists user-chosen device display names so renames survive reconnects and restarts
- **streaming_service.dart** - Audio streaming with HTTP range request support for efficient seeking
- **stream_tracker.dart** - Tracks active streams per user and issues short-lived stream tokens for playback
- **download_job_service.dart** - Server-managed download jobs for bulk offline downloads
- **http_server_limiters.dart** - Global and per-user concurrency limiters for streams and downloads
- **metrics_service.dart** - Aggregates server-side metrics and emits periodic structured summary logs
- **network_endpoint_monitor.dart** - Periodically re-probes advertised network endpoints
- **server_port_policy.dart** - Port candidate selection and binding policy
- **response_compression.dart** - Response compression middleware
- **tailscale_path_diagnostics.dart** - Diagnostics for Tailscale-routed connections
- **v2_handlers.dart** - V2 API handlers (feature-flagged)

## Discovery Services

Located in `services/discovery/`:

- **discovery_protocol.dart** - Wire-level constants and payload helpers for the UDP beacon and mDNS
- **discovery_responder.dart** - Answers discovery traffic for a running server
- **discovery_browser.dart** - Finds candidate server endpoints on the network (candidates are unverified until confirmed over HTTP)
- **dns_wire.dart** - Minimal DNS/mDNS record encoding and decoding

## Connect Services

Located in `services/connect/`:

- **connect_hub.dart** - Authenticated, in-memory rendezvous for Ariami Connect; playback state stays owned by clients
- **connect_client.dart** - Resilient client transport over a dedicated WebSocket
- **remote_playback.dart** - Read-only view of playback on another Connect device, with controls routed as Connect commands

Connect protocol negotiation, authentication, ownership, mixed-version
behaviour, and recovery are documented in [docs/connect/](../docs/connect/README.md).

## Auth Services

Located in `services/auth/`:

- **auth_service.dart** - User registration, login, logout, and session validation
- **user_store.dart** - JSON-based user persistence with bcrypt password hashing
- **session_store.dart** - Session token management with sliding TTL (30 days default)

If no users are registered, the server runs in legacy/open mode. Once the first user registers, authentication becomes required.

## Listening Stats Services

Located in `services/stats/`:

- **listening_stats_store.dart** - Server-side per-user statistics backed by SQLite; raw events are the source of truth and are deduped by client-generated event ID, so retries and offline replays never double-count
- **listening_event_tracker.dart** - Turns playback activity into listening events
- **listening_event_outbox.dart** / **listening_stats_syncer.dart** - Offline-safe client outbox and uploader; batches are only dropped once the server confirms acceptance
- **period_stats_overlay.dart**, **stats_range.dart**, **stats_local_day.dart** - Period/range handling and local-day bucketing
- **credited_artist_splitter.dart** - Splits multi-artist credits for per-artist attribution
- **spotify_import/** - Parses Spotify Extended Streaming History, matches tracks against the library, and builds importable events

## Playlist, Pin, and License Services

- `services/playlists/` - **playlist_edit_store.dart** (user playlist edits), **playlist_edit_reconcile.dart** (reconciling edits against rescans), **playlist_image_store.dart** (custom playlist artwork), **created_playlist_id.dart**
- `services/pins/pinned_item_store.dart` - SQLite persistence for account-scoped pins
- `services/license/` - **license_file_store.dart** and **license_key_activator.dart**; the server is a dumb relay that never parses or validates license contents — clients verify them

## Search Services

Located in `services/search/`:

- **library_search_engine.dart** - Shared, deterministic search and ranking so a query behaves identically on mobile, desktop, and TV
- **search_normalizer.dart** - Shared text normalization (lowercasing, diacritic folding) for queries and indexed fields

## Artwork and Transcoding Services

- `services/artwork/artwork_service.dart` - Artwork compression and optimization for efficient delivery, with size variants
- `services/transcoding/transcoding_service.dart` - Server-side audio transcoding with quality presets and caching (uses Sonic via FFI for MP3 -> AAC); implementation is split across `src/` for cache, environment, FFI, models, and process handling
- `services/transcoding/transcode_slots_policy.dart` - Concurrency policy for transcode slots

## Other Services

- `services/setup/music_folder_path_helper.dart` - Music folder path resolution during setup
- `services/reset/reset_service.dart` - Clears local Ariami state at configurable scopes

## Data Models

Located in `models/`:

- **Album** - Album information with track list and metadata
- **SongMetadata** - File metadata including title, artist, album, year, track number, duration
- **LibraryStructure** - Hierarchical library representation for client consumption
- **ScanResult** / **ScanDiagnostics** - Results and diagnostics of library scan operations
- **FileChange** - File system change notifications for real-time updates
- **ApiModels** - Server request/response contracts for HTTP endpoints
- **WebSocketModels** - Real-time message formats for WebSocket communication
- **AuthModels** - User, session, and stream ticket contracts
- **ConnectModels** - Ariami Connect presence, state, and command contracts
- **SyncModels** - Library sync contracts
- **DownloadJobModels** - Download job requests and status
- **ListeningStatsModels** / **UserActivityRow** - Listening event and statistics contracts
- **FolderPlaylist** / **PlaylistSuggestion** - Detected playlists and advisory suggestions
- **PinnedItem** - Account-scoped pins
- **ArtworkSize** / **QualityPreset** - Artwork variants and transcoding quality presets
- **ServerOrigin** - Server origin/endpoint description
- **FeatureFlags** - Runtime feature gating

## Key Features

### Pure Dart Implementation

Ariami Core is implemented in pure Dart without Flutter dependencies, enabling:
- Execution in headless environments without Flutter runtime
- Deployment on minimal hardware (Raspberry Pi, servers)
- Faster startup and lower memory footprint for CLI server

### MP3 Duration Parser

Custom pure Dart MP3 duration parser that correctly handles:
- Large ID3 tags (>64KB) with embedded album art
- Multiple ID3 versions
- Variable bitrate (VBR) files
- Accurate duration extraction without external libraries

### Supported Audio Formats

MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC

### Real-time Library Updates

- File system watcher monitors music folder for changes
- Automatic processing of new, modified, and deleted files
- WebSocket broadcasts to connected clients
- Incremental updates without full rescans

### Multi-User Authentication

- User registration and login with bcrypt password hashing
- Session tokens with 30-day sliding TTL
- Stream tokens with duration-based TTL for audio playback compatibility
- Rate-limited login attempts (5 per 15 minutes per device)
- Admin APIs for device management and password changes

### Server Discovery

- UDP beacon plus mDNS responder so clients can find servers on the LAN
- Discovered endpoints are treated as unverified until confirmed via `GET /api/server-info`

### Download Throttling

- Server-side concurrent download limits (configurable per platform)
- Per-user download concurrency enforcement
- Queuing with 503/429 responses when limits are exceeded

### Feature Flags

`AriamiFeatureFlags` gates optional server behavior:

- `enableV2Api` - V2 API routes
- `enableCatalogWrite` / `enableCatalogRead` - SQLite catalog write and read paths
- `enableArtworkPrecompute` - Precomputed artwork variants
- `enableDownloadJobs` - Server-managed download jobs
- `enableApiScopedAuthForCliWeb` - Scoped API auth for the CLI web client

Flags are validated for consistency when the HTTP server starts.

## Usage

Add to `pubspec.yaml`:

```yaml
dependencies:
  ariami_core:
    path: ../ariami_core
```

Import the package:

```dart
import 'package:ariami_core/ariami_core.dart';
```

### Example: Scan a Music Folder

```dart
final libraryManager = LibraryManager();
libraryManager.setCachePath('/path/to/cache');
await libraryManager.scanMusicFolder('/path/to/music');
```

### Example: Start HTTP Server

```dart
final httpServer = AriamiHttpServer();
await httpServer.start(advertisedIp: '192.168.1.10', port: 8080);
```

## Development

### Running Tests

```bash
dart test
```

### Code Analysis

```bash
dart analyze
```

## Dependencies

Key dependencies:
- `shelf`, `shelf_router`, `shelf_web_socket`, `shelf_static`, `web_socket_channel` - HTTP server framework and WebSockets
- `sqlite3` - Pure Dart SQLite runtime for the catalog, stats, pins, and playlist stores
- `dart_tags` - Audio metadata extraction
- `crypto` - File hashing for duplicate detection
- `bcrypt` - Password hashing for user authentication
- `watcher` - File system monitoring
- `ffi` - Sonic transcoder bindings
- `http` - Outbound HTTP (license activation, sync)
- `path` - Path manipulation utilities
- `logging` - Structured logging

## Technical Details

### Singleton Services

Critical services use singleton pattern:
- `LibraryManager` - Ensures single library instance
- `AriamiHttpServer` - Prevents port conflicts
- `AuthService` - Single auth coordinator

### Error Handling

Services throw exceptions that should be caught and logged by consumers. All public APIs document their exception types.

### Concurrency

- File scanning uses asynchronous I/O and a dedicated isolate
- HTTP server handles concurrent requests, with limiters for streams and downloads
- Library updates are queued and processed sequentially to prevent race conditions
