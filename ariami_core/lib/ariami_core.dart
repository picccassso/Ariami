/// Ariami Core Library - Platform-agnostic services and models for Ariami
library;

// Models
export 'models/album.dart';
export 'models/api_models.dart';
export 'models/file_change.dart';
export 'models/folder_playlist.dart';
export 'models/library_structure.dart';
export 'models/quality_preset.dart';
export 'models/scan_result.dart';
export 'models/song_metadata.dart';
export 'models/websocket_models.dart';

// Library Services
export 'services/library/album_builder.dart';
export 'services/library/change_processor.dart';
export 'services/library/duplicate_detector.dart';
export 'services/library/file_scanner.dart';
export 'services/library/folder_watcher.dart';
export 'services/library/library_manager.dart';
export 'services/library/library_scanner_isolate.dart';
export 'services/library/metadata_cache.dart';
export 'services/library/metadata_extractor.dart';

// Server Services
export 'services/server/connection_manager.dart';
export 'services/server/http_server.dart';
export 'services/server/streaming_service.dart';

// Transcoding Services
export 'services/transcoding/transcoding_service.dart';
