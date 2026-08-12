import '../search/search_normalizer.dart';
import 'lastfm_recommendation_client.dart';
import 'music_recommendation_models.dart';
import 'musicbrainz_identity_client.dart';

class MusicRecommendationService {
  MusicRecommendationService({
    required this.lastFm,
    required this.musicBrainz,
    this.artistSeedLimit = MusicDiscoveryPreferences.maxSeedDepth,
    this.trackSeedLimit = MusicDiscoveryPreferences.maxSeedDepth,
    this.musicBrainzLookupLimit = 4,
    this.artworkLookupLimit = 36,
    this.metadataLookupLimit = 72,
  });

  final LastFmRecommendationClient lastFm;
  final MusicBrainzIdentityClient musicBrainz;

  /// Ceilings, not the control: callers choose depth through
  /// [MusicDiscoveryPreferences.seedDepth] and pass that many seeds in. These
  /// only stop a miscounted caller fanning out unboundedly on Last.fm.
  final int artistSeedLimit;
  final int trackSeedLimit;
  final int musicBrainzLookupLimit;
  final int artworkLookupLimit;
  final int metadataLookupLimit;

  Future<MusicRecommendationSnapshot> discover({
    required Iterable<MusicRecommendationSeed> seeds,
    required Iterable<OwnedMusicTrack> ownedTracks,
    int limit = 24,
    MusicDiscoveryMix mix = MusicDiscoveryMix.balanced,
    Set<String> preferredTags = const <String>{},
    Set<String> libraryTags = const <String>{},
    bool instrumentalOnly = false,
  }) async {
    final effectiveMix = instrumentalOnly ? MusicDiscoveryMix.tracks : mix;
    final requestedTags = preferredTags
        .map(normalizeMusicDiscoveryTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final discoveryTags = <String>{
      ...requestedTags,
      if (instrumentalOnly) 'instrumental',
    };
    final localTasteTags = libraryTags
        .map(normalizeMusicDiscoveryTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final selectedArtists =
        _selectSeeds(seeds.where((seed) => !seed.isTrack), artistSeedLimit);
    final selectedTracks =
        _selectSeeds(seeds.where((seed) => seed.isTrack), trackSeedLimit);
    if (selectedArtists.isEmpty &&
        selectedTracks.isEmpty &&
        discoveryTags.isEmpty) {
      throw const LastFmRecommendationException(
        'Listen to a few songs first so Ariami can choose recommendation seeds.',
      );
    }

    final owned = _OwnedMusicIndex(ownedTracks);
    final accumulators = <String, _CandidateAccumulator>{};
    final candidateLimit = limit > 24 ? 24 : 12;
    // A seed Last.fm has never heard of is normal for a personal library, so
    // it is skipped rather than aborting the run. Anything else — a bad key,
    // a rate limit, a dead connection — is about the request itself and still
    // propagates immediately.
    var unresolvedSeeds = 0;
    for (final seed in selectedArtists) {
      try {
        _merge(
          accumulators,
          await lastFm.similarArtists(seed.artist, limit: candidateLimit),
          seed,
        );
      } on LastFmRecommendationException catch (error) {
        if (!error.isNotFound) rethrow;
        unresolvedSeeds++;
      }
    }
    for (final seed in selectedTracks) {
      try {
        _merge(
          accumulators,
          await _similarTracksForSeed(seed, limit: candidateLimit),
          seed,
        );
      } on LastFmRecommendationException catch (error) {
        if (!error.isNotFound) rethrow;
        unresolvedSeeds++;
      }
    }
    if (accumulators.isEmpty && unresolvedSeeds > 0 && requestedTags.isEmpty) {
      throw const LastFmRecommendationException(
        'Last.fm did not recognise any of your top artists or tracks for that '
        'period. Try a wider taste period, or a greater taste depth.',
        apiCode: 6,
      );
    }

    final tagCandidates = <String, _CandidateAccumulator>{};
    for (final tag in discoveryTags) {
      try {
        if (effectiveMix == MusicDiscoveryMix.tracks ||
            effectiveMix == MusicDiscoveryMix.balanced) {
          _mergeTag(
            tagCandidates,
            await lastFm.topTracksForTag(tag, limit: candidateLimit * 2),
            tag,
          );
        }
        if (effectiveMix == MusicDiscoveryMix.artists ||
            effectiveMix == MusicDiscoveryMix.albums ||
            effectiveMix == MusicDiscoveryMix.balanced) {
          _mergeTag(
            tagCandidates,
            await lastFm.topArtistsForTag(tag, limit: candidateLimit * 2),
            tag,
          );
        }
      } on LastFmRecommendationException catch (error) {
        if (!error.isNotFound) rethrow;
      }
    }
    if (requestedTags.isNotEmpty && tagCandidates.isEmpty) {
      throw LastFmRecommendationException(
        'Last.fm found no music tagged ${requestedTags.map(musicDiscoveryTagLabel).join(' or ')}. '
        'Try another tag.',
        apiCode: 6,
      );
    }
    if (tagCandidates.isNotEmpty) {
      for (final entry in tagCandidates.entries) {
        final tasteCandidate = accumulators[entry.key];
        if (tasteCandidate != null) entry.value.absorb(tasteCandidate);
      }
    }

    final candidatePool = <String, _CandidateAccumulator>{...tagCandidates};
    if (requestedTags.isEmpty) {
      // Instrumental mode remains taste-aware, but the explicit tag pool also
      // makes it useful when similarity candidates have sparse metadata.
      for (final entry in accumulators.entries) {
        candidatePool.putIfAbsent(entry.key, () => entry.value);
      }
    }
    var candidates = candidatePool.values
        .where((candidate) => !_isSeed(candidate, <MusicRecommendationSeed>[
              ...selectedArtists,
              ...selectedTracks,
            ]))
        .where((candidate) =>
            effectiveMix == MusicDiscoveryMix.albums ||
            !owned.contains(candidate.kind, candidate.name, candidate.artist))
        .toList()
      ..sort(_compareCandidates);

    var lookups = 0;
    for (final candidate in candidates) {
      if (lookups >= musicBrainzLookupLimit) break;
      if (candidate.musicBrainzId != null) continue;
      lookups++;
      final identity = candidate.kind == MusicRecommendationKind.artist
          ? await musicBrainz.searchArtist(candidate.name)
          : await musicBrainz.searchRecording(
              title: candidate.name,
              artist: candidate.artist ?? '',
            );
      if (identity == null) continue;
      candidate.musicBrainzId = identity.id;
      candidate.name = identity.name;
      if (candidate.kind == MusicRecommendationKind.track &&
          (identity.artist?.isNotEmpty ?? false)) {
        candidate.artist = identity.artist;
      }
    }

    // Canonical MusicBrainz ids can reveal duplicates that had different
    // Last.fm spellings. Merge once more, then re-run the owned-library filter.
    final identified = <String, _CandidateAccumulator>{};
    for (final candidate in candidates) {
      if (effectiveMix != MusicDiscoveryMix.albums &&
          owned.contains(candidate.kind, candidate.name, candidate.artist)) {
        continue;
      }
      final key = _identityKey(
        candidate.kind,
        candidate.name,
        candidate.artist,
        candidate.musicBrainzId,
      );
      final existing = identified[key];
      if (existing == null) {
        identified[key] = candidate;
      } else {
        existing.absorb(candidate);
      }
    }
    candidates = identified.values.toList()..sort(_compareCandidates);

    if (localTasteTags.isNotEmpty) {
      await _enrichMetadata(
        candidates.take(metadataLookupLimit),
        rethrowFailures: false,
      );
      for (final candidate in candidates) {
        if (_tagsMatch(candidate.tags, localTasteTags)) {
          candidate.boostForLibraryTaste();
        }
      }
      candidates.sort(_compareCandidates);
    }

    candidates = switch (effectiveMix) {
      MusicDiscoveryMix.tracks => candidates
          .where((item) => item.kind == MusicRecommendationKind.track)
          .toList(),
      MusicDiscoveryMix.artists || MusicDiscoveryMix.albums => candidates
          .where((item) => item.kind == MusicRecommendationKind.artist)
          .toList(),
      MusicDiscoveryMix.balanced => candidates,
    };

    if (instrumentalOnly) {
      await _enrichMetadata(candidates.take(metadataLookupLimit));
      final styleTags =
          requestedTags.difference(const <String>{'instrumental'});
      candidates = candidates.where((candidate) {
        final explicitlyInstrumental = _hasTagEvidence(
          candidate,
          const <String>{'instrumental'},
        );
        final matchesRequestedStyle =
            styleTags.isEmpty || _hasTagEvidence(candidate, styleTags);
        return explicitlyInstrumental && matchesRequestedStyle;
      }).toList();
      if (candidates.isEmpty) {
        throw LastFmRecommendationException(
          requestedTags.isEmpty
              ? 'Last.fm found no explicitly instrumental matches for your taste. Try a wider taste period or depth.'
              : 'Last.fm found no explicitly instrumental ${requestedTags.map(musicDiscoveryTagLabel).join(' or ')} matches. Try another tag.',
          apiCode: 6,
        );
      }
    }

    if (effectiveMix == MusicDiscoveryMix.albums) {
      final recommendations = await _albumsFromArtists(
        candidates,
        owned: owned,
        limit: limit,
      );
      return MusicRecommendationSnapshot(
        generatedAt: DateTime.now().toUtc(),
        recommendations: List.unmodifiable(recommendations),
        artistSeeds:
            List.unmodifiable(selectedArtists.map((seed) => seed.label)),
        trackSeeds: List.unmodifiable(selectedTracks.map((seed) => seed.label)),
      );
    }

    final selected = <_CandidateAccumulator>[];
    final tracksPerArtist = <String, int>{};
    for (final candidate in candidates) {
      if (selected.length >= limit) break;
      if (candidate.kind == MusicRecommendationKind.track) {
        final artistKey =
            SearchNormalizer.normalizeString(candidate.artist ?? '');
        final count = tracksPerArtist[artistKey] ?? 0;
        if (artistKey.isNotEmpty && count >= 2) continue;
        tracksPerArtist[artistKey] = count + 1;
      }
      selected.add(candidate);
    }

    await _enrichArtwork(selected);
    final recommendations = selected.map((candidate) => candidate.build());

    return MusicRecommendationSnapshot(
      generatedAt: DateTime.now().toUtc(),
      recommendations: List.unmodifiable(recommendations),
      artistSeeds: List.unmodifiable(selectedArtists.map((seed) => seed.label)),
      trackSeeds: List.unmodifiable(selectedTracks.map((seed) => seed.label)),
    );
  }

  /// Similar tracks for [seed], retrying once without a trailing edition or
  /// feature suffix. Library tags carry things Last.fm does not index in the
  /// title — "Song (Remastered 2011)", "Song (feat. Someone)" — and those are
  /// the most common cause of a false "Track not found".
  Future<List<LastFmRecommendationCandidate>> _similarTracksForSeed(
    MusicRecommendationSeed seed, {
    required int limit,
  }) async {
    try {
      return await lastFm.similarTracks(
        artist: seed.artist,
        track: seed.title!,
        limit: limit,
      );
    } on LastFmRecommendationException catch (error) {
      final base = error.isNotFound ? _baseTitle(seed.title!) : null;
      if (base == null) rethrow;
      return lastFm.similarTracks(
        artist: seed.artist,
        track: base,
        limit: limit,
      );
    }
  }

  /// "Song (Remastered 2011)" -> "Song"; null when there is nothing to strip.
  /// Casing is preserved because the result goes back to Last.fm as a title.
  static String? _baseTitle(String title) {
    const suffixWords = <String>{
      'live', 'remaster', 'remastered', 'remix', 'edit', 'version', 'mix',
      'acoustic', 'demo', 'mono', 'stereo', 'deluxe', 'bonus', 'instrumental',
      'feat', 'feat.', 'featuring', 'ft', 'ft.', 'with', //
    };
    final match =
        RegExp(r'^(.*?)\s*[\(\[]([^\)\]]+)[\)\]]\s*$').firstMatch(title.trim());
    if (match == null) return null;
    final suffix = (match.group(2) ?? '').toLowerCase();
    if (!suffix.split(RegExp(r'[\s,]+')).any(suffixWords.contains)) return null;
    final base = (match.group(1) ?? '').trim();
    return base.isEmpty || base == title.trim() ? null : base;
  }

  Future<List<MusicRecommendation>> _albumsFromArtists(
    List<_CandidateAccumulator> artists, {
    required _OwnedMusicIndex owned,
    required int limit,
  }) async {
    final recommendations = <MusicRecommendation>[];
    final seen = <String>{};
    for (var offset = 0;
        offset < artists.length && recommendations.length < limit;
        offset += 4) {
      final end = offset + 4 < artists.length ? offset + 4 : artists.length;
      final batch = await Future.wait(
        artists.sublist(offset, end).map((candidate) async {
          try {
            return (
              candidate: candidate,
              album: await lastFm.topAlbum(candidate.name)
            );
          } catch (_) {
            return (candidate: candidate, album: null);
          }
        }),
      );
      for (final entry in batch) {
        final album = entry.album;
        if (album == null ||
            owned.contains(
              MusicRecommendationKind.album,
              album.name,
              album.artist,
            )) {
          continue;
        }
        final key = _identityKey(
          MusicRecommendationKind.album,
          album.name,
          album.artist,
          album.musicBrainzId,
        );
        if (!seen.add(key)) continue;
        recommendations.add(MusicRecommendation(
          kind: MusicRecommendationKind.album,
          name: album.name,
          artist: album.artist,
          score: entry.candidate.score,
          lastFmUrl: album.url,
          musicBrainzId: album.musicBrainzId,
          imageUrl: album.imageUrl,
          sourceSeeds: entry.candidate.sourceSeeds.toList(growable: false)
            ..sort(),
          sourceTags: entry.candidate.sourceTags.toList(growable: false)
            ..sort(),
        ));
        if (recommendations.length >= limit) break;
      }
    }
    return recommendations;
  }

  Future<void> _enrichArtwork(
    List<_CandidateAccumulator> candidates,
  ) async {
    final missing = <_CandidateAccumulator>[
      ...candidates.where((candidate) =>
          candidate.kind == MusicRecommendationKind.track &&
          candidate.imageUrl == null &&
          !candidate.metadataLoaded),
      ...candidates.where((candidate) =>
          candidate.kind == MusicRecommendationKind.artist &&
          candidate.imageUrl == null),
    ].take(artworkLookupLimit).toList(growable: false);

    // Small batches keep refresh responsive without bursting Last.fm with one
    // request for every visible recommendation at once.
    for (var offset = 0; offset < missing.length; offset += 4) {
      final end = offset + 4 < missing.length ? offset + 4 : missing.length;
      await Future.wait(missing.sublist(offset, end).map((candidate) async {
        try {
          candidate.imageUrl = candidate.kind == MusicRecommendationKind.artist
              ? await lastFm.artistImage(candidate.name)
              : await lastFm.trackImage(
                  artist: candidate.artist ?? '',
                  track: candidate.name,
                );
        } catch (_) {
          // Artwork is optional; recommendation ranking and links remain useful.
        }
      }));
    }
  }

  Future<void> _enrichMetadata(Iterable<_CandidateAccumulator> source,
      {bool rethrowFailures = true}) async {
    final candidates = source
        .where((candidate) => !candidate.metadataLoaded)
        .toList(growable: false);
    for (var offset = 0; offset < candidates.length; offset += 4) {
      final end =
          offset + 4 < candidates.length ? offset + 4 : candidates.length;
      await Future.wait(candidates.sublist(offset, end).map((candidate) async {
        try {
          final metadata = candidate.kind == MusicRecommendationKind.artist
              ? await lastFm.artistMetadata(candidate.name)
              : await lastFm.trackMetadata(
                  artist: candidate.artist ?? '',
                  track: candidate.name,
                );
          candidate.metadataLoaded = true;
          candidate.tags = metadata.tags;
          candidate.imageUrl ??= metadata.imageUrl;
        } on LastFmRecommendationException catch (error) {
          if (!error.isNotFound) {
            if (rethrowFailures) rethrow;
            return;
          }
          candidate.metadataLoaded = true;
          // An individual track or artist can be absent from Last.fm's info
          // catalogue even when it appeared in a similarity response.
        } catch (_) {
          if (rethrowFailures) rethrow;
          // A local-genre boost is optional. Instrumental mode retries failed
          // metadata because it needs positive evidence before including one.
        }
      }));
    }
  }

  static bool _tagsMatch(Set<String>? tags, Set<String> aliases) {
    if (tags == null || tags.isEmpty) return false;
    for (final rawTag in tags) {
      final tag = SearchNormalizer.normalizeString(rawTag);
      for (final rawAlias in aliases) {
        final alias = SearchNormalizer.normalizeString(rawAlias);
        if (tag == alias ||
            tag.startsWith('$alias ') ||
            tag.endsWith(' $alias') ||
            tag.contains(' $alias ')) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasTagEvidence(
    _CandidateAccumulator candidate,
    Set<String> aliases,
  ) =>
      _tagsMatch(candidate.sourceTags, aliases) ||
      _tagsMatch(candidate.tags, aliases);

  static List<MusicRecommendationSeed> _selectSeeds(
    Iterable<MusicRecommendationSeed> source,
    int limit,
  ) {
    final byIdentity = <String, MusicRecommendationSeed>{};
    for (final seed in source) {
      final artist = seed.artist.trim();
      final title = seed.title?.trim();
      if (artist.isEmpty || artist == 'Unknown Artist') continue;
      if (seed.isTrack &&
          (title == null || title.isEmpty || title == 'Unknown Song')) {
        continue;
      }
      final key = '${SearchNormalizer.normalizeString(artist)}|'
          '${SearchNormalizer.normalizeString(title ?? '')}';
      final existing = byIdentity[key];
      if (existing == null || seed.weight > existing.weight) {
        byIdentity[key] = seed;
      }
    }
    final selected = byIdentity.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return selected.take(limit).toList(growable: false);
  }

  static void _merge(
    Map<String, _CandidateAccumulator> target,
    Iterable<LastFmRecommendationCandidate> candidates,
    MusicRecommendationSeed seed,
  ) {
    for (final candidate in candidates) {
      if (candidate.match <= 0) continue;
      final key = _identityKey(
        candidate.kind,
        candidate.name,
        candidate.artist,
        candidate.musicBrainzId,
      );
      final weightedScore = candidate.match * seed.weight.clamp(0.1, 1);
      final existing = target[key];
      if (existing == null) {
        target[key] = _CandidateAccumulator.fromLastFm(
          candidate,
          weightedScore: weightedScore,
          seed: seed.label,
        );
      } else {
        existing.addEvidence(weightedScore, seed.label);
      }
    }
  }

  static void _mergeTag(
    Map<String, _CandidateAccumulator> target,
    Iterable<LastFmRecommendationCandidate> candidates,
    String tag,
  ) {
    for (final candidate in candidates) {
      if (candidate.match <= 0) continue;
      final key = _identityKey(
        candidate.kind,
        candidate.name,
        candidate.artist,
        candidate.musicBrainzId,
      );
      final existing = target[key];
      if (existing == null) {
        target[key] = _CandidateAccumulator.fromTag(
          candidate,
          tag: tag,
        );
      } else {
        existing.addTagEvidence(candidate.match, tag);
      }
    }
  }

  static bool _isSeed(
    _CandidateAccumulator candidate,
    Iterable<MusicRecommendationSeed> seeds,
  ) {
    final candidateArtist = SearchNormalizer.normalizeString(
      candidate.kind == MusicRecommendationKind.artist
          ? candidate.name
          : candidate.artist ?? '',
    );
    final candidateTitle = SearchNormalizer.normalizeString(
      candidate.kind == MusicRecommendationKind.track ? candidate.name : '',
    );
    return seeds.any((seed) {
      if (SearchNormalizer.normalizeString(seed.artist) != candidateArtist) {
        return false;
      }
      if (!seed.isTrack || candidate.kind == MusicRecommendationKind.artist) {
        return true;
      }
      return SearchNormalizer.normalizeString(seed.title ?? '') ==
          candidateTitle;
    });
  }

  static String _identityKey(
    MusicRecommendationKind kind,
    String name,
    String? artist,
    String? musicBrainzId,
  ) {
    final mbid = musicBrainzId?.trim();
    if (mbid != null && mbid.isNotEmpty) return '${kind.name}:mbid:$mbid';
    return '${kind.name}:${SearchNormalizer.normalizeString(name)}|'
        '${SearchNormalizer.normalizeString(artist ?? '')}';
  }

  static int _compareCandidates(
    _CandidateAccumulator a,
    _CandidateAccumulator b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void close() {
    lastFm.close();
    musicBrainz.close();
  }
}

class _CandidateAccumulator {
  _CandidateAccumulator({
    required this.kind,
    required this.name,
    required this.artist,
    required this.lastFmUrl,
    required this.musicBrainzId,
    required this.imageUrl,
    required this.score,
    required this.sourceSeeds,
    required this.sourceTags,
  });

  factory _CandidateAccumulator.fromLastFm(
    LastFmRecommendationCandidate candidate, {
    required double weightedScore,
    required String seed,
  }) =>
      _CandidateAccumulator(
        kind: candidate.kind,
        name: candidate.name,
        artist: candidate.artist,
        lastFmUrl: candidate.url,
        musicBrainzId: candidate.musicBrainzId,
        imageUrl: candidate.imageUrl,
        score: weightedScore,
        sourceSeeds: <String>{seed},
        sourceTags: <String>{},
      );

  factory _CandidateAccumulator.fromTag(
    LastFmRecommendationCandidate candidate, {
    required String tag,
  }) =>
      _CandidateAccumulator(
        kind: candidate.kind,
        name: candidate.name,
        artist: candidate.artist,
        lastFmUrl: candidate.url,
        musicBrainzId: candidate.musicBrainzId,
        imageUrl: candidate.imageUrl,
        score: candidate.match,
        sourceSeeds: <String>{},
        sourceTags: <String>{tag},
      );

  final MusicRecommendationKind kind;
  String name;
  String? artist;
  Uri lastFmUrl;
  String? musicBrainzId;
  Uri? imageUrl;
  double score;
  final Set<String> sourceSeeds;
  final Set<String> sourceTags;
  Set<String>? tags;
  bool metadataLoaded = false;

  void addEvidence(double weightedScore, String seed) {
    // The strongest relationship leads, with corroborating seeds adding a
    // smaller boost so broad consensus wins without swamping similarity.
    score = score > weightedScore
        ? score + weightedScore * 0.25
        : weightedScore + score * 0.25;
    sourceSeeds.add(seed);
  }

  void addTagEvidence(double tagScore, String tag) {
    score =
        score > tagScore ? score + tagScore * 0.15 : tagScore + score * 0.15;
    sourceTags.add(tag);
  }

  void boostForLibraryTaste() => score *= 1.15;

  void absorb(_CandidateAccumulator other) {
    if (other.sourceSeeds.isNotEmpty) {
      addEvidence(other.score, other.sourceSeeds.first);
    } else {
      score = score > other.score
          ? score + other.score * 0.25
          : other.score + score * 0.25;
    }
    sourceSeeds.addAll(other.sourceSeeds);
    sourceTags.addAll(other.sourceTags);
    musicBrainzId ??= other.musicBrainzId;
    imageUrl ??= other.imageUrl;
    if (!lastFmUrl.hasScheme) lastFmUrl = other.lastFmUrl;
  }

  MusicRecommendation build() => MusicRecommendation(
        kind: kind,
        name: name,
        artist: artist,
        score: score,
        lastFmUrl: lastFmUrl,
        musicBrainzId: musicBrainzId,
        imageUrl: imageUrl,
        sourceSeeds: sourceSeeds.toList(growable: false)..sort(),
        sourceTags: sourceTags.toList(growable: false)..sort(),
      );
}

class _OwnedMusicIndex {
  _OwnedMusicIndex(Iterable<OwnedMusicTrack> tracks) {
    for (final track in tracks) {
      final artist = SearchNormalizer.normalizeString(track.artist);
      if (artist.isEmpty) continue;
      artists.add(artist);
      for (final title in _titleVariants(track.title)) {
        songs.add('$artist|$title');
      }
      final album = SearchNormalizer.normalizeString(track.album ?? '');
      final albumArtist = SearchNormalizer.normalizeString(
        track.albumArtist ?? track.artist,
      );
      if (album.isNotEmpty && albumArtist.isNotEmpty) {
        albums.add('$albumArtist|$album');
      }
    }
  }

  final Set<String> artists = <String>{};
  final Set<String> songs = <String>{};
  final Set<String> albums = <String>{};

  bool contains(MusicRecommendationKind kind, String name, String? artist) {
    if (kind == MusicRecommendationKind.artist) {
      return artists.contains(SearchNormalizer.normalizeString(name));
    }
    final normalizedArtist = SearchNormalizer.normalizeString(artist ?? '');
    if (normalizedArtist.isEmpty) return false;
    if (kind == MusicRecommendationKind.album) {
      return albums.contains(
        '$normalizedArtist|${SearchNormalizer.normalizeString(name)}',
      );
    }
    return _titleVariants(name)
        .any((title) => songs.contains('$normalizedArtist|$title'));
  }

  static Iterable<String> _titleVariants(String title) sync* {
    final normalized = SearchNormalizer.normalizeString(title);
    if (normalized.isNotEmpty) yield normalized;
    final match =
        RegExp(r'^(.*?)\s*[\(\[]([^\)\]]+)[\)\]]\s*$').firstMatch(title);
    if (match == null) return;
    final suffix = SearchNormalizer.normalizeString(match.group(2) ?? '');
    const variantWords = <String>{
      'live',
      'remaster',
      'remastered',
      'remix',
      'edit',
      'version',
      'mix',
      'acoustic',
      'demo',
      'mono',
      'deluxe',
    };
    if (!suffix.split(' ').any(variantWords.contains)) return;
    final base = SearchNormalizer.normalizeString(match.group(1) ?? '');
    if (base.isNotEmpty && base != normalized) yield base;
  }
}
