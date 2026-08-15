/// Household Last.fm API-key configuration returned by the Ariami server.
///
/// The key is an application identifier used by Ariami's unauthenticated
/// discovery requests. It is not the separate Last.fm API secret.
class MusicDiscoveryApiKeyConfig {
  static const int maxApiKeyBytes = 256;

  const MusicDiscoveryApiKeyConfig({
    required this.lastFmApiKey,
    required this.canManage,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final String? lastFmApiKey;
  final bool canManage;

  bool get isConfigured => lastFmApiKey?.isNotEmpty ?? false;

  factory MusicDiscoveryApiKeyConfig.fromJson(Map<String, dynamic> json) {
    final rawKey = json['lastFmApiKey'];
    final normalizedKey = rawKey is String ? rawKey.trim() : '';
    return MusicDiscoveryApiKeyConfig(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      lastFmApiKey: normalizedKey.isEmpty ? null : normalizedKey,
      canManage: json['canManage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'lastFmApiKey': lastFmApiKey,
        'canManage': canManage,
      };
}
