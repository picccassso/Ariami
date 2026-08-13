/// A server-owned, per-user instruction to keep something out of a client's
/// library browsing UI.
///
/// Hiding is presentation only: the album, playlist or artist stays in the
/// catalog and keeps playing, appearing in search and on detail pages. Only
/// the browsing lists that offer the Hide action honour it.
///
/// Artists have no catalog entity in Ariami — they are credit strings — so an
/// artist [targetId] is the display name itself.
class HiddenItem {
  const HiddenItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.targetId,
    required this.hiddenAt,
    this.sourceDeviceId,
  });

  static const String albumType = 'album';
  static const String playlistType = 'playlist';
  static const String artistType = 'artist';
  static const Set<String> supportedTypes = <String>{
    albumType,
    playlistType,
    artistType,
  };

  final String id;
  final String userId;
  final String type;
  final String targetId;
  final DateTime hiddenAt;
  final String? sourceDeviceId;

  String get key => '$type:$targetId';

  Map<String, dynamic> toJson({bool includeUserId = false}) =>
      <String, dynamic>{
        'id': id,
        if (includeUserId) 'userId': userId,
        'type': type,
        'targetId': targetId,
        'hiddenAt': hiddenAt.toUtc().toIso8601String(),
        if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
      };
}
