# BMA Core

Platform-agnostic core library for BMA (Basic Music App).

## Overview

This package contains all the shared business logic and services used by both `bma_desktop` and `bma_cli`:

### Services

**Library Services** (`services/library/`):
- `file_scanner.dart` - Recursively scans directories for audio files
- `metadata_extractor.dart` - Extracts ID3/Vorbis tags using dart_tags
- `album_builder.dart` - Groups songs into albums with compilation detection
- `duplicate_detector.dart` - Identifies duplicates via file hash + metadata
- `library_manager.dart` - Main library coordinator (singleton)
- `folder_watcher.dart` - Monitors file system changes
- `change_processor.dart` - Processes file additions/modifications/deletions

**Server Services** (`services/server/`):
- `http_server.dart` - Shelf-based HTTP server with REST endpoints and WebSocket
- `connection_manager.dart` - Tracks connected mobile clients and sessions
- `streaming_service.dart` - Audio streaming with HTTP range request support

### Models

All data models used across the BMA ecosystem:
- `Album` - Album information with track list
- `ApiModels` - Server request/response contracts
- `WebSocketModels` - Real-time message formats
- `ScanResult` - Results of library scan operation
- `LibraryStructure` - Hierarchical library representation
- `SongMetadata` - File metadata (title, artist, album, etc.)
- `FileChange` - File system change notifications

## Usage

Add to `pubspec.yaml`:

```yaml
dependencies:
  bma_core:
    path: ../bma_core
```

Import the package:

```dart
import 'package:bma_core/bma_core.dart';
```

## Supported Audio Formats

MP3, M4A, MP4, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC
