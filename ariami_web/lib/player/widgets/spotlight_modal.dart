import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/services/search/search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/ariami_connect_controller.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../services/theme_controller.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'artwork_image_provider.dart';
import 'hover_builder.dart';
import 'hover_surface.dart';
import 'now_playing_full_view.dart';
import 'playlist_artwork.dart';
import 'search_view.dart';

/// Text shown inside the top search bar advertising the Spotlight shortcut.
String spotlightShortcutHint({bool? isMacOS}) =>
    (isMacOS ?? defaultTargetPlatform == TargetPlatform.macOS)
        ? '⌘K'
        : 'Ctrl+K';

/// True when [event] is the Cmd+K (macOS) or Ctrl+K (Windows/Linux) shortcut.
bool isSpotlightShortcut(KeyEvent event, {bool? isMacOS}) {
  final key = event.logicalKey;
  final physical = event.physicalKey;
  if (key != LogicalKeyboardKey.keyK && physical != PhysicalKeyboardKey.keyK) {
    return false;
  }
  final keyboard = HardwareKeyboard.instance;
  final mac = isMacOS ?? defaultTargetPlatform == TargetPlatform.macOS;
  return mac ? keyboard.isMetaPressed : keyboard.isControlPressed;
}

bool _spotlightOpen = false;

/// Opens the floating Spotlight quick-navigation modal if not already open.
Future<void> showSpotlightModal(
  BuildContext context, {
  VoidCallback? onBeforeNavigate,
}) {
  if (_spotlightOpen) return Future<void>.value();
  _spotlightOpen = true;

  final shellContext = context;
  final audio = context.read<AudioController>();
  final connection = context.read<ConnectionController>();
  final library = context.read<LibraryController>();
  final navigator = context.read<PlayerNavigator>();
  final host = maybeReadHost(context);
  final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
      maybeReadProvider<PlayerDownloadsBridge>(context);
  final connect = maybeReadProvider<AriamiConnectController?>(context) ??
      maybeReadProvider<AriamiConnectController>(context);
  final theme = maybeReadProvider<ThemeController?>(context) ??
      maybeReadProvider<ThemeController>(context);
  final queryHolder = maybeReadProvider<SearchQueryHolder?>(context) ??
      maybeReadProvider<SearchQueryHolder>(context);
  final capturedTheme = Theme.of(context);

  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close Spotlight',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: Motion.fast,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final modal = SpotlightModal(
        shellContext: shellContext,
        onBeforeNavigate: onBeforeNavigate,
      );
      return MultiProvider(
        providers: [
          if (host != null) ...[
            Provider<PlayerHost>.value(value: host),
            Provider<PlayerHost?>.value(value: host),
          ],
          ChangeNotifierProvider<AudioController>.value(value: audio),
          ChangeNotifierProvider<ConnectionController>.value(value: connection),
          ChangeNotifierProvider<LibraryController>.value(value: library),
          ChangeNotifierProvider<PlayerNavigator>.value(value: navigator),
          ChangeNotifierProvider<PlayerDownloadsBridge?>.value(value: downloads),
          if (connect != null)
            ChangeNotifierProvider<AriamiConnectController>.value(
              value: connect,
            ),
          if (theme != null)
            ChangeNotifierProvider<ThemeController>.value(value: theme),
          if (queryHolder != null)
            Provider<SearchQueryHolder>.value(value: queryHolder),
        ],
        child: theme != null
            ? Consumer<ThemeController>(
                builder: (context, themeCtrl, child) {
                  final data = themeCtrl.themeMode == ThemeMode.light
                      ? themeCtrl.lightTheme
                      : themeCtrl.darkTheme;
                  return AnimatedTheme(
                    data: data,
                    duration: const Duration(milliseconds: 400),
                    child: child!,
                  );
                },
                child: modal,
              )
            : Theme(data: capturedTheme, child: modal),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        Motion.fadeScale(child, animation),
  ).whenComplete(() {
    _spotlightOpen = false;
  });
}

class SpotlightModal extends StatefulWidget {
  const SpotlightModal({
    super.key,
    required this.shellContext,
    this.onBeforeNavigate,
  });

  static const Duration searchDebounce = Duration(milliseconds: 120);
  static const double topOffset = 96;

  final BuildContext shellContext;
  final VoidCallback? onBeforeNavigate;

  @override
  State<SpotlightModal> createState() => _SpotlightModalState();
}

class _SpotlightModalState extends State<SpotlightModal> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'SpotlightSearchField');
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  Timer? _debounceTimer;
  String _query = '';
  int _selectedIndex = 0;

  String? _cachedSectionsQuery;
  List<Track>? _cachedRecentSearches;
  List<Track>? _cachedSongs;
  List<Album>? _cachedAlbums;
  List<PlaylistSummary>? _cachedPlaylists;
  LibraryCurationFilter? _cachedCurationFilter;
  bool? _cachedIsLocalServer;
  bool? _cachedHasCurrentTrack;
  bool? _cachedRightPanelOpen;
  bool? _cachedSidebarCollapsed;
  dynamic _cachedClient;
  LibrarySearchResults? _cachedLibraryResults;
  List<_SpotlightSection> _cachedSections = const <_SpotlightSection>[];

  LibrarySearchResults _libraryResults = LibrarySearchResults.empty;
  (
    String,
    List<Track>,
    List<Album>,
    List<PlaylistSummary>
  )? _librarySearchInputs;
  Future<void> _librarySearch = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryInputChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      if (_query.isNotEmpty) {
        setState(() {
          _query = '';
          _selectedIndex = 0;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      return;
    }
    _debounceTimer = Timer(SpotlightModal.searchDebounce, () {
      if (!mounted || _query == value) return;
      setState(() {
        _query = value;
        _selectedIndex = 0;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Ensures any debounced text in [_controller] is applied immediately when
  /// the user presses Enter or ↑/↓ before the debounce timer fires.
  void _flushPendingQuery() {
    _debounceTimer?.cancel();
    if (_query == _controller.text) return;
    setState(() {
      _query = _controller.text;
      _selectedIndex = 0;
      // Starts the library search that keyboard actions then wait on.
      _ensureSections(context, listen: false);
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// Library results arrive from the search worker; keyboard actions wait
  /// for an in-flight search so they never act on stale rows.
  Future<void> _whenResultsReady(
    void Function(List<_SpotlightEntry> items) action,
  ) async {
    await _librarySearch;
    if (!mounted) return;
    final items = [
      for (final section in _ensureSections(context, listen: false))
        ...section.entries,
    ];
    if (items.isNotEmpty) action(items);
  }

  void _searchLibrary(
    LibraryController library,
    (String, List<Track>, List<Album>, List<PlaylistSummary>) inputs,
  ) {
    if (inputs == _librarySearchInputs) return;
    _librarySearchInputs = inputs;
    _librarySearch = library.searchAsync(inputs.$1).then((results) {
      if (!mounted || inputs != _librarySearchInputs) return;
      final client = context.read<ConnectionController>().client;
      if (client != null) {
        final albumIds = <String>{
          for (final a in results.albums.take(10)) a.id,
        };
        final songIds = <String>{};
        for (final t in results.songs.take(15)) {
          if (t.albumId != null && t.albumId!.isNotEmpty) {
            albumIds.add(t.albumId!);
          } else if (t.id.isNotEmpty) {
            songIds.add(t.id);
          }
        }
        if (albumIds.isNotEmpty || songIds.isNotEmpty) {
          unawaited(
            ArtworkImageProvider.prefetchBatch(
              client,
              albumIds: albumIds,
              songIds: songIds,
            ),
          );
        }
      }
      setState(() => _libraryResults = results);
    });
  }

  GlobalKey _keyFor(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'spotlight_$id'));

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || isSpotlightShortcut(event)) {
      if (event is KeyDownEvent) {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _flushPendingQuery();
      final down = key == LogicalKeyboardKey.arrowDown;
      _whenResultsReady((items) {
        final clamped = _selectedIndex.clamp(0, items.length - 1);
        final next = down
            ? (clamped + 1).clamp(0, items.length - 1)
            : (clamped - 1).clamp(0, items.length - 1);
        if (next != _selectedIndex) {
          setState(() => _selectedIndex = next);
          _scrollItemIntoView(items[next].id, down: down);
        }
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        _flushPendingQuery();
        _whenResultsReady(
          (items) =>
              _activate(items[_selectedIndex.clamp(0, items.length - 1)]),
        );
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollItemIntoView(String id, {required bool down}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _itemKeys[id]?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignmentPolicy: down
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _activate(_SpotlightEntry entry) {
    Navigator.of(context).pop();
    entry.onSelect();
  }

  void _navigateToView(PlayerView view) {
    widget.onBeforeNavigate?.call();
    context.read<PlayerNavigator>().go(view);
  }

  List<_SpotlightPageSpec> _pageSpecs(
    BuildContext context, {
    required PlayerHost? host,
    required bool isLocalServer,
    required bool hasCurrentTrack,
    required bool rightPanelOpen,
    required bool sidebarCollapsed,
  }) {
    final extra = host?.extraSettings;
    final hasDownloads = !isLocalServer && host?.downloads != null;
    final supportsUpdates = extra?.supportsUpdates ?? false;
    final hasLicense = extra?.buildLicenseSection(context) != null;
    final hasServer = isLocalServer && extra != null;
    return <_SpotlightPageSpec>[
      _SpotlightPageSpec(
        id: 'page:home',
        section: 'PAGES',
        title: 'Home',
        subtitle: 'Home • Highlights, pins & library overview',
        actionLabel: 'Go to page',
        icon: Icons.home_rounded,
        keywords: const [
          'home',
          'browse',
          'start',
          'main',
          'pinned',
          'jump back in'
        ],
        onSelect: () => _navigateToView(PlayerView.home),
      ),
      _SpotlightPageSpec(
        id: 'page:albums',
        section: 'PAGES',
        title: 'All Albums',
        subtitle: 'Library • Browse all albums',
        actionLabel: 'Go to page',
        icon: Icons.album_rounded,
        keywords: const ['albums', 'all albums', 'records', 'library'],
        onSelect: () => _navigateToView(PlayerView.albums),
      ),
      _SpotlightPageSpec(
        id: 'page:songs',
        section: 'PAGES',
        title: 'All Songs',
        subtitle: 'Library • Browse all songs',
        actionLabel: 'Go to page',
        icon: Icons.music_note_rounded,
        keywords: const ['songs', 'all songs', 'tracks', 'library'],
        onSelect: () => _navigateToView(PlayerView.songs),
      ),
      _SpotlightPageSpec(
        id: 'page:discovery',
        section: 'PAGES',
        title: 'Discover Music',
        subtitle: 'Explore • Recommendations & similar tracks',
        actionLabel: 'Go to page',
        icon: Icons.explore_rounded,
        keywords: const [
          'discover',
          'discovery',
          'explore',
          'recommendations',
          'for you'
        ],
        onSelect: () => _navigateToView(PlayerView.discovery),
      ),
      _SpotlightPageSpec(
        id: 'page:recently-played',
        section: 'PAGES',
        title: 'Recently Played',
        subtitle: 'History • Recently played tracks',
        actionLabel: 'Go to page',
        icon: Icons.history_rounded,
        keywords: const ['recently played', 'history', 'recent', 'past'],
        onSelect: () => _navigateToView(PlayerView.recentlyPlayed),
      ),
      _SpotlightPageSpec(
        id: 'page:search',
        section: 'PAGES',
        title: 'Search',
        subtitle: 'Search • Find songs, albums & playlists',
        actionLabel: 'Go to page',
        icon: Icons.search_rounded,
        keywords: const ['search', 'find', 'library search'],
        onSelect: () => _navigateToView(PlayerView.search),
      ),
      if (hasCurrentTrack)
        _SpotlightPageSpec(
          id: 'page:full-now-playing',
          section: 'PAGES',
          title: 'Now Playing (Full Screen)',
          subtitle: 'Player • Open full-screen now playing view',
          actionLabel: 'Open view',
          icon: Icons.open_in_full_rounded,
          keywords: const [
            'now playing',
            'full screen',
            'fullscreen',
            'player',
            'visualizer'
          ],
          onSelect: () {
            if (widget.shellContext.mounted) {
              unawaited(showFullNowPlaying(widget.shellContext));
            }
          },
        ),
      _SpotlightPageSpec(
        id: 'action:toggle-right-panel',
        section: 'PAGES',
        title: rightPanelOpen
            ? 'Hide Now Playing Panel'
            : 'Show Now Playing Panel',
        subtitle: 'Panel • Toggle the right-hand queue & now playing sidebar',
        actionLabel: 'Toggle panel',
        icon: rightPanelOpen
            ? Icons.view_sidebar_rounded
            : Icons.view_sidebar_outlined,
        keywords: const [
          'now playing',
          'queue',
          'panel',
          'right sidebar',
          'toggle'
        ],
        onSelect: () {
          widget.onBeforeNavigate?.call();
          context.read<PlayerNavigator>().toggleRightPanel();
        },
      ),
      _SpotlightPageSpec(
        id: 'action:toggle-sidebar',
        section: 'PAGES',
        title: sidebarCollapsed
            ? 'Expand Library Sidebar'
            : 'Collapse Library Sidebar',
        subtitle: 'Panel • Toggle the left library sidebar',
        actionLabel: 'Toggle sidebar',
        icon: Icons.library_music_rounded,
        keywords: const ['sidebar', 'library', 'collapse', 'expand', 'toggle'],
        onSelect: () {
          widget.onBeforeNavigate?.call();
          context.read<PlayerNavigator>().toggleSidebar();
        },
      ),
      _SpotlightPageSpec(
        id: 'settings:general',
        section: 'SETTINGS',
        title: 'Settings — General',
        subtitle: 'Settings • Window behaviour, privacy, search & quick jump',
        actionLabel: 'Open settings',
        icon: Icons.tune_rounded,
        keywords: const [
          'settings',
          'preferences',
          'general',
          'window',
          'close',
          'minimize',
          'tray',
          'privacy',
          'quick jump',
          'recent searches',
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'general'),
        ),
      ),
      _SpotlightPageSpec(
        id: 'settings:appearance',
        section: 'SETTINGS',
        title: 'Settings — Appearance',
        subtitle: 'Settings • Theme, colours & interface scale',
        actionLabel: 'Open settings',
        icon: Icons.palette_rounded,
        keywords: const [
          'settings',
          'appearance',
          'theme',
          'dark',
          'light',
          'color',
          'colour',
          'accent',
          'zoom',
          'scale',
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'appearance'),
        ),
      ),
      _SpotlightPageSpec(
        id: 'settings:playback',
        section: 'SETTINGS',
        title: 'Settings — Playback',
        subtitle: 'Settings • Equalizer, gapless playback & audio quality',
        actionLabel: 'Open settings',
        icon: Icons.headphones_rounded,
        keywords: const [
          'settings',
          'playback',
          'audio',
          'equalizer',
          'eq',
          'gapless',
          'quality',
          'streaming',
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'playback'),
        ),
      ),
      if (hasDownloads)
        _SpotlightPageSpec(
          id: 'settings:downloads',
          section: 'SETTINGS',
          title: 'Settings — Downloads',
          subtitle: 'Settings • Offline downloads & storage',
          actionLabel: 'Open settings',
          icon: Icons.download_rounded,
          keywords: const [
            'settings',
            'downloads',
            'offline',
            'storage',
            'cache'
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'downloads'),
          ),
        ),
      _SpotlightPageSpec(
        id: 'settings:listening-stats',
        section: 'SETTINGS',
        title: 'Settings — Listening Stats',
        subtitle: 'Settings • Top songs, artists, albums & play time',
        actionLabel: 'Open settings',
        icon: Icons.equalizer_rounded,
        keywords: const [
          'settings',
          'listening stats',
          'statistics',
          'stats',
          'top songs',
          'top artists',
          'playtime',
          'spotify',
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'listening-stats'),
        ),
      ),
      if (supportsUpdates)
        _SpotlightPageSpec(
          id: 'settings:updates',
          section: 'SETTINGS',
          title: 'Settings — Updates',
          subtitle: 'Settings • Check for updates & version info',
          actionLabel: 'Open settings',
          icon: Icons.system_update_alt_rounded,
          keywords: const ['settings', 'updates', 'version', 'upgrade'],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'updates'),
          ),
        ),
      _SpotlightPageSpec(
        id: 'settings:account',
        section: 'SETTINGS',
        title: 'Settings — Account',
        subtitle: 'Settings • Profile, avatar, password & server',
        actionLabel: 'Open settings',
        icon: Icons.person_rounded,
        keywords: const [
          'settings',
          'account',
          'profile',
          'user',
          'avatar',
          'password',
          'server',
          'sign out',
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'account'),
        ),
      ),
      if (hasLicense)
        _SpotlightPageSpec(
          id: 'settings:license',
          section: 'SETTINGS',
          title: 'Settings — License',
          subtitle: 'Settings • Desktop & TV license activation',
          actionLabel: 'Open settings',
          icon: Icons.key_rounded,
          keywords: const [
            'settings',
            'license',
            'key',
            'activation',
            'tv',
            'premium'
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'license'),
          ),
        ),
      _SpotlightPageSpec(
        id: 'settings:hidden-items',
        section: 'SETTINGS',
        title: 'Settings — Hidden Items',
        subtitle: 'Settings • Manage hidden albums, playlists & artists',
        actionLabel: 'Open settings',
        icon: Icons.visibility_off_rounded,
        keywords: const [
          'settings',
          'hidden items',
          'hidden',
          'unhide',
          'restore'
        ],
        onSelect: () => _navigateToView(
          const PlayerView(PlayerViewKind.settings, id: 'hidden-items'),
        ),
      ),
      if (hasServer) ...[
        _SpotlightPageSpec(
          id: 'settings:server-overview',
          section: 'SETTINGS',
          title: 'Server — Overview',
          subtitle: 'Server Settings • Local server status & library scan',
          actionLabel: 'Open settings',
          icon: Icons.dns_rounded,
          keywords: const [
            'settings',
            'server',
            'overview',
            'dashboard',
            'status',
            'scan'
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'server-overview'),
          ),
        ),
        _SpotlightPageSpec(
          id: 'settings:server-activity',
          section: 'SETTINGS',
          title: 'Server — Activity',
          subtitle: 'Server Settings • Active streams & connected devices',
          actionLabel: 'Open settings',
          icon: Icons.timeline_rounded,
          keywords: const [
            'settings',
            'server',
            'activity',
            'streams',
            'devices'
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'server-activity'),
          ),
        ),
        _SpotlightPageSpec(
          id: 'settings:server-users',
          section: 'SETTINGS',
          title: 'Server — Users',
          subtitle: 'Server Settings • Manage server user accounts',
          actionLabel: 'Open settings',
          icon: Icons.people_alt_rounded,
          keywords: const [
            'settings',
            'server',
            'users',
            'accounts',
            'members'
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'server-users'),
          ),
        ),
        _SpotlightPageSpec(
          id: 'settings:server-config',
          section: 'SETTINGS',
          title: 'Server — Configuration',
          subtitle: 'Server Settings • Music folder, Tailscale & autostart',
          actionLabel: 'Open settings',
          icon: Icons.settings_rounded,
          keywords: const [
            'settings',
            'server',
            'configuration',
            'config',
            'music folder',
            'tailscale',
            'autostart',
          ],
          onSelect: () => _navigateToView(
            const PlayerView(PlayerViewKind.settings, id: 'server-config'),
          ),
        ),
      ],
    ];
  }

  List<_SpotlightSection> _ensureSections(
    BuildContext context, {
    bool listen = true,
  }) {
    final library = context.read<LibraryController>();
    final trimmed = _query.trim();
    final isEmpty = trimmed.isEmpty;

    final List<Track>? recentSearches;
    final List<Track>? songs;
    final List<Album>? albums;
    final List<PlaylistSummary>? playlists;
    final LibraryCurationFilter? curationFilter;
    if (isEmpty) {
      recentSearches = listen
          ? context.select<LibraryController, List<Track>>(
              (l) => l.recentSearches,
            )
          : library.recentSearches;
      songs = null;
      albums = null;
      playlists = null;
      curationFilter = null;
    } else {
      recentSearches = null;
      final catalog = listen
          ? context.select<
              LibraryController,
              (
                List<Track>,
                List<Album>,
                List<PlaylistSummary>,
                LibraryCurationFilter,
              )>(
              (l) => (l.songs, l.albums, l.playlists, l.curationFilter),
            )
          : (
              library.songs,
              library.albums,
              library.playlists,
              library.curationFilter,
            );
      songs = catalog.$1;
      albums = catalog.$2;
      playlists = catalog.$3;
      curationFilter = catalog.$4;
      _searchLibrary(library, (trimmed, songs, albums, playlists));
    }

    final isLocalServer = listen
        ? context.select<ConnectionController, bool>((c) => c.isLocalServer)
        : context.read<ConnectionController>().isLocalServer;
    final client = listen
        ? context.select<ConnectionController, dynamic>((c) => c.client)
        : context.read<ConnectionController>().client;
    final hasCurrentTrack = listen
        ? context.select<AudioController, bool>((a) => a.currentTrack != null)
        : context.read<AudioController>().currentTrack != null;
    final rightPanelOpen = listen
        ? context.select<PlayerNavigator, bool>((n) => n.rightPanelOpen)
        : context.read<PlayerNavigator>().rightPanelOpen;
    final sidebarCollapsed = listen
        ? context.select<PlayerNavigator, bool>((n) => n.sidebarCollapsed)
        : context.read<PlayerNavigator>().sidebarCollapsed;

    if (_cachedSectionsQuery == _query &&
        identical(_cachedRecentSearches, recentSearches) &&
        identical(_cachedSongs, songs) &&
        identical(_cachedAlbums, albums) &&
        identical(_cachedPlaylists, playlists) &&
        _cachedCurationFilter == curationFilter &&
        _cachedIsLocalServer == isLocalServer &&
        _cachedHasCurrentTrack == hasCurrentTrack &&
        _cachedRightPanelOpen == rightPanelOpen &&
        _cachedSidebarCollapsed == sidebarCollapsed &&
        identical(_cachedClient, client) &&
        identical(_cachedLibraryResults, _libraryResults)) {
      return _cachedSections;
    }

    _cachedSectionsQuery = _query;
    _cachedRecentSearches = recentSearches;
    _cachedSongs = songs;
    _cachedAlbums = albums;
    _cachedPlaylists = playlists;
    _cachedCurationFilter = curationFilter;
    _cachedIsLocalServer = isLocalServer;
    _cachedHasCurrentTrack = hasCurrentTrack;
    _cachedRightPanelOpen = rightPanelOpen;
    _cachedSidebarCollapsed = sidebarCollapsed;
    _cachedClient = client;
    _cachedLibraryResults = _libraryResults;

    final host = maybeReadHost(context);
    final pages = _pageSpecs(
      context,
      host: host,
      isLocalServer: isLocalServer,
      hasCurrentTrack: hasCurrentTrack,
      rightPanelOpen: rightPanelOpen,
      sidebarCollapsed: sidebarCollapsed,
    );

    if (isEmpty) {
      final sections = <_SpotlightSection>[];
      final recents = recentSearches!.take(5).toList();
      if (recents.isNotEmpty) {
        sections.add(
          _SpotlightSection(
            title: 'RECENT SEARCHES',
            entries: [
              for (final track in recents)
                _buildTrackEntry(
                  context,
                  track,
                  client: client,
                  idPrefix: 'recent',
                ),
            ],
          ),
        );
      }

      sections.add(
        _SpotlightSection(
          title: 'PAGES',
          entries: [
            for (final page in pages.where((p) => p.section == 'PAGES'))
              _buildPageEntry(context, page),
          ],
        ),
      );

      sections.add(
        _SpotlightSection(
          title: 'SETTINGS',
          entries: [
            for (final page in pages.where((p) => p.section == 'SETTINGS'))
              _buildPageEntry(context, page),
          ],
        ),
      );
      _cachedSections = sections;
      return sections;
    }

    final parsed = SearchQuery.parse(trimmed);
    final matchedPages = LibrarySearchEngine.rank(
      parsed,
      pages,
      (p) => [
        SearchField(p.title, isPrimary: true),
        SearchField(p.subtitle),
        for (final kw in p.keywords) SearchField(kw),
      ],
      limit: 8,
    );

    final libraryResults = _libraryResults;
    final matchedPlaylists = libraryResults.playlists.take(6).toList();
    final matchedArtists = library.searchArtists(trimmed).take(6).toList();
    final matchedAlbums = libraryResults.albums.take(6).toList();
    final matchedSongs = libraryResults.songs.take(8).toList();

    final sections = <_SpotlightSection>[];

    if (matchedPages.isNotEmpty) {
      sections.add(
        _SpotlightSection(
          title: 'PAGES & SETTINGS',
          entries: [
            for (final page in matchedPages) _buildPageEntry(context, page),
          ],
        ),
      );
    }

    if (matchedPlaylists.isNotEmpty) {
      sections.add(
        _SpotlightSection(
          title: 'PLAYLISTS',
          entries: [
            for (final playlist in matchedPlaylists)
              _SpotlightEntry(
                id: 'playlist:${playlist.id}',
                title: playlist.name,
                subtitle:
                    'Playlist • ${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                actionLabel: 'Open playlist',
                leading: PlaylistArtwork(
                  playlist: playlist,
                  size: 36,
                  borderRadius: 6,
                ),
                onSelect: () {
                  widget.onBeforeNavigate?.call();
                  context.read<PlayerNavigator>().openPlaylist(playlist.id);
                },
              ),
          ],
        ),
      );
    }

    if (matchedArtists.isNotEmpty) {
      sections.add(
        _SpotlightSection(
          title: 'ARTISTS',
          entries: [
            for (final artist in matchedArtists)
              _SpotlightEntry(
                id: 'artist:${artist.name}',
                title: artist.name,
                subtitle: artist.albumCount == 0
                    ? 'Artist'
                    : 'Artist • ${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'}',
                actionLabel: 'Open artist',
                leading: _ArtistAvatar(
                  artist: artist,
                  client: client,
                  library: library,
                ),
                onSelect: () {
                  widget.onBeforeNavigate?.call();
                  context.read<PlayerNavigator>().openArtist(artist.name);
                },
              ),
          ],
        ),
      );
    }

    if (matchedAlbums.isNotEmpty) {
      sections.add(
        _SpotlightSection(
          title: 'ALBUMS',
          entries: [
            for (final album in matchedAlbums)
              _SpotlightEntry(
                id: 'album:${album.id}',
                title: album.title,
                subtitle: 'Album • ${album.artist}',
                actionLabel: 'Open album',
                leading: Artwork(
                  client: client,
                  albumId: album.id,
                  size: 36,
                  borderRadius: 6,
                ),
                onSelect: () {
                  widget.onBeforeNavigate?.call();
                  context.read<PlayerNavigator>().openAlbum(album.id);
                },
              ),
          ],
        ),
      );
    }

    if (matchedSongs.isNotEmpty) {
      sections.add(
        _SpotlightSection(
          title: 'SONGS',
          entries: [
            for (final track in matchedSongs)
              _buildTrackEntry(
                context,
                track,
                client: client,
                idPrefix: 'song',
                lyricSnippet: libraryResults.lyricSnippets[track.id],
              ),
          ],
        ),
      );
    }

    _cachedSections = sections;
    return sections;
  }

  _SpotlightEntry _buildPageEntry(
    BuildContext context,
    _SpotlightPageSpec page,
  ) {
    final colors = context.colors;
    return _SpotlightEntry(
      id: page.id,
      title: page.title,
      subtitle: page.subtitle,
      actionLabel: page.actionLabel,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Icon(page.icon, size: 18, color: colors.textPrimary),
      ),
      onSelect: page.onSelect,
    );
  }

  _SpotlightEntry _buildTrackEntry(
    BuildContext context,
    Track track, {
    required dynamic client,
    required String idPrefix,
    String? lyricSnippet,
  }) {
    final albumSuffix =
        track.albumTitle != null && track.albumTitle!.trim().isNotEmpty
            ? ' • ${track.albumTitle}'
            : '';
    final lyricSuffix = lyricSnippet != null && lyricSnippet.isNotEmpty
        ? ' • “$lyricSnippet”'
        : '';
    return _SpotlightEntry(
      id: '$idPrefix:${track.id}',
      title: track.title,
      subtitle: 'Song • ${track.artist}$albumSuffix$lyricSuffix',
      actionLabel: 'Play song',
      leading: Artwork(
        client: client,
        albumId: track.albumId,
        songId: track.albumId == null ? track.id : null,
        size: 36,
        borderRadius: 6,
      ),
      onSelect: () {
        if (widget.shellContext.mounted) {
          playFromSearch(widget.shellContext, track);
        } else {
          context.read<AudioController>().playTrack(track);
          context.read<LibraryController>().addRecentSearch(track);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sections = _ensureSections(context);
    final flatEntries = <_SpotlightEntry>[
      for (final section in sections) ...section.entries,
    ];
    final activeIndex = flatEntries.isEmpty
        ? -1
        : _selectedIndex.clamp(0, flatEntries.length - 1);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          24,
          SpotlightModal.topOffset,
          24,
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 500),
          child: Material(
            color: colors.popover,
            elevation: 28,
            shadowColor: Colors.black.withValues(alpha: 0.65),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PlayerTheme.panelRadius),
              side: BorderSide(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchInput(context),
                Divider(height: 1, thickness: 1, color: colors.border),
                Flexible(
                  child: flatEntries.isEmpty
                      ? _buildEmptyState(context)
                      : _buildResultsList(context, sections, activeIndex),
                ),
                Divider(height: 1, thickness: 1, color: colors.border),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('spotlight-search-field'),
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: _onQueryInputChanged,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText:
                      'Where would you like to go? Search pages, songs, albums, artists…',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    tooltip: 'Clear query',
                    iconSize: 18,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    color: colors.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _debounceTimer?.cancel();
                      _controller.clear();
                      setState(() {
                        _query = '';
                        _selectedIndex = 0;
                      });
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      _focusNode.requestFocus();
                    },
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            _KeycapBadge(
              label: 'ESC',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'No matches for "$_query"',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try searching for a page, setting, song, album, artist or playlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    List<_SpotlightSection> sections,
    int activeIndex,
  ) {
    final colors = context.colors;
    final rows = <_SpotlightDisplayRow>[];
    var runningIndex = 0;
    for (var s = 0; s < sections.length; s++) {
      rows.add(_SpotlightDisplayRow.header(sections[s].title, topGap: s > 0));
      for (final entry in sections[s].entries) {
        rows.add(_SpotlightDisplayRow.entry(entry, runningIndex++));
      }
    }

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final title = row.headerTitle;
        if (title != null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(10, row.topGap ? 14 : 4, 10, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: colors.textSecondary,
              ),
            ),
          );
        }
        final entry = row.entry!;
        final selected = row.flatIndex == activeIndex;
        return _SpotlightRow(
          key: _keyFor(entry.id),
          entry: entry,
          selected: selected,
          onTap: () => _activate(entry),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: colors.surfaceHigh.withValues(alpha: 0.4),
      child: Row(
        children: [
          const _KeycapBadge(label: '↑↓'),
          const SizedBox(width: 6),
          Text(
            'Navigate',
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
          const SizedBox(width: 16),
          const _KeycapBadge(label: '↵'),
          const SizedBox(width: 6),
          Text(
            'Select',
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
          const SizedBox(width: 16),
          const _KeycapBadge(label: 'ESC'),
          const SizedBox(width: 6),
          Text(
            'Dismiss',
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SpotlightRow extends StatelessWidget {
  const _SpotlightRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _SpotlightEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hover) => HoverSurface(
          active: selected || hover,
          base: Colors.transparent,
          highlight: colors.surfaceHover,
          borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              entry.leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected || hover) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    entry.actionLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({
    required this.artist,
    required this.client,
    required this.library,
  });

  final LibraryArtistSummary artist;
  final dynamic client;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    final customVersion = library.artistImageVersion(artist.name);
    final customUrl = customVersion != null && client != null
        ? client.artistImageUrl(artist.name, version: customVersion) as String
        : null;

    final fallback = Artwork(
      client: client,
      albumId: artist.artworkAlbumId,
      songId: artist.artworkSongId,
      size: size,
      borderRadius: size / 2,
      iconScale: 0.52,
      placeholderIcon: Icons.person_rounded,
    );

    if (customUrl == null || client == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image(
        image: Artwork.cachedImage(
          customUrl,
          client,
          cacheWidth:
              (size * MediaQuery.devicePixelRatioOf(context) * 2).round(),
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => fallback,
      ),
    );
  }
}

class _KeycapBadge extends StatelessWidget {
  const _KeycapBadge({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
    if (onTap == null) return badge;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: badge),
    );
  }
}

class _SpotlightSection {
  const _SpotlightSection({required this.title, required this.entries});

  final String title;
  final List<_SpotlightEntry> entries;
}

class _SpotlightDisplayRow {
  const _SpotlightDisplayRow.header(this.headerTitle, {required this.topGap})
      : entry = null,
        flatIndex = -1;

  const _SpotlightDisplayRow.entry(this.entry, this.flatIndex)
      : headerTitle = null,
        topGap = false;

  final String? headerTitle;
  final bool topGap;
  final _SpotlightEntry? entry;
  final int flatIndex;
}

class _SpotlightEntry {
  const _SpotlightEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.leading,
    required this.onSelect,
  });

  final String id;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Widget leading;
  final VoidCallback onSelect;
}

class _SpotlightPageSpec {
  const _SpotlightPageSpec({
    required this.id,
    required this.section,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.icon,
    required this.keywords,
    required this.onSelect,
  });

  final String id;
  final String section;
  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData icon;
  final List<String> keywords;
  final VoidCallback onSelect;
}
