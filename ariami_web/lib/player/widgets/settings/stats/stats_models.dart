enum StatsCategory { tracks, artists, albums }

class ListeningRankItem {
  const ListeningRankItem({
    required this.title,
    required this.subtitle,
    required this.detail,
    this.albumId,
    this.songId,
  });

  final String title;
  final String subtitle;
  final String detail;
  final String? albumId;
  final String? songId;
}
