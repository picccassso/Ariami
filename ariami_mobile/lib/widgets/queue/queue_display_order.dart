import '../../models/song.dart';

/// Maps between internal [PlaybackQueue] storage order and visible queue order.
class QueueDisplayOrder {
  QueueDisplayOrder._();

  static List<Song> songsInDisplayOrder(List<Song> songs, int currentIndex) {
    if (songs.isEmpty) return [];
    final c = currentIndex.clamp(0, songs.length - 1);
    return songs.sublist(c);
  }

  static int displayIndexToReal(
      int displayIndex, int length, int currentIndex) {
    if (length <= 0) return 0;
    final c = currentIndex.clamp(0, length - 1);
    return (c + displayIndex).clamp(0, length - 1);
  }
}
