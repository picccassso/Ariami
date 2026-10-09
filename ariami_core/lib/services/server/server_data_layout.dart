import 'package:path/path.dart' as p;

/// File/directory names of the state a server host keeps under [rootDir].
class ServerDataLayout {
  const ServerDataLayout(this.rootDir);

  final String rootDir;

  static const usersFileName = 'users.json';
  static const sessionsFileName = 'sessions.json';
  static const musicDiscoveryFileName = 'music_discovery.json';
  static const metadataCacheFileName = 'metadata_cache.json';
  static const catalogDbFileName = 'catalog.db';
  static const artworkCacheDirName = 'artwork_cache';
  static const transcodedCacheDirName = 'transcoded_cache';

  String get usersFile => p.join(rootDir, usersFileName);
  String get sessionsFile => p.join(rootDir, sessionsFileName);
  String get musicDiscoveryFile => p.join(rootDir, musicDiscoveryFileName);
  String get metadataCacheFile => p.join(rootDir, metadataCacheFileName);
  String get catalogDbFile => p.join(rootDir, catalogDbFileName);
  String get artworkCacheDir => p.join(rootDir, artworkCacheDirName);
  String get transcodedCacheDir => p.join(rootDir, transcodedCacheDirName);
}
