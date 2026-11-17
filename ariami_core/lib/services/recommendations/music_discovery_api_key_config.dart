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
    this.feedToken,
    this.webhookUrl,
  });

  final int schemaVersion;
  final String? lastFmApiKey;
  final bool canManage;
  final String? feedToken;
  final String? webhookUrl;

  factory MusicDiscoveryApiKeyConfig.fromJson(Map<String, dynamic> json) {
    final rawKey = json['lastFmApiKey'];
    final normalizedKey = rawKey is String ? rawKey.trim() : '';
    final rawFeedToken = json['feedToken'];
    final normalizedFeedToken =
        rawFeedToken is String ? rawFeedToken.trim() : '';
    final rawWebhook = json['webhookUrl'];
    final normalizedWebhook = rawWebhook is String ? rawWebhook.trim() : '';
    return MusicDiscoveryApiKeyConfig(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      lastFmApiKey: normalizedKey.isEmpty ? null : normalizedKey,
      canManage: json['canManage'] as bool? ?? false,
      feedToken: normalizedFeedToken.isEmpty ? null : normalizedFeedToken,
      webhookUrl: normalizedWebhook.isEmpty ? null : normalizedWebhook,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'lastFmApiKey': lastFmApiKey,
        'canManage': canManage,
        if (feedToken != null && feedToken!.isNotEmpty) 'feedToken': feedToken,
        if (webhookUrl != null && webhookUrl!.isNotEmpty)
          'webhookUrl': webhookUrl,
      };
}
