# Transcoding Implementation

This document provides a comprehensive overview of the audio transcoding feature in Ariami.

## Overview

Ariami supports server-side audio transcoding to reduce bandwidth usage on mobile connections. The server uses FFmpeg to transcode audio files to lower bitrates on-demand, with intelligent caching to avoid re-transcoding.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           MOBILE APP                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  NetworkMonitorService ──▶ QualitySettingsService ──▶ PlaybackManager   │
│        (WiFi/Mobile)          (picks quality)         (builds URL)      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                         GET /api/stream/{id}?quality=medium
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           SERVER                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  HttpServer ──▶ TranscodingService ──▶ FFmpeg ──▶ Cache                 │
│  (parses ?quality)  (checks cache)      (transcodes)  (stores .m4a)     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Quality Presets

| Quality | Bitrate | Format | File Extension | Use Case |
|---------|---------|--------|----------------|----------|
| **High** | Original | Original | Original | WiFi streaming, downloads |
| **Medium** | 128 kbps | AAC | .m4a | Mobile data streaming |
| **Low** | 64 kbps | AAC | .m4a | Slow connections |

## Components

### Server-Side (ariami_core)

#### TranscodingService

**File:** `ariami_core/lib/services/transcoding/transcoding_service.dart`

The core transcoding engine that handles FFmpeg-based transcoding and caching.

**Key Features:**
- FFmpeg availability detection
- Quality-based transcoding (medium=128kbps, low=64kbps AAC)
- LRU cache with configurable size (default 2GB)
- Concurrency control to prevent duplicate transcoding of the same file
- Cache cleanup and song invalidation

**Key Methods:**
```dart
/// Check if FFmpeg is available on the system
Future<bool> isFFmpegAvailable()

/// Get a transcoded file (from cache or by transcoding)
Future<File?> getTranscodedFile(String sourcePath, String songId, QualityPreset quality)

/// Get current cache size in bytes
Future<int> getCacheSize()

/// Clear the entire transcoding cache
Future<void> clearCache()

/// Invalidate cached transcodes for a specific song
Future<void> invalidateSong(String songId)
```

**FFmpeg Command:**
```bash
ffmpeg -y -i [input] -c:a aac -b:a [bitrate]k -vn -movflags +faststart -map_metadata -1 [output]
```

- `-y` - Overwrite output file without asking
- `-c:a aac` - AAC audio codec
- `-b:a [bitrate]k` - Target bitrate
- `-vn` - No video output
- `-movflags +faststart` - Enable streaming before full download
- `-map_metadata -1` - Strip metadata for smaller file size

#### QualityPreset

**File:** `ariami_core/lib/models/quality_preset.dart`

Enum defining the available quality levels.

```dart
enum QualityPreset {
  high,   // Original file (no transcoding)
  medium, // 128 kbps AAC
  low;    // 64 kbps AAC

  int? get bitrate;           // Bitrate in kbps (null for high)
  String? get fileExtension;  // 'm4a' for transcoded files
  String? get mimeType;       // 'audio/mp4' for transcoded
  String get displayName;     // Human-readable name
  bool get requiresTranscoding;

  static QualityPreset fromString(String? value);
  String toQueryParam();
}
```

#### HttpServer Integration

**File:** `ariami_core/lib/services/server/http_server.dart`

The HTTP server integrates transcoding into the streaming and download endpoints.

**Streaming Endpoint:** `GET /api/stream/<songId>?quality=<preset>`
**Download Endpoint:** `GET /api/download/<songId>?quality=<preset>`

**Behavior:**
1. Parse quality parameter from request (defaults to `high`)
2. Look up file path from library
3. If quality requires transcoding and service is configured:
   - Check cache for existing transcoded file
   - If not cached, transcode using FFmpeg
   - Fall back to original file if transcoding fails
4. Stream/download the file with HTTP range request support

**Server Setup:**
```dart
// Set transcoding service (called during server initialization)
void setTranscodingService(TranscodingService service)
```

### Mobile App (ariami_mobile)

#### QualitySettings Model

**File:** `ariami_mobile/lib/models/quality_settings.dart`

```dart
enum StreamingQuality {
  high,   // Original file
  medium, // 128 kbps
  low;    // 64 kbps

  String toApiParam();
  String get displayName;
  String get description;
  String get bitrateLabel;
}

class QualitySettings {
  final StreamingQuality wifiQuality;       // Default: high
  final StreamingQuality mobileDataQuality; // Default: medium
  final StreamingQuality downloadQuality;   // Default: high
}
```

#### QualitySettingsService

**File:** `ariami_mobile/lib/services/quality/quality_settings_service.dart`

Singleton service managing quality preferences with persistence.

**Key Methods:**
```dart
/// Initialize and load saved settings
Future<void> initialize()

/// Get current streaming quality based on network type
StreamingQuality getCurrentStreamingQuality()

/// Get download quality setting
StreamingQuality getDownloadQuality()

/// Update individual quality settings
Future<void> setWifiQuality(StreamingQuality quality)
Future<void> setMobileDataQuality(StreamingQuality quality)
Future<void> setDownloadQuality(StreamingQuality quality)

/// Generate URLs with quality parameter
String getStreamUrlWithQuality(String baseStreamUrl)
String getDownloadUrlWithQuality(String baseDownloadUrl)
```

#### NetworkMonitorService

**File:** `ariami_mobile/lib/services/quality/network_monitor_service.dart`

Singleton service for monitoring network connectivity type.

```dart
enum NetworkType {
  wifi,   // WiFi or Ethernet
  mobile, // Cellular data
  none,   // No connection
}

class NetworkMonitorService {
  NetworkType get currentNetworkType;
  Stream<NetworkType> get networkTypeStream;
  bool get isOnWifi;
  bool get isOnMobileData;
  bool get isOffline;
}
```

**Network Type Mapping:**
- WiFi, Ethernet → `NetworkType.wifi`
- Mobile/Cellular → `NetworkType.mobile`
- Bluetooth, VPN, Other → `NetworkType.mobile` (conservative)
- None → `NetworkType.none`

#### QualitySettingsScreen

**File:** `ariami_mobile/lib/screens/settings/quality_settings_screen.dart`

Full UI for configuring quality settings with:
- Current network status indicator
- Separate quality pickers for WiFi, Mobile Data, and Downloads
- Quality descriptions and bitrate labels
- Info section explaining quality levels

#### ApiClient Integration

**File:** `ariami_mobile/lib/services/api/api_client.dart`

```dart
/// Get stream URL with quality parameter
String getStreamUrlWithQuality(String songId, StreamingQuality quality)

/// Get download URL with quality parameter
String getDownloadUrlWithQuality(String songId, StreamingQuality quality)
```

**URL Format:**
- High quality: `/api/stream/{songId}` (no parameter needed)
- Medium/Low: `/api/stream/{songId}?quality=medium` or `?quality=low`

#### PlaybackManager Integration

**File:** `ariami_mobile/lib/services/playback_manager.dart`

The playback manager automatically selects quality based on network:

```dart
// Get streaming quality based on current network (WiFi vs mobile data)
final streamingQuality = _qualityService.getCurrentStreamingQuality();
audioUrl = _connectionService.apiClient!.getStreamUrlWithQuality(
  song.filePath,
  streamingQuality,
);
```

### Desktop App (ariami_desktop)

#### Dashboard Integration

**File:** `ariami_desktop/lib/screens/dashboard_screen.dart`

```dart
// Initialize transcoding service
final transcodingCachePath = p.join(appDir.path, 'transcoded_cache');
_transcodingService = TranscodingService(
  cacheDirectory: transcodingCachePath,
  maxCacheSizeMB: 2048, // 2GB cache limit
);
_httpServer.setTranscodingService(_transcodingService!);

// Check FFmpeg availability
_transcodingService!.isFFmpegAvailable().then((available) {
  if (!available) {
    print('[Dashboard] Warning: FFmpeg not found - transcoding will be disabled');
  }
});
```

**Cache Location:** `~/Library/Application Support/ariami_desktop/transcoded_cache/`

### CLI App (ariami_cli)

#### Server Runner Integration

**File:** `ariami_cli/lib/server_runner.dart`

```dart
// Initialize transcoding service
final transcodingCachePath = p.join(CliStateService.getConfigDir(), 'transcoded_cache');
final transcodingService = TranscodingService(
  cacheDirectory: transcodingCachePath,
  maxCacheSizeMB: 2048, // 2GB cache limit
);
_httpServer.setTranscodingService(transcodingService);

// Check FFmpeg availability
final ffmpegAvailable = await transcodingService.isFFmpegAvailable();
if (ffmpegAvailable) {
  print('✓ FFmpeg available - transcoding enabled');
} else {
  print('⚠ FFmpeg not found - transcoding disabled (will serve original files)');
}
```

**Cache Location:** `~/.ariami_cli/transcoded_cache/`

## Initialization Flow

### Mobile App Initialization

**File:** `ariami_mobile/lib/main.dart`

```dart
Future<void> _initializeServices() async {
  // ... other services ...

  // Initialize network monitor for quality-based streaming
  await _networkMonitor.initialize();
  // Initialize quality settings service
  await _qualityService.initialize();
}
```

### Server Initialization (Desktop/CLI)

1. Create `TranscodingService` with cache directory and size limit
2. Call `httpServer.setTranscodingService(transcodingService)`
3. Check FFmpeg availability and log status
4. Server is ready to handle quality-based requests

## Default Settings

| Setting | Default Value |
|---------|---------------|
| WiFi Streaming Quality | High (Original) |
| Mobile Data Streaming Quality | Medium (128 kbps) |
| Download Quality | High (Original) |
| Transcoding Cache Size | 2 GB |
| Transcoding Timeout | 5 minutes |

## Cache Management

### LRU Eviction Strategy

The transcoding cache uses Least Recently Used (LRU) eviction:
1. When cache exceeds max size, collect all cached files with their stats
2. Sort by last modified time (oldest first)
3. Delete oldest files until cache is under limit

### Cache Structure

```
transcoded_cache/
├── medium/
│   ├── {songId1}.m4a
│   ├── {songId2}.m4a
│   └── ...
└── low/
    ├── {songId1}.m4a
    ├── {songId2}.m4a
    └── ...
```

### Cache Invalidation

Call `transcodingService.invalidateSong(songId)` when:
- Source file is modified
- Source file is deleted
- User manually requests cache clear

## Requirements

### Server Requirements

- **FFmpeg** must be installed and accessible in PATH
- Sufficient disk space for transcoding cache (2GB default)
- Write permissions to cache directory

### FFmpeg Installation

**macOS:**
```bash
brew install ffmpeg
```

**Ubuntu/Debian:**
```bash
sudo apt install ffmpeg
```

**Windows:**
Download from https://ffmpeg.org/download.html and add to PATH

### Fallback Behavior

If FFmpeg is not available:
- Server logs warning at startup
- Quality parameter is ignored
- Original files are served for all requests
- Mobile app works normally (just no bandwidth savings)

## API Reference

### Stream Endpoint

```
GET /api/stream/<songId>?quality=<preset>
```

**Parameters:**
- `songId` (path) - The song identifier
- `quality` (query, optional) - Quality preset: `high`, `medium`, or `low`

**Response:**
- Audio stream with appropriate Content-Type
- Supports HTTP Range requests for seeking

### Download Endpoint

```
GET /api/download/<songId>?quality=<preset>
```

**Parameters:**
- `songId` (path) - The song identifier
- `quality` (query, optional) - Quality preset: `high`, `medium`, or `low`

**Response:**
- Full file download with Content-Disposition header
- Filename extension adjusted for transcoded files (.m4a)

## Troubleshooting

### Transcoding Not Working

1. Check FFmpeg is installed: `ffmpeg -version`
2. Check server logs for "FFmpeg not found" warning
3. Verify cache directory exists and is writable

### High Latency on First Play

First play of a song at medium/low quality requires transcoding. Subsequent plays use cached version.

### Cache Growing Too Large

- Reduce `maxCacheSizeMB` in TranscodingService initialization
- Call `transcodingService.clearCache()` to clear manually
- Cache auto-cleans using LRU when limit is reached
