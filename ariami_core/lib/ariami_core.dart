/// Ariami Core Library - Platform-agnostic services and models for Ariami
library;

export 'app_version.dart';

// Models
export 'models/album.dart';
export 'models/api_models.dart';
export 'models/artwork_size.dart';
export 'models/auth_models.dart';
export 'models/connect_models.dart';
export 'models/file_change.dart';
export 'models/folder_playlist.dart';
export 'models/library_structure.dart';
export 'models/listening_stats_models.dart';
export 'models/pinned_item.dart';
export 'models/quality_preset.dart';
export 'models/scan_result.dart';
export 'models/server_origin.dart';
export 'models/song_metadata.dart';
export 'models/sync_models.dart';
export 'models/user_activity_row.dart';
export 'models/websocket_models.dart';

// Library Services
export 'services/library/album_builder.dart';
export 'services/library/album_identity.dart';
export 'services/library/change_processor.dart';
export 'services/library/library_playlist_builder.dart';
export 'services/library/duplicate_detector.dart';
export 'services/library/file_scanner.dart';
export 'services/library/folder_watcher.dart';
export 'services/library/library_manager.dart';
export 'services/library/library_scanner_isolate.dart';
export 'services/library/metadata_cache.dart';
export 'services/library/metadata_extractor.dart';

// Reset Services
export 'services/reset/reset_service.dart';

// Setup Services
export 'services/setup/music_folder_path_helper.dart';

// Discovery Services
export 'services/discovery/discovery_browser.dart';
export 'services/discovery/discovery_protocol.dart';
export 'services/discovery/discovery_responder.dart';
export 'services/discovery/dns_wire.dart';

// Server Services
export 'services/server/connection_manager.dart';
export 'services/server/http_server.dart';
export 'services/server/network_endpoint_monitor.dart';
export 'services/server/server_port_policy.dart';
export 'services/server/stream_tracker.dart';
export 'services/server/streaming_service.dart';
export 'services/connect/connect_hub.dart';
export 'services/connect/connect_client.dart';
export 'services/connect/remote_playback.dart';

// Transcoding Services
export 'services/transcoding/transcode_slots_policy.dart';
export 'services/transcoding/transcoding_service.dart';

// Artwork Services
export 'services/artwork/artwork_service.dart';

// Listening Stats Services
export 'services/stats/listening_event_outbox.dart';
export 'services/stats/listening_event_tracker.dart';
export 'services/stats/listening_stats_store.dart';
export 'services/stats/listening_stats_syncer.dart';
export 'services/stats/period_stats_overlay.dart';
export 'services/stats/stats_local_day.dart';
export 'services/stats/stats_range.dart';
// Spotify Extended Streaming History import
export 'services/stats/spotify_import/spotify_import_models.dart';
export 'services/stats/spotify_import/library_track_matcher.dart';
export 'services/stats/spotify_import/spotify_history_parser.dart';
export 'services/stats/spotify_import/spotify_event_builder.dart';
export 'services/stats/spotify_import/spotify_importer.dart';
export 'services/pins/pinned_item_store.dart';
export 'services/license/license_file_store.dart';
export 'services/license/license_key_activator.dart';

// Auth Services
export 'services/auth/auth_service.dart';
export 'services/auth/session_store.dart';
export 'services/auth/user_store.dart';
