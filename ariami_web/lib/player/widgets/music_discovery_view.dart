import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/services/recommendations/music_discovery_api_key_config.dart';
import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:ariami_core/services/stats/stats_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/music_discovery_controller.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'music_discovery_cards.dart';

class MusicDiscoveryView extends StatelessWidget {
  const MusicDiscoveryView({super.key});

  static bool _isValidWebhookUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || utf8.encode(normalized).length > 512) {
      return false;
    }
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _showSetup(
    BuildContext context,
    MusicDiscoveryController discovery,
  ) async {
    final apiKeyState = discovery.apiKeyState;
    final preferences = discovery.preferences;
    final needsPersonalKey = !discovery.isEmbeddedApiKey;
    final controller =
        TextEditingController(text: apiKeyState.effectiveKey ?? '');
    final webhookController =
        TextEditingController(text: discovery.webhookUrl ?? '');
    final canManageWebhook = discovery.canManageHousehold;
    final lidarrUrl = discovery.feedUrlFor(format: 'lidarr');
    final textUrl = discovery.feedUrlFor(format: 'text');
    String? copiedNotice;
    var obscure = true;
    var keyTouched = false;
    var selectedMix = preferences.mix;
    var selectedLimit = preferences.resultLimit;
    var selectedRange = MusicDiscoveryPreferences.tasteRangeChoices
            .contains(preferences.tasteRange)
        ? preferences.tasteRange
        : StatsRange.all;
    var selectedDepth = preferences.seedDepth;
    final selectedTags = <String>{...preferences.preferredTags};
    final libraryTags = splitMusicDiscoveryGenreTags(
      context.read<LibraryController>().songs.map((song) => song.genre),
    );
    var instrumentalOnly = preferences.instrumentalOnly;
    final result = await showDialog<_SetupResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final trimmedKey = controller.text.trim();
          final keyTooLong = needsPersonalKey &&
              utf8.encode(trimmedKey).length >
                  MusicDiscoveryApiKeyConfig.maxApiKeyBytes;
          final keyMissing = needsPersonalKey && trimmedKey.isEmpty;
          final keyErrorText = keyTooLong
              ? 'API key must be at most ${MusicDiscoveryApiKeyConfig.maxApiKeyBytes} bytes.'
              : (keyMissing && keyTouched ? 'Enter a Last.fm API key.' : null);
          final trimmedWebhook = webhookController.text.trim();
          final webhookInvalid = canManageWebhook &&
              trimmedWebhook.isNotEmpty &&
              !_isValidWebhookUrl(trimmedWebhook);
          final webhookErrorText = webhookInvalid
              ? 'Enter a valid http:// or https:// URL.'
              : null;
          final canSubmit =
              (!needsPersonalKey || (!keyMissing && !keyTooLong)) &&
                  !webhookInvalid;
          return AlertDialog(
            scrollable: true,
            title: const Text('Private music discovery'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ariami sends only your selected exploration tags and a '
                    'handful of favourite artist and track names to Last.fm. '
                    'It never uploads listening history, playlists, account '
                    'details, or your full library.',
                  ),
                  const SizedBox(height: 14),
                  if (needsPersonalKey) ...[
                    TextField(
                      controller: controller,
                      obscureText: obscure,
                      readOnly: apiKeyState.isHouseholdManaged &&
                          !apiKeyState.canManageHousehold,
                      onChanged: (_) => setDialogState(() => keyTouched = true),
                      decoration: InputDecoration(
                        labelText: 'Last.fm API key',
                        errorText: keyErrorText,
                        helperText: apiKeyState.isHouseholdManaged
                            ? apiKeyState.canManageHousehold
                                ? 'Shared by your Ariami server with signed-in devices.'
                                : 'Synced from this Ariami server by its owner.'
                            : apiKeyState.canManageHousehold
                                ? 'Saving shares this key with your signed-in Ariami devices.'
                                : 'Stored locally unless the server owner shares a key.',
                        suffixIcon: IconButton(
                          tooltip: obscure ? 'Show API key' : 'Hide API key',
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _open(
                        context,
                        Uri.parse('https://www.last.fm/api/account/create'),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Get a personal API key'),
                    ),
                    Text(
                      'A Last.fm developer account is only needed to obtain the '
                      'key; Ariami never signs into it.',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if ((apiKeyState.canManageHousehold &&
                            apiKeyState.isHouseholdManaged) ||
                        discovery.hasLocalKey)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (apiKeyState.canManageHousehold &&
                              apiKeyState.isHouseholdManaged)
                            TextButton.icon(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                const _SetupResult.removeHouseholdKey(),
                              ),
                              icon: const Icon(Icons.link_off_rounded, size: 16),
                              label: const Text('Remove shared key'),
                            ),
                          if (discovery.hasLocalKey)
                            TextButton.icon(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                const _SetupResult.clearLocalKey(),
                              ),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('Clear local key'),
                            ),
                        ],
                      ),
                  ] else
                    const Text(
                      'This build includes an Ariami Last.fm API key. Enabling '
                      'discovery is still your choice.',
                    ),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Recommendations',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<MusicDiscoveryMix>(
                    key: ValueKey(selectedMix),
                    initialValue: selectedMix,
                    decoration: const InputDecoration(labelText: 'Show'),
                    items: MusicDiscoveryMix.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_mixLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedMix = value;
                          if (value != MusicDiscoveryMix.tracks) {
                            instrumentalOnly = false;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedLimit,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem(
                          value: 12, child: Text('Compact · up to 12')),
                      DropdownMenuItem(
                          value: 24, child: Text('Standard · up to 24')),
                      DropdownMenuItem(
                          value: 36, child: Text('More · up to 36')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedLimit = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('Refine suggestions',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Instrumental only'),
                    subtitle: const Text(
                      "Explores Last.fm's instrumental pool and keeps only "
                      'tracks with explicit instrumental evidence.',
                    ),
                    value: instrumentalOnly,
                    onChanged: (value) => setDialogState(() {
                      instrumentalOnly = value;
                      if (value) selectedMix = MusicDiscoveryMix.tracks;
                    }),
                  ),
                  Text(
                    'Explore tags',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _MusicTagPicker(
                    selectedTags: selectedTags,
                    libraryTags: libraryTags,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tags choose the Last.fm music Ariami explores. Multiple '
                    'tags broaden the results; Instrumental remains an extra '
                    'requirement. Library genres gently rank matching results '
                    'and appear here as suggestions; they never limit you.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StatsRange>(
                    initialValue: selectedRange,
                    decoration: const InputDecoration(labelText: 'Taste from'),
                    items: MusicDiscoveryPreferences.tasteRangeChoices
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                MusicDiscoveryPreferences.tasteRangeLabel(
                                  value,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedRange = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDepth,
                    decoration: const InputDecoration(labelText: 'Taste depth'),
                    items: MusicDiscoveryPreferences.seedDepthChoices
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_depthLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedDepth = value);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Deeper reaches further down your favourites, so results '
                    'get broader and refreshing takes longer.',
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Wishlist automation',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (lidarrUrl != null && textUrl != null) ...[
                    Text(
                      'Copy a server feed URL for Lidarr Custom Lists or MusicGrabber.',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            unawaited(
                              Clipboard.setData(ClipboardData(text: lidarrUrl)),
                            );
                            setDialogState(
                              () => copiedNotice = 'Lidarr JSON URL copied.',
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy Lidarr URL'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            unawaited(
                              Clipboard.setData(ClipboardData(text: textUrl)),
                            );
                            setDialogState(
                              () => copiedNotice = 'Text list URL copied.',
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy Text URL'),
                        ),
                      ],
                    ),
                    if (copiedNotice != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        copiedNotice!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      'Connect to your Ariami server to copy wishlist feed URLs.',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  if (canManageWebhook) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: webhookController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Webhook URL (optional)',
                        hintText: 'https://example.com/webhook',
                        errorText: webhookErrorText,
                        helperText:
                            'Receives a JSON POST whenever you bookmark an item.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Last.fm does not receive an Ariami login and Ariami does '
                    'not scrobble. Last.fm and MusicBrainz terms still apply.',
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              if (discovery.enabled)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, const _SetupResult.disable()),
                  child: const Text('Disable'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () {
                        Navigator.pop(
                          dialogContext,
                          _SetupResult.enable(
                            needsPersonalKey ? trimmedKey : null,
                            MusicDiscoveryPreferences(
                              mix: selectedMix,
                              resultLimit: selectedLimit,
                              tasteRange: selectedRange,
                              seedDepth: selectedDepth,
                              preferredTags: selectedTags,
                              instrumentalOnly: instrumentalOnly,
                            ),
                            webhookUrl: canManageWebhook ? trimmedWebhook : null,
                          ),
                        );
                      }
                    : null,
                child: Text(discovery.enabled ? 'Save' : 'Enable'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    webhookController.dispose();
    if (result == null) return;
    switch (result.action) {
      case _SetupAction.removeHouseholdKey:
        await discovery.removeHouseholdKey();
      case _SetupAction.clearLocalKey:
        await discovery.clearLocalKey();
      case _SetupAction.disable:
        await discovery.disable();
      case _SetupAction.enable:
        await discovery.applySetupEnable(
          personalKey: result.apiKey,
          preferences: result.preferences,
        );
        if (canManageWebhook &&
            (result.webhookUrl ?? '') != (discovery.webhookUrl ?? '')) {
          final webhookError =
              await discovery.saveWebhookUrl(result.webhookUrl);
          if (webhookError != null && context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(webhookError)),
            );
          }
        }
    }
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Could not open that link.')),
    );
  }

  void _openArtist(BuildContext context, String artistName) {
    context.read<PlayerNavigator>().openArtist(artistName);
  }

  void _searchInAriami(BuildContext context, MusicRecommendation item) {
    final holder = context.read<SearchQueryHolder?>();
    if (holder != null) {
      holder.selectedIndex.value = -1;
      holder.query.value = item.kind == MusicRecommendationKind.artist
          ? item.name
          : '${item.artist ?? ''} ${item.name}'.trim();
    }
    context.read<PlayerNavigator>().go(PlayerView.search);
  }

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<MusicDiscoveryController>();
    if (discovery.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!discovery.enabled || !discovery.hasApiKey) {
      return _buildOptIn(context, discovery);
    }

    final isOffline = context.select<ConnectionController, bool>(
      (c) => c.isOfflineActive || !c.isConnected,
    );
    final snapshot = discovery.snapshot;
    final songs = context.watch<LibraryController>().songs;
    final libraryArtists = context.watch<LibraryController>().artists;
    final artistsByLower = <String, String>{
      for (final artist in libraryArtists)
        artist.name.trim().toLowerCase(): artist.name,
    };
    String? matchedArtistFor(MusicRecommendation item) {
      final candidate =
          item.kind == MusicRecommendationKind.artist ? item.name : item.artist;
      if (candidate == null) return null;
      return artistsByLower[candidate.trim().toLowerCase()];
    }

    final savedOnly = discovery.showSavedOnly;
    final tracks = savedOnly
        ? discovery.wishlist
            .where((item) => item.kind == MusicRecommendationKind.track)
            .toList(growable: false)
        : snapshot == null
            ? const <MusicRecommendation>[]
            : discovery.visibleRecommendations(snapshot.tracks);
    final artists = savedOnly
        ? discovery.wishlist
            .where((item) => item.kind == MusicRecommendationKind.artist)
            .toList(growable: false)
        : snapshot == null
            ? const <MusicRecommendation>[]
            : discovery.visibleRecommendations(snapshot.artists);
    final albums = savedOnly
        ? discovery.wishlist
            .where((item) => item.kind == MusicRecommendationKind.album)
            .toList(growable: false)
        : snapshot == null
            ? const <MusicRecommendation>[]
            : discovery.visibleRecommendations(snapshot.albums);
    final hasVisible =
        tracks.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty;
    final allDismissed = !savedOnly &&
        snapshot != null &&
        snapshot.recommendations.isNotEmpty &&
        !hasVisible;

    final (errorActionLabel, errorAction) = switch (discovery.errorKind) {
      DiscoveryErrorKind.invalidApiKey => (
          'Update API key',
          () => unawaited(_showSetup(context, discovery)),
        ),
      DiscoveryErrorKind.rateLimited || DiscoveryErrorKind.general => (
          isOffline ? null : 'Retry',
          isOffline ? null : () => unawaited(discovery.refresh(force: true)),
        ),
    };

    return CustomScrollView(
      key: const PageStorageKey<String>('music_discovery_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(
            context,
            discovery,
            snapshot,
            isOffline: isOffline,
          ),
        ),
        if (!savedOnly && isOffline && snapshot != null)
          const SliverToBoxAdapter(
            child: _NoticeBanner(
              icon: Icons.cloud_off_rounded,
              message: 'Offline — showing cached results.',
            ),
          ),
        if (!savedOnly && discovery.error != null)
          SliverToBoxAdapter(
            child: _ErrorBanner(
              message: discovery.error!,
              actionLabel: errorActionLabel,
              onAction: errorAction,
            ),
          ),
        if (!savedOnly && discovery.refreshing && snapshot == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!savedOnly && discovery.error != null && snapshot == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.shrink(),
          )
        else if (!savedOnly && isOffline && snapshot == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _OfflineDiscovery(),
          )
        else if (!savedOnly && discovery.coldStart && snapshot == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ColdStartDiscovery(
              isAllTime: discovery.preferences.tasteRange.isAllTime,
              rangeTitle: discovery.preferences.tasteRange.title(),
              quickTags: _quickStartTags(songs.map((song) => song.genre)),
              onSelectTag: (tag) => unawaited(
                discovery.applyPreferences(
                  discovery.preferences.copyWith(
                    preferredTags: <String>{
                      ...discovery.preferences.preferredTags,
                      tag,
                    },
                  ),
                ),
              ),
              onUseAllTime: () => unawaited(
                discovery.applyPreferences(
                  discovery.preferences.copyWith(tasteRange: StatsRange.all),
                ),
              ),
              onBrowseLibrary: () =>
                  context.read<PlayerNavigator>().go(PlayerView.home),
            ),
          )
        else if ((!savedOnly && snapshot == null) || !hasVisible)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyDiscovery(
              onRefresh: () => unawaited(discovery.refresh()),
              onAdjustFilters: () => unawaited(_showSetup(context, discovery)),
              onRestoreDismissed: allDismissed
                  ? () => unawaited(discovery.clearDismissed())
                  : null,
            ),
          )
        else ...[
          if (tracks.isNotEmpty)
            RecommendationSection(
              title: savedOnly ? 'SAVED TRACKS' : 'TRACKS TO FIND',
              items: tracks,
              matchedArtistFor: matchedArtistFor,
              isWishlisted: discovery.isWishlisted,
              onToggleWishlist: (item) =>
                  unawaited(discovery.toggleWishlist(item)),
              onOpenExternal: (uri) => unawaited(_open(context, uri)),
              onOpenArtist: (artist) => _openArtist(context, artist),
              onSearch: (item) => _searchInAriami(context, item),
              onDismiss: savedOnly
                  ? null
                  : (item) => unawaited(discovery.dismiss(item)),
            ),
          if (artists.isNotEmpty)
            RecommendationSection(
              title: savedOnly ? 'SAVED ARTISTS' : 'ARTISTS TO EXPLORE',
              items: artists,
              matchedArtistFor: matchedArtistFor,
              isWishlisted: discovery.isWishlisted,
              onToggleWishlist: (item) =>
                  unawaited(discovery.toggleWishlist(item)),
              onOpenExternal: (uri) => unawaited(_open(context, uri)),
              onOpenArtist: (artist) => _openArtist(context, artist),
              onSearch: (item) => _searchInAriami(context, item),
              onDismiss: savedOnly
                  ? null
                  : (item) => unawaited(discovery.dismiss(item)),
            ),
          if (albums.isNotEmpty)
            RecommendationSection(
              title: savedOnly ? 'SAVED ALBUMS' : 'ALBUMS TO TRY',
              items: albums,
              matchedArtistFor: matchedArtistFor,
              isWishlisted: discovery.isWishlisted,
              onToggleWishlist: (item) =>
                  unawaited(discovery.toggleWishlist(item)),
              onOpenExternal: (uri) => unawaited(_open(context, uri)),
              onOpenArtist: (artist) => _openArtist(context, artist),
              onSearch: (item) => _searchInAriami(context, item),
              onDismiss: savedOnly
                  ? null
                  : (item) => unawaited(discovery.dismiss(item)),
            ),
          SliverToBoxAdapter(
            child: _Attribution(onOpen: (uri) => unawaited(_open(context, uri))),
          ),
        ],
      ],
    );
  }

  static List<String> _quickStartTags(Iterable<String?> genres) {
    final library = splitMusicDiscoveryGenreTags(genres).toList()..sort();
    return <String>{
      ...library,
      ...MusicDiscoveryPreferences.commonTags,
    }.take(8).toList(growable: false);
  }

  Widget _buildOptIn(
    BuildContext context,
    MusicDiscoveryController discovery,
  ) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Icon(Icons.explore_rounded,
                    size: 58, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(height: 18),
                const Text('Discover music from your Ariami listening',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  'Recommendations use your private, locally calculated favourites. '
                  'Only selected seed names or exploration tags leave Ariami; '
                  'there is no scrobbling and no Last.fm account connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.colors.textSecondary, height: 1.45),
                ),
                if (discovery.error != null) ...[
                  const SizedBox(height: 18),
                  _InlineSetupError(message: discovery.error!),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: discovery.hasApiKey
                          ? () => unawaited(discovery.enableImmediately())
                          : () => unawaited(_showSetup(context, discovery)),
                      icon: const Icon(Icons.explore_rounded),
                      label: Text(discovery.hasApiKey
                          ? 'Enable music discovery'
                          : 'Add API key and enable'),
                    ),
                    if (discovery.hasApiKey)
                      OutlinedButton(
                        onPressed: () =>
                            unawaited(_showSetup(context, discovery)),
                        child: const Text('Customize'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildHeader(
    BuildContext context,
    MusicDiscoveryController discovery,
    MusicRecommendationSnapshot? snapshot, {
    required bool isOffline,
  }) {
    final colors = context.colors;
    final preferences = discovery.preferences;
    final tags = preferences.preferredTags.toList()..sort();
    final seedCount = snapshot == null
        ? 0
        : snapshot.artistSeeds.length + snapshot.trackSeeds.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondary
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
                ),
                child: Icon(
                  Icons.explore_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discover',
                      style: PlayerTheme.display(
                        44,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot == null
                          ? 'New music based on what you actually listen to · '
                              '${_preferenceSummary(preferences)}'
                          : 'Based on $seedCount private taste seeds · '
                              '${_preferenceSummary(preferences)} · '
                              'updated ${_relativeTime(snapshot.generatedAt)}',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Discovery preferences',
                    onPressed: () => unawaited(_showSetup(context, discovery)),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: discovery.refreshing || isOffline
                        ? null
                        : () => unawaited(discovery.refresh()),
                    icon: discovery.refreshing
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final mix in MusicDiscoveryMix.values)
                ChoiceChip(
                  label: Text(_mixChipLabel(mix)),
                  selected: !discovery.showSavedOnly && preferences.mix == mix,
                  onSelected: (selected) {
                    if (!selected) return;
                    discovery.setShowSavedOnly(false);
                    if (preferences.mix != mix) {
                      unawaited(
                        discovery.applyPreferences(
                          preferences.copyWith(mix: mix),
                        ),
                      );
                    }
                  },
                ),
              if (discovery.wishlist.isNotEmpty || discovery.showSavedOnly)
                FilterChip(
                  avatar: const Icon(Icons.bookmark_rounded, size: 16),
                  label: Text('Saved (${discovery.wishlist.length})'),
                  selected: discovery.showSavedOnly,
                  onSelected: discovery.setShowSavedOnly,
                ),
              if (preferences.instrumentalOnly)
                InputChip(
                  label: const Text('Instrumental'),
                  onDeleted: () => unawaited(
                    discovery.applyPreferences(
                      preferences.copyWith(instrumentalOnly: false),
                    ),
                  ),
                ),
              for (final tag in tags)
                InputChip(
                  label: Text(musicDiscoveryTagLabel(tag)),
                  onDeleted: () {
                    final nextTags = <String>{...preferences.preferredTags}
                      ..remove(tag);
                    unawaited(
                      discovery.applyPreferences(
                        preferences.copyWith(preferredTags: nextTags),
                      ),
                    );
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Tag'),
                tooltip: 'Add or edit exploration tags',
                onPressed: () => unawaited(_showSetup(context, discovery)),
              ),
              if (seedCount > 0)
                ActionChip(
                  avatar: Icon(
                    discovery.showSeeds
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                  ),
                  label: Text('$seedCount seeds'),
                  tooltip: discovery.showSeeds
                      ? 'Hide taste seeds used'
                      : 'Show taste seeds used',
                  onPressed: discovery.toggleShowSeeds,
                ),
              if (discovery.dismissedKeys.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(discovery.clearDismissed()),
                  child: Text('Restore ${discovery.dismissedKeys.length} hidden'),
                ),
            ],
          ),
          if (discovery.showSeeds && snapshot != null && seedCount > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final artist in snapshot.artistSeeds)
                  _SeedPill(
                    icon: Icons.person_outline_rounded,
                    label: artist,
                  ),
                for (final track in snapshot.trackSeeds)
                  _SeedPill(
                    icon: Icons.music_note_rounded,
                    label: track,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().toUtc().difference(value.toUtc());
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _InlineSetupError extends StatelessWidget {
  const _InlineSetupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      );
}

class _SetupResult {
  const _SetupResult.enable(
    this.apiKey,
    this.preferences, {
    this.webhookUrl,
  }) : action = _SetupAction.enable;
  const _SetupResult.disable()
      : action = _SetupAction.disable,
        apiKey = null,
        webhookUrl = null,
        preferences = const MusicDiscoveryPreferences();
  const _SetupResult.removeHouseholdKey()
      : action = _SetupAction.removeHouseholdKey,
        apiKey = null,
        webhookUrl = null,
        preferences = const MusicDiscoveryPreferences();
  const _SetupResult.clearLocalKey()
      : action = _SetupAction.clearLocalKey,
        apiKey = null,
        webhookUrl = null,
        preferences = const MusicDiscoveryPreferences();

  final _SetupAction action;
  final String? apiKey;
  final String? webhookUrl;
  final MusicDiscoveryPreferences preferences;
}

enum _SetupAction { enable, disable, removeHouseholdKey, clearLocalKey }

class _SeedPill extends StatelessWidget {
  const _SeedPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _mixChipLabel(MusicDiscoveryMix mix) => switch (mix) {
      MusicDiscoveryMix.balanced => 'Balanced',
      MusicDiscoveryMix.tracks => 'Tracks',
      MusicDiscoveryMix.artists => 'Artists',
      MusicDiscoveryMix.albums => 'Albums',
    };

String _mixLabel(MusicDiscoveryMix mix) => switch (mix) {
      MusicDiscoveryMix.balanced => 'Balanced · tracks and artists',
      MusicDiscoveryMix.tracks => 'Tracks only',
      MusicDiscoveryMix.artists => 'Artists only',
      MusicDiscoveryMix.albums => 'Albums only',
    };

String _depthLabel(int depth) => switch (depth) {
      3 => 'Focused · top 3 artists and tracks',
      6 => 'Wider · top 6 artists and tracks',
      _ => 'Deepest · top $depth artists and tracks',
    };

String _preferenceSummary(MusicDiscoveryPreferences preferences) {
  final mix = switch (preferences.mix) {
    MusicDiscoveryMix.balanced => 'Balanced',
    MusicDiscoveryMix.tracks => 'Tracks',
    MusicDiscoveryMix.artists => 'Artists',
    MusicDiscoveryMix.albums => 'Albums',
  };
  final tags = preferences.preferredTags.toList()..sort();
  final refinement = <String>[
    if (preferences.instrumentalOnly) 'Instrumental',
    if (tags.isNotEmpty)
      tags.length <= 2
          ? tags.map(musicDiscoveryTagLabel).join(', ')
          : '${tags.take(2).map(musicDiscoveryTagLabel).join(', ')} '
              '+${tags.length - 2}',
  ];
  return '$mix${refinement.isEmpty ? '' : ' · ${refinement.join(' · ')}'} · '
      '${preferences.resultLimit} max · '
      '${MusicDiscoveryPreferences.tasteRangeLabel(preferences.tasteRange)} · '
      'depth ${preferences.seedDepth}';
}

class _MusicTagPicker extends StatefulWidget {
  const _MusicTagPicker({
    required this.selectedTags,
    required this.libraryTags,
  });

  final Set<String> selectedTags;
  final Set<String> libraryTags;

  @override
  State<_MusicTagPicker> createState() => _MusicTagPickerState();
}

class _MusicTagPickerState extends State<_MusicTagPicker> {
  final _controller = TextEditingController();
  String _query = '';

  void _add(String value) {
    final tag = normalizeMusicDiscoveryTag(value);
    if (tag.isEmpty) return;
    setState(() {
      widget.selectedTags.add(tag);
      _controller.clear();
      _query = '';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matching = <String>{
      ...widget.libraryTags,
      ...MusicDiscoveryPreferences.commonTags,
    }
        .where((tag) {
          return !widget.selectedTags.contains(tag) &&
              (_query.isEmpty || tag.contains(_query));
        })
        .toList()
      ..sort();
    final suggestions = matching.take(18).toList(growable: false);
    final selected = widget.selectedTags.toList()..sort();
    final entered = normalizeMusicDiscoveryTag(_controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Search or add any Last.fm tag',
            hintText: 'For example: fusion',
            suffixIcon: IconButton(
              tooltip: 'Add tag',
              onPressed: entered.isEmpty ? null : () => _add(entered),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          onChanged: (value) => setState(
            () => _query = normalizeMusicDiscoveryTag(value),
          ),
          onSubmitted: _add,
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: selected
                .map((tag) => InputChip(
                      label: Text(musicDiscoveryTagLabel(tag)),
                      onDeleted: () => setState(
                        () => widget.selectedTags.remove(tag),
                      ),
                    ))
                .toList(),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: suggestions
                .map((tag) => ActionChip(
                      avatar: widget.libraryTags.contains(tag)
                          ? const Icon(Icons.library_music_rounded, size: 16)
                          : null,
                      label: Text(musicDiscoveryTagLabel(tag)),
                      tooltip: widget.libraryTags.contains(tag)
                          ? 'Found in your library metadata'
                          : 'Common Last.fm tag',
                      onPressed: () => _add(tag),
                    ))
                .toList(),
          ),
        ] else if (_query.isNotEmpty && !widget.selectedTags.contains(_query)) ...[
          const SizedBox(height: 8),
          Text(
            'Press Enter to add "$_query"',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ]),
        ),
      );
}

class _OfflineDiscovery extends StatelessWidget {
  const _OfflineDiscovery();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: context.colors.textSecondary),
            const SizedBox(height: 12),
            const Text('Connect to discover new music',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'No cached recommendations are saved for this filter.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
}

class _ColdStartDiscovery extends StatelessWidget {
  const _ColdStartDiscovery({
    required this.isAllTime,
    required this.rangeTitle,
    required this.quickTags,
    required this.onSelectTag,
    required this.onUseAllTime,
    required this.onBrowseLibrary,
  });

  final bool isAllTime;
  final String rangeTitle;
  final List<String> quickTags;
  final ValueChanged<String> onSelectTag;
  final VoidCallback onUseAllTime;
  final VoidCallback onBrowseLibrary;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_outlined,
                    size: 48, color: context.colors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  isAllTime
                      ? 'Pick a genre to start exploring'
                      : 'No listening recorded in $rangeTitle',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  isAllTime
                      ? 'Ariami does not have listening favourites yet. Choose '
                          'a tag below to discover music right away, or listen '
                          'in your library first.'
                      : 'Try exploring a tag below, or switch back to all-time listening.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                if (quickTags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in quickTags)
                        ActionChip(
                          label: Text(musicDiscoveryTagLabel(tag)),
                          onPressed: () => onSelectTag(tag),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!isAllTime)
                      FilledButton(
                        onPressed: onUseAllTime,
                        child: const Text('Use all-time listening'),
                      ),
                    OutlinedButton(
                      onPressed: onBrowseLibrary,
                      child: const Text('Browse library'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _EmptyDiscovery extends StatelessWidget {
  const _EmptyDiscovery({
    required this.onRefresh,
    required this.onAdjustFilters,
    this.onRestoreDismissed,
  });
  final VoidCallback onRefresh;
  final VoidCallback onAdjustFilters;
  final VoidCallback? onRestoreDismissed;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_rounded,
                size: 48, color: context.colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              onRestoreDismissed != null
                  ? 'All recommendations hidden'
                  : 'No unowned matches yet',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              onRestoreDismissed != null
                  ? 'Restore hidden recommendations or refresh for new ones.'
                  : 'Try changing your refinements or refresh later.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                if (onRestoreDismissed != null)
                  FilledButton(
                    onPressed: onRestoreDismissed,
                    child: const Text('Restore hidden'),
                  ),
                OutlinedButton(
                  onPressed: onAdjustFilters,
                  child: const Text('Adjust filters'),
                ),
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.onOpen});

  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 30),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 15),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Ranked by Last.fm · identities assisted by MusicBrainz · full history stays in Ariami',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => onOpen(Uri.parse('https://www.last.fm')),
              child: const Text('Powered by Last.fm'),
            ),
            TextButton(
              onPressed: () => onOpen(Uri.parse('https://musicbrainz.org')),
              child: const Text('MusicBrainz'),
            ),
          ],
        ),
      );
}
