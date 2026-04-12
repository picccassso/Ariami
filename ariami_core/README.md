# Ariami Core

Platform-agnostic core library for Ariami. Contains shared business logic and services used by both ariami_desktop and ariami_cli.

## Overview

Ariami Core is a pure Dart package (no Flutter dependencies) that provides music library management, HTTP server functionality, authentication, and data models for the Ariami ecosystem. This package enables both GUI (desktop) and headless (CLI) server deployments to share the same core functionality.

## Architecture Role

- Shared by `ariami_desktop` and `ariami_cli` via path dependency
- Pure Dart implementation (no Flutter runtime required)
- Enables headless server deployment on minimal hardware
- Provides consistent API and behavior across all server types

## Library Services

Located in `services/library/`:

- **file_scanner.dart** - Recursively scans directories for audio files with support for multiple formats
- **metadata_extractor.dart** - Extracts ID3 and Vorbis tags using dart_tags package
- **metadata_cache.dart** - Caches extracted metadata for faster rescanning
- **album_builder.dart** - Groups songs into albums with multi-artist compilation detection
- **duplicate_detector.dart** - Identifies duplicate files via file hash and metadata comparison
- **library_manager.dart** - Main library coordinator (singleton pattern)
- **library_scanner_isolate.dart** - Isolate-based parallel scanning for performance
- **folder_watcher.dart** - Monitors file system for changes and triggers updates
- **change_processor.dart** - Processes file additions, modifications, and deletions in real-time
- **mp3_duration_parser.dart** - Pure Dart MP3 duration parser that handles large ID3 tags with embedded album art

## Server Services

Located in `services/server/`:

- **http_server.dart** - Shelf-based HTTP server with REST endpoints, WebSocket support, and static file serving (singleton pattern)
- **connection_manager.dart** - Tracks connected mobile clients, sessions, per-device identification, and heartbeat monitoring
- **streaming_service.dart** - Audio streaming with HTTP range request support for efficient seeking
- **stream_tracker.dart** - Tracks active streams per user and issues short-lived stream tokens for playback

## Auth Services

Located in `services/auth/`:

- **auth_service.dart** - User registration, login, logout, and session validation
- **user_store.dart** - JSON-based user persistence with bcrypt password hashing
- **session_store.dart** - Session token management with sliding TTL (30 days default)

If no users are registered, the server runs in legacy/open mode. Once the first user registers, authentication becomes required.

## Artwork Services

Located in `services/artwork/`:

- **artwork_service.dart** - Artwork compression and optimization for efficient delivery

## Transcoding Services

Located in `services/transcoding/`:

- **transcoding_service.dart** - Server-side audio transcoding with quality presets and caching (uses Sonic for MP3 -> AAC)

## Data Models

Located in `models/`:

- **Album** - Album information with track list and metadata
- **SongMetadata** - File metadata including title, artist, album, year, track number, duration
- **LibraryStructure** - Hierarchical library representation for client consumption
- **ScanResult** - Results of library scan operations with statistics
- **FileChange** - File system change notifications for real-time updates
- **ApiModels** - Server request/response contracts for HTTP endpoints
- **WebSocketModels** - Real-time message formats for WebSocket communication
- **AuthModels** - User, session, and stream ticket contracts

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

### Download Throttling

- Server-side concurrent download limits (configurable per platform)
- Per-user download concurrency enforcement
- Queuing with 503/429 responses when limits are exceeded

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

### Example: Initialize Library Manager

```dart
final libraryManager = LibraryManager();
await libraryManager.initialize('/path/to/music');
```

### Example: Start HTTP Server

```dart
final httpServer = AriamiHttpServer();
await httpServer.start(port: 8080);
```

## Development

### Running Tests

```bash
cd ariami_core
dart test
```

### Code Analysis

```bash
dart analyze
```

## Dependencies

Key dependencies:
- `shelf`, `shelf_router`, `shelf_web_socket`, `shelf_static` - HTTP server framework
- `dart_tags` - Audio metadata extraction
- `crypto` - File hashing for duplicate detection
- `bcrypt` - Password hashing for user authentication
- `watcher` - File system monitoring
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

- File scanning uses asynchronous I/O
- HTTP server handles concurrent requests
- Library updates are queued and processed sequentially to prevent race conditions
