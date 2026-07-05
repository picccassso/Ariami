/// A server-owned, per-user shortcut to an album or playlist.
class PinnedItem {
  const PinnedItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.targetId,
    required this.sortOrder,
    required this.pinnedAt,
    required this.updatedAt,
    this.sourceDeviceId,
  });

  static const String albumType = 'album';
  static const String playlistType = 'playlist';
  static const Set<String> supportedTypes = <String>{albumType, playlistType};

  final String id;
  final String userId;
  final String type;
  final String targetId;
  final int sortOrder;
  final DateTime pinnedAt;
  final DateTime updatedAt;
  final String? sourceDeviceId;

  String get key => '$type:$targetId';

  Map<String, dynamic> toJson({bool includeUserId = false}) =>
      <String, dynamic>{
        'id': id,
        if (includeUserId) 'userId': userId,
        'type': type,
        'targetId': targetId,
        'sortOrder': sortOrder,
        'pinnedAt': pinnedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
      };
}
