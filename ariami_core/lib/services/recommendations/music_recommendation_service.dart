import '../search/search_normalizer.dart';
import '../stats/credited_artist_splitter.dart';
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
    final skipTasteSeeds = requestedTags.isNotEmpty;
    final selectedArtists = skipTasteSeeds
        ? const <MusicRecommendationSeed>[]
        : _selectSeeds(
            seeds.where((seed) => !seed.isTrack),
            artistSeedLimit,
          );
    final selectedTracks = skipTasteSeeds
        ? const <MusicRecommendationSeed>[]
        : _selectSeeds(
            seeds.where((seed) => seed.isTrack),
            trackSeedLimit,
            maxPerArtist: _maxTrackSeedsPerArtist,
          );
    final selectedSeeds = <MusicRecommendationSeed>[
      ...selectedArtists,
      ...selectedTracks,
    ];
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
    if (!skipTasteSeeds) {
      unresolvedSeeds += await _collectSeedCandidates(
        accumulators,
        selectedArtists,
        (seed) => _similarArtistsForSeed(seed, limit: candidateLimit),
      );
      unresolvedSeeds += await _collectSeedCandidates(
        accumulators,
        selectedTracks,
        (seed) => _similarTracksForSeed(seed, limit: candidateLimit),
      );
    }
    if (accumulators.isEmpty && unresolvedSeeds > 0 && requestedTags.isEmpty) {
      throw const LastFmRecommendationException(
        'Last.fm did not recognise any of your top artists or tracks for that '
        'period. Try a wider taste period, or a greater taste depth.',
        apiCode: 6,
      );
    }

    final tagCandidates = <String, _CandidateAccumulator>{};
    await _mergeTopTagCandidates(
      tagCandidates,
      discoveryTags,
      mix: effectiveMix,
      limit: candidateLimit * 2,
    );

    if (instrumentalOnly && requestedTags.isNotEmpty) {
      final styleTags =
          requestedTags.difference(const <String>{'instrumental'});
      await _enrichMetadata(tagCandidates.values.take(metadataLookupLimit));
      final hasStrictMatch = tagCandidates.values.any(
        (candidate) =>
            !_isSeed(candidate, selectedSeeds) &&
            !owned.contains(candidate.kind, candidate.name, candidate.artist) &&
            _matchesInstrumentalStyle(candidate, styleTags),
      );
      if (!hasStrictMatch) {
        // Last.fm has no multi-tag query. Its compound community tags often
        // carry the intended intersection even when the separate top charts
        // and per-track tags do not overlap.
        await _mergeTopTagCandidates(
          tagCandidates,
          _instrumentalCompoundTags(styleTags),
          mix: effectiveMix,
          limit: candidateLimit * 2,
        );
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
        .where((candidate) => !_isSeed(candidate, selectedSeeds))
        .where((candidate) =>
            effectiveMix == MusicDiscoveryMix.albums ||
            !owned.contains(candidate.kind, candidate.name, candidate.artist))
        .toList()
      ..sort(_compareCandidates);

    candidates = switch (effectiveMix) {
      MusicDiscoveryMix.tracks => candidates
          .where((item) => item.kind == MusicRecommendationKind.track)
          .toList(),
      MusicDiscoveryMix.artists || MusicDiscoveryMix.albums => candidates
          .where((item) => item.kind == MusicRecommendationKind.artist)
          .toList(),
      MusicDiscoveryMix.balanced => candidates,
    };

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

    if (instrumentalOnly) {
      await _enrichMetadata(candidates.take(metadataLookupLimit));
      final styleTags =
          requestedTags.difference(const <String>{'instrumental'});
      candidates = candidates
          .where((candidate) => _matchesInstrumentalStyle(candidate, styleTags))
          .toList();
      if (candidates.isEmpty) {
        throw LastFmRecommendationException(
          requestedTags.isEmpty
              ? 'Last.fm found no explicitly instrumental matches for your taste. Try a wider taste period or depth.'
              : 'Last.fm found no explicitly instrumental ${requestedTags.map(musicDiscoveryTagLabel).join(' or ')} matches. Try another tag.',
          apiCode: 6,
        );
      }
    }

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

    final selected = _selectRecommendations(
      candidates,
      mix: effectiveMix,
      limit: limit,
    );

    await _enrichArtwork(selected);
    final recommendations = selected.map((candidate) => candidate.build());

    return MusicRecommendationSnapshot(
      generatedAt: DateTime.now().toUtc(),
      recommendations: List.unmodifiable(recommendations),
      artistSeeds: List.unmodifiable(selectedArtists.map((seed) => seed.label)),
      trackSeeds: List.unmodifiable(selectedTracks.map((seed) => seed.label)),
    );
  }

  static const int _maxTrackSeedsPerArtist = 2;
  static const int _seedConcurrency = 4;
  static final CreditedArtistSplitter _artistSplitter = CreditedArtistSplitter();

  Future<int> _collectSeedCandidates(
    Map<String, _CandidateAccumulator> accumulators,
    List<MusicRecommendationSeed> seeds,
    Future<List<LastFmRecommendationCandidate>> Function(
            MusicRecommendationSeed)
        fetch,
  ) async {
    var unresolved = 0;
    for (var offset = 0; offset < seeds.length; offset += _seedConcurrency) {
      final end = offset + _seedConcurrency < seeds.length
          ? offset + _seedConcurrency
          : seeds.length;
      final batch = await Future.wait(
        seeds.sublist(offset, end).map((seed) async {
          try {
            return (seed: seed, candidates: await fetch(seed), notFound: false);
          } on LastFmRecommendationException catch (error) {
            if (!error.isNotFound) rethrow;
            return (
              seed: seed,
              candidates: const <LastFmRecommendationCandidate>[],
              notFound: true,
            );
          }
        }),
      );
      for (final item in batch) {
        if (item.notFound) {
          unresolved++;
        } else {
          _merge(accumulators, item.candidates, item.seed);
        }
      }
    }
    return unresolved;
  }

  Future<List<LastFmRecommendationCandidate>> _similarArtistsForSeed(
    MusicRecommendationSeed seed, {
    required int limit,
  }) async {
    try {
      return await lastFm.similarArtists(seed.artist, limit: limit);
    } on LastFmRecommendationException catch (error) {
      final primary = error.isNotFound ? _primaryArtist(seed.artist) : null;
      if (primary == null) rethrow;
      return lastFm.similarArtists(primary, limit: limit);
    }
  }

  /// Similar tracks for [seed], retrying without a trailing edition/feature
  /// suffix or secondary collaboration credits on "Track not found".
  Future<List<LastFmRecommendationCandidate>> _similarTracksForSeed(
    MusicRecommendationSeed seed, {
    required int limit,
  }) async {
    final title = seed.title!;
    final base = _baseTitle(title);
    final primary = _primaryArtist(seed.artist);
    final attempts = <(String artist, String track)>[
      (seed.artist, title),
      if (base != null) (seed.artist, base),
      if (primary != null) (primary, title),
      if (primary != null && base != null) (primary, base),
    ];
    LastFmRecommendationException? lastNotFound;
    for (final attempt in attempts) {
      try {
        return await lastFm.similarTracks(
          artist: attempt.$1,
          track: attempt.$2,
          limit: limit,
        );
      } on LastFmRecommendationException catch (error) {
        if (!error.isNotFound) rethrow;
        lastNotFound = error;
      }
    }
    throw lastNotFound!;
  }

  static String? _primaryArtist(String artist) {
    final trimmed = artist.trim();
    final credits = _artistSplitter.split(trimmed);
    if (credits.isEmpty) return null;
    final primary = credits.first.display;
    return primary == trimmed ? null : primary;
  }

  Future<void> _mergeTopTagCandidates(
    Map<String, _CandidateAccumulator> target,
    Iterable<String> tags, {
    required MusicDiscoveryMix mix,
    required int limit,
  }) async {
    for (final tag in tags) {
      try {
        if (mix == MusicDiscoveryMix.tracks ||
            mix == MusicDiscoveryMix.balanced) {
          _mergeTag(
            target,
            await lastFm.topTracksForTag(tag, limit: limit),
            tag,
          );
        }
        if (mix == MusicDiscoveryMix.artists ||
            mix == MusicDiscoveryMix.albums ||
            mix == MusicDiscoveryMix.balanced) {
          _mergeTag(
            target,
            await lastFm.topArtistsForTag(tag, limit: limit),
            tag,
          );
        }
      } on LastFmRecommendationException catch (error) {
        if (!error.isNotFound) rethrow;
      }
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
              albums: await lastFm.topAlbums(candidate.name, limit: 5),
            );
          } catch (_) {
            return (candidate: candidate, albums: const <LastFmTopAlbum>[]);
          }
        }),
      );
      for (final entry in batch) {
        for (final album in entry.albums) {
          if (owned.contains(
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
          break;
        }
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

  static bool _matchesInstrumentalStyle(
    _CandidateAccumulator candidate,
    Set<String> styleTags,
  ) =>
      _hasTagEvidence(candidate, const <String>{'instrumental'}) &&
      (styleTags.isEmpty || _hasTagEvidence(candidate, styleTags));

  static Set<String> _instrumentalCompoundTags(Set<String> styleTags) =>
      <String>{
        for (final tag in styleTags)
          if (!_tagsMatch(<String>{tag}, const <String>{'instrumental'})) ...[
            'instrumental $tag',
            '$tag instrumental',
          ],
      };

  static List<MusicRecommendationSeed> _selectSeeds(
    Iterable<MusicRecommendationSeed> source,
    int limit, {
    int? maxPerArtist,
  }) {
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
    final ranked = byIdentity.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    if (maxPerArtist == null || maxPerArtist <= 0) {
      return ranked.take(limit).toList(growable: false);
    }
    final selected = <MusicRecommendationSeed>[];
    final perArtist = <String, int>{};
    for (final seed in ranked) {
      if (selected.length >= limit) break;
      final artistKey = normalizeArtistKey(
        _primaryArtist(seed.artist) ?? seed.artist,
      );
      final count = perArtist[artistKey] ?? 0;
      if (count >= maxPerArtist) continue;
      perArtist[artistKey] = count + 1;
      selected.add(seed);
    }
    return selected;
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

  static List<_CandidateAccumulator> _selectRecommendations(
    List<_CandidateAccumulator> candidates, {
    required MusicDiscoveryMix mix,
    required int limit,
  }) {
    if (limit <= 0) return const <_CandidateAccumulator>[];
    final tracks = <_CandidateAccumulator>[];
    final artists = <_CandidateAccumulator>[];
    final tracksPerArtist = <String, int>{};
    for (final candidate in candidates) {
      if (candidate.kind == MusicRecommendationKind.artist) {
        artists.add(candidate);
      } else if (candidate.kind == MusicRecommendationKind.track) {
        final artistKey =
            SearchNormalizer.normalizeString(candidate.artist ?? '');
        final count = tracksPerArtist[artistKey] ?? 0;
        if (artistKey.isNotEmpty && count >= 2) continue;
        tracksPerArtist[artistKey] = count + 1;
        tracks.add(candidate);
      }
    }
    if (mix != MusicDiscoveryMix.balanced) {
      return (mix == MusicDiscoveryMix.tracks ? tracks : artists)
          .take(limit)
          .toList(growable: false);
    }
    final trackTarget = limit ~/ 2;
    final artistTarget = limit - trackTarget;
    final trackCount =
        tracks.length < trackTarget ? tracks.length : trackTarget;
    final artistCount =
        artists.length < artistTarget ? artists.length : artistTarget;
    final selected = <_CandidateAccumulator>[
      ...tracks.take(trackCount),
      ...artists.take(artistCount),
    ];
    final remaining = limit - selected.length;
    if (remaining > 0) {
      if (tracks.length > trackCount) {
        selected.addAll(tracks.skip(trackCount).take(remaining));
      } else if (artists.length > artistCount) {
        selected.addAll(artists.skip(artistCount).take(remaining));
      }
    }
    selected.sort(_compareCandidates);
    return selected;
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
  static const int _minOwnedTracksForArtist = 3;
  static const int _minTracksForAlbumArtist = 2;

  _OwnedMusicIndex(Iterable<OwnedMusicTrack> tracks) {
    final albumTracks = <String, Set<String>>{};
    for (final track in tracks) {
      final artist = SearchNormalizer.normalizeString(track.artist);
      if (artist.isEmpty) continue;
      _artistTrackCounts[artist] = (_artistTrackCounts[artist] ?? 0) + 1;
      final titleKey = SearchNormalizer.normalizeString(track.title);
      for (final title in _titleVariants(track.title)) {
        songs.add('$artist|$title');
      }
      final album = SearchNormalizer.normalizeString(track.album ?? '');
      final albumArtist = SearchNormalizer.normalizeString(
        track.albumArtist ?? track.artist,
      );
      if (album.isNotEmpty && albumArtist.isNotEmpty) {
        final albumKey = '$albumArtist|$album';
        albums.add(albumKey);
        final titles = albumTracks.putIfAbsent(albumKey, () => <String>{});
        titles.add(titleKey.isEmpty ? '${titles.length}' : titleKey);
        if (titles.length >= _minTracksForAlbumArtist &&
            albumArtist != 'various artists') {
          _multiTrackAlbumArtists.add(albumArtist);
        }
      }
    }
  }

  final Map<String, int> _artistTrackCounts = <String, int>{};
  final Set<String> _multiTrackAlbumArtists = <String>{};
  final Set<String> songs = <String>{};
  final Set<String> albums = <String>{};

  bool contains(MusicRecommendationKind kind, String name, String? artist) {
    if (kind == MusicRecommendationKind.artist) {
      final key = SearchNormalizer.normalizeString(name);
      return (_artistTrackCounts[key] ?? 0) >= _minOwnedTracksForArtist ||
          _multiTrackAlbumArtists.contains(key);
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
