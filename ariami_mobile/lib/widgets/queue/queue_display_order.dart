import '../../models/song.dart';

/// Maps between internal [PlaybackQueue] storage order and "current track first" display order.
class QueueDisplayOrder {
  QueueDisplayOrder._();

  /// Songs as shown in the queue UI: current + upcoming + history.
  static List<Song> songsInDisplayOrder(List<Song> songs, int currentIndex) {
    if (songs.isEmpty) return [];
    final c = currentIndex.clamp(0, songs.length - 1);
    return [...songs.sublist(c), ...songs.sublist(0, c)];
  }

  /// Convert a row index in [songsInDisplayOrder] to a storage index in [PlaybackQueue.songs].
  static int displayIndexToReal(int displayIndex, int length, int currentIndex) {
    if (length <= 0) return 0;
    final c = currentIndex.clamp(0, length - 1);
    final upcomingCount = length - c;
    if (displayIndex < upcomingCount) {
      return c + displayIndex;
    }
    return displayIndex - upcomingCount;
  }
}
