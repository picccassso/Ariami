/// Shared models for Ariami's privacy-conscious music discovery feature.
library;

import '../stats/stats_range.dart';

enum MusicRecommendationKind { artist, track, album }

enum MusicDiscoveryMix { balanced, tracks, artists, albums }

class MusicDiscoveryPreferences {
  const MusicDiscoveryPreferences({
    this.mix = MusicDiscoveryMix.balanced,
    this.resultLimit = 24,
    this.tasteRange = StatsRange.all,
    this.seedDepth = 3,
  });

  /// Selectable result counts and seed depths, shared by both clients so the
  /// pickers cannot drift apart.
  static const Set<int> resultLimitChoices = <int>{12, 24, 36};
  static const Set<int> seedDepthChoices = <int>{3, 6, maxSeedDepth};

  /// The deepest selectable seed count, and the fan-out ceiling the
  /// recommendation service defaults to.
  static const int maxSeedDepth = 10;

  /// Taste ranges the discovery pickers offer, deliberately un-anchored: each
  /// resolves against "now" at refresh time, so a saved preference keeps
  /// meaning "this month" instead of freezing on the month it was chosen.
  static const List<StatsRange> tasteRangeChoices = <StatsRange>[
    StatsRange.all,
    StatsRange.week,
    StatsRange.month,
    StatsRange.year,
  ];

  /// Picker label for a taste range: the granularity plus the period it
  /// currently resolves to, e.g. "This month · July 2026".
  static String tasteRangeLabel(StatsRange range, {DateTime? now}) =>
      switch (range.kind) {
        StatsRangeKind.all => 'All time',
        StatsRangeKind.week => 'This week · ${range.title(now: now)}',
        StatsRangeKind.month => 'This month · ${range.title(now: now)}',
        StatsRangeKind.year => 'This year · ${range.title(now: now)}',
        StatsRangeKind.today || StatsRangeKind.day => range.title(now: now),
      };

  final MusicDiscoveryMix mix;
  final int resultLimit;

  /// Which slice of listening history the taste seeds are drawn from. Uses
  /// the same range model as the stats screens, so "month" means one thing
  /// across the whole app.
  final StatsRange tasteRange;

  /// How many artist seeds and how many track seeds to send. Each seed costs
  /// one Last.fm request, so this is the main lever on both breadth and time.
  final int seedDepth;

  /// Every field that changes the result set, so a cache entry is never
  /// reused across different settings. [StatsRange.token] carries the anchor,
  /// keeping two different weeks (or months) in separate entries.
  String get cacheKey =>
      '${mix.name}_${resultLimit}_${tasteRange.token}_$seedDepth';

  MusicDiscoveryPreferences copyWith({
    MusicDiscoveryMix? mix,
    int? resultLimit,
    StatsRange? tasteRange,
    int? seedDepth,
  }) =>
      MusicDiscoveryPreferences(
        mix: mix ?? this.mix,
        resultLimit: resultLimit ?? this.resultLimit,
        tasteRange: tasteRange ?? this.tasteRange,
        seedDepth: seedDepth ?? this.seedDepth,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mix': mix.name,
        'resultLimit': resultLimit,
        'tasteRange': tasteRange.token,
        'seedDepth': seedDepth,
      };

  factory MusicDiscoveryPreferences.fromJson(Map<String, dynamic> json) {
    int choice(Object? raw, Set<int> allowed, int fallback) {
      final value = (raw as num?)?.toInt();
      return value != null && allowed.contains(value) ? value : fallback;
    }

    return MusicDiscoveryPreferences(
      mix: MusicDiscoveryMix.values
              .where((value) => value.name == json['mix'])
              .firstOrNull ??
          MusicDiscoveryMix.balanced,
      resultLimit: choice(json['resultLimit'], resultLimitChoices, 24),
      tasteRange: StatsRange.tryParse(json['tasteRange'] as String?) ??
          _migratedRange(json['tastePeriod'] as String?),
      seedDepth: choice(json['seedDepth'], seedDepthChoices, 3),
    );
  }

  /// Preferences saved before ranges replaced the recent/all-time pair. The
  /// old "recent" meant a rolling seven days; the calendar week is its
  /// nearest equivalent.
  static StatsRange _migratedRange(String? tastePeriod) =>
      tastePeriod == 'recent' ? StatsRange.week : StatsRange.all;
}

/// One locally chosen taste signal. Only [artist] and, for track seeds,
/// [title] are sent to Last.fm; listening events and library contents stay local.
class MusicRecommendationSeed {
  const MusicRecommendationSeed.artist(this.artist, {this.weight = 1})
      : title = null;

  const MusicRecommendationSeed.track({
    required this.artist,
    required String this.title,
    this.weight = 1,
  });

  final String artist;
  final String? title;
  final double weight;

  bool get isTrack => title != null;
  String get label => isTrack ? '$artist — $title' : artist;
}

/// Minimal local-catalog shape used to remove music the listener already owns.
class OwnedMusicTrack {
  const OwnedMusicTrack({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
  });

  final String title;
  final String artist;
  final String? album;
  final String? albumArtist;
}

class MusicRecommendation {
  const MusicRecommendation({
    required this.kind,
    required this.name,
    required this.score,
    required this.lastFmUrl,
    required this.sourceSeeds,
    this.artist,
    this.musicBrainzId,
    this.imageUrl,
  });

  final MusicRecommendationKind kind;

  /// Track/album title for those kinds, artist name otherwise.
  final String name;
  final String? artist;
  final double score;
  final Uri lastFmUrl;
  final String? musicBrainzId;
  final Uri? imageUrl;
  final List<String> sourceSeeds;

  String get displayTitle => name;
  String? get displaySubtitle => switch (kind) {
        MusicRecommendationKind.track => artist,
        MusicRecommendationKind.album => artist,
        MusicRecommendationKind.artist => 'Similar artist',
      };

  Uri get youtubeMusicUrl => Uri.https(
        'music.youtube.com',
        '/search',
        <String, String>{'q': _searchLabel},
      );

  Uri get bandcampUrl => Uri.https(
        'bandcamp.com',
        '/search',
        <String, String>{'q': _searchLabel},
      );

  Uri? get musicBrainzUrl {
    final id = musicBrainzId;
    if (id == null || id.isEmpty) return null;
    final entity = switch (kind) {
      MusicRecommendationKind.artist => 'artist',
      MusicRecommendationKind.track => 'recording',
      MusicRecommendationKind.album => 'release-group',
    };
    return Uri.https('musicbrainz.org', '/$entity/$id');
  }

  String get _searchLabel => kind == MusicRecommendationKind.artist
      ? name
      : '${artist ?? ''} $name'.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'name': name,
        if (artist != null) 'artist': artist,
        'score': score,
        'lastFmUrl': lastFmUrl.toString(),
        if (musicBrainzId != null) 'musicBrainzId': musicBrainzId,
        if (imageUrl != null) 'imageUrl': imageUrl.toString(),
        'sourceSeeds': sourceSeeds,
      };

  factory MusicRecommendation.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'] as String?;
    final parsedImageUrl = Uri.tryParse(json['imageUrl'] as String? ?? '');
    return MusicRecommendation(
      kind: MusicRecommendationKind.values
              .where((kind) => kind.name == rawKind)
              .firstOrNull ??
          MusicRecommendationKind.track,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      lastFmUrl: Uri.tryParse(json['lastFmUrl'] as String? ?? '') ?? Uri(),
      musicBrainzId: json['musicBrainzId'] as String?,
      imageUrl: parsedImageUrl?.hasScheme == true ? parsedImageUrl : null,
      sourceSeeds: (json['sourceSeeds'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class MusicRecommendationSnapshot {
  const MusicRecommendationSnapshot({
    required this.generatedAt,
    required this.recommendations,
    required this.artistSeeds,
    required this.trackSeeds,
  });

  final DateTime generatedAt;
  final List<MusicRecommendation> recommendations;
  final List<String> artistSeeds;
  final List<String> trackSeeds;

  List<MusicRecommendation> get tracks => recommendations
      .where((item) => item.kind == MusicRecommendationKind.track)
      .toList(growable: false);

  List<MusicRecommendation> get artists => recommendations
      .where((item) => item.kind == MusicRecommendationKind.artist)
      .toList(growable: false);

  List<MusicRecommendation> get albums => recommendations
      .where((item) => item.kind == MusicRecommendationKind.album)
      .toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'recommendations':
            recommendations.map((item) => item.toJson()).toList(),
        'artistSeeds': artistSeeds,
        'trackSeeds': trackSeeds,
      };

  factory MusicRecommendationSnapshot.fromJson(Map<String, dynamic> json) {
    final generatedAt = DateTime.tryParse(json['generatedAt'] as String? ?? '');
    final recommendations =
        (json['recommendations'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicRecommendation.fromJson)
            .where((item) => item.name.isNotEmpty && item.lastFmUrl.hasScheme)
            .toList(growable: false);
    return MusicRecommendationSnapshot(
      generatedAt: generatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      recommendations: recommendations,
      artistSeeds: (json['artistSeeds'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      trackSeeds: (json['trackSeeds'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
