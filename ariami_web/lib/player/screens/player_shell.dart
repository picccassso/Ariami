import '../widgets/music_availability_banner.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_navigator.dart';
import '../services/quick_jump_service.dart';
import '../services/sidebar_selection_controller.dart';
import '../services/track_selection_controller.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import '../widgets/album_detail_view.dart';
import '../widgets/artist_detail_view.dart';
import '../widgets/browse_view.dart';
import '../widgets/curation_onboarding_dialog.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/find_in_page.dart';
import '../widgets/library_sidebar.dart';
import '../widgets/music_discovery_view.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/playback_helpers.dart';
import '../widgets/player_bar.dart';
import '../widgets/playlist_detail_view.dart';
import '../widgets/queue_intent.dart';
import '../widgets/recently_played_view.dart';
import '../widgets/search_view.dart';
import '../widgets/settings_view.dart';
import '../widgets/sidebar_selection_bar.dart';
import '../widgets/songs_view.dart';
import '../widgets/spotlight_modal.dart';
import '../widgets/top_bar.dart';

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final _find = FindInPageController();

  /// One selection for the whole centre column: only one track list is on
  /// screen at a time, and holding it here is what lets Escape cancel from
  /// the shell's key handler, which owns keyboard focus.
  final _selection = TrackSelectionController();

  /// The sidebar selects independently of the centre column: the two lists
  /// hold different kinds of thing and are on screen at the same time.
  final _sidebarSelection = SidebarSelectionController();
  final _shortcutFocus = FocusNode(debugLabel: 'PlayerShellShortcuts');
  PlayerNavigator? _nav;
  LibraryController? _library;
  String? _promptedOnboardingUserId;
  bool _onboardingDialogOpen = false;
  StreamSubscription<Track>? _unplayableTrackSubscription;
  StreamSubscription<QueueUndo>? _queueReplacedSubscription;

  @override
  void initState() {
    super.initState();
    // The macOS title bar is hidden app-wide (set once in main()); this
    // shell just reserves clearance for the floating traffic lights via its
    // own drag strip. Never toggle the style from widget lifecycles here —
    // stage hops briefly run two PlayerShell instances (the old one fades
    // out inside the surface switcher), so paired hide/restore calls race.
    // Focus watchdog — see _ensureShortcutFocus. Also run once after the
    // first frame: if something else held focus while the shell mounted
    // (e.g. a sign-in field), the Focus widget's autofocus is skipped and the
    // shortcuts would start out dead.
    FocusManager.instance.addListener(_ensureShortcutFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShortcutFocus());
  }

  /// Reclaims keyboard focus whenever it falls off the widget tree.
  ///
  /// Key events are dispatched from the focused node upward, so the shell's
  /// shortcuts only work while focus sits on [_shortcutFocus] or one of its
  /// descendants. When a focused text field is unmounted (closing the Cmd+F
  /// find bar, leaving the search view) and the scope has no history to
  /// restore, primary focus lands on a bare [FocusScopeNode] — an *ancestor*
  /// of this widget — and every shortcut goes dead until the app restarts.
  /// Detect that state and take focus back, unless another route (a dialog)
  /// is on top and rightfully owns it.
  ///
  /// Skipped while the window is in the background: Flutter parks focus on
  /// the root scope then and restores the focused field on return — but only
  /// if nothing took focus meanwhile, so grabbing it here would drop the
  /// caret out of whatever the user was typing in.
  void _ensureShortcutFocus() {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _shortcutFocus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A leftover filter must not silently narrow the next page's track list,
    // so any navigation dismisses it.
    final nav = context.read<PlayerNavigator>();
    if (!identical(nav, _nav)) {
      _nav?.removeListener(_onNavChanged);
      _nav = nav..addListener(_onNavChanged);
    }
    final library = context.read<LibraryController>();
    if (!identical(library, _library)) {
      _library?.removeListener(_maybeShowCurationOnboarding);
      _library = library..addListener(_maybeShowCurationOnboarding);
    }
    _maybeShowCurationOnboarding();
    // Surface auto-skipped queue entries (tracks deleted from the server
    // library) so the listener knows what was skipped and why.
    _unplayableTrackSubscription ??= context
        .read<AudioController>()
        .unplayableTrackStream
        .listen(_onUnplayableTrackSkipped);
    _queueReplacedSubscription ??= context
        .read<AudioController>()
        .queueReplacedStream
        .listen(_onQueueReplaced);
  }

  void _onQueueReplaced(QueueUndo undo) {
    if (!mounted) return;
    showUndoToast(
      ScaffoldMessenger.maybeOf(context),
      'Queue replaced',
      onUndo: () => unawaited(undo()),
    );
  }

  void _onUnplayableTrackSkipped(Track track) {
    if (!mounted) return;
    final label = track.title.isEmpty ? 'a song' : '"${track.title}"';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Skipped $label — it is no longer on the server.'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _maybeShowCurationOnboarding() {
    if (!mounted || _onboardingDialogOpen) return;
    final library = _library;
    if (library == null || !library.needsCurationOnboarding) return;
    final userId = library.curation.userId;
    if (_promptedOnboardingUserId == userId) return;
    _promptedOnboardingUserId = userId;
    _onboardingDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted) {
          await showCurationOnboardingDialog(context);
        }
      } finally {
        _onboardingDialogOpen = false;
      }
    });
  }

  void _onNavChanged() {
    _find.close();
    // Leaving a list drops its selection: the ids belong to the list that is
    // going away.
    _selection.exit();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_ensureShortcutFocus);
    _shortcutFocus.dispose();
    _nav?.removeListener(_onNavChanged);
    _library?.removeListener(_maybeShowCurationOnboarding);
    _unplayableTrackSubscription?.cancel();
    _queueReplacedSubscription?.cancel();
    _find.dispose();
    _selection.dispose();
    _sidebarSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<PlayerNavigator>();
    // Transport shortcuts: space toggles play/pause, ←/→ seek ±10s and ↑/↓
    // nudge the volume — like a desktop player should. The Focus seeds
    // keyboard focus so the shortcuts work without clicking first. When a
    // text field (e.g. the search box) holds focus we return `ignored` so the
    // keys fall through to normal typing — a `CallbackShortcuts` binding can't
    // do this because it always reports the key as handled once it matches,
    // which silently swallowed spaces typed into the search field.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _find),
        ChangeNotifierProvider.value(value: _selection),
        ChangeNotifierProvider.value(value: _sidebarSelection),
      ],
      child: Focus(
        focusNode: _shortcutFocus,
        autofocus: true,
        onKeyEvent: (node, event) => _handleKey(event),
        child: _buildLayout(context, nav),
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Cmd/Ctrl+K opens the Spotlight quick-navigation modal from anywhere in
    // the player shell, including when a text field holds focus.
    if (isSpotlightShortcut(event)) {
      if (event is KeyDownEvent) {
        unawaited(showSpotlightModal(context));
      }
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+F opens the in-page track filter on the track-list views.
    // Checked before the editing guard so it also works while the top search
    // bar (or the filter field itself) holds focus, like in a browser.
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (modifier && key == LogicalKeyboardKey.keyF) {
      final view = context.read<PlayerNavigator>().current.kind;
      if (view == PlayerViewKind.album ||
          view == PlayerViewKind.playlist ||
          view == PlayerViewKind.songs) {
        _find.open();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Escape cancels a multi-selection. Checked before the editing guard so
    // it still works while the filter field holds focus.
    if (key == LogicalKeyboardKey.escape &&
        (_selection.active || _sidebarSelection.active)) {
      _selection.exit();
      _sidebarSelection.exit();
      return KeyEventResult.handled;
    }

    if (_isEditing()) return KeyEventResult.ignored;

    // When on the search view and not editing, Escape clears the active search
    // query (returning to recent searches) and refocuses the search bar, or
    // navigates back if the query is already empty.
    if (key == LogicalKeyboardKey.escape) {
      final nav = context.read<PlayerNavigator>();
      if (nav.current.kind == PlayerViewKind.search) {
        if (event is KeyDownEvent) {
          final queryHolder = context.read<SearchQueryHolder?>();
          if (queryHolder != null &&
              (queryHolder.query.value.isNotEmpty ||
                  queryHolder.selectedIndex.value != -1)) {
            queryHolder.clear();
            queryHolder.requestFocus();
          } else if (nav.canGoBack) {
            nav.goBack();
          }
        }
        return KeyEventResult.handled;
      }
    }

    return handleTransportKey(context.read<AudioController>(), event);
  }

  /// True when a text field currently holds focus (e.g. the search box), so the
  /// spacebar shortcut yields to normal typing.
  bool _isEditing() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  Widget _buildLayout(BuildContext context, PlayerNavigator nav) {
    // The player tree needs a Scaffold of its own: the app-wide
    // ScaffoldMessenger only presents snackbars (queue popups etc.) in a
    // registered Scaffold, and without one they are silently never shown.
    // The PlayerBar takes the bottomNavigationBar slot so a fixed snackbar
    // renders just above it instead of covering the transport controls.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildColumns(context, nav),
          // Opt-in diagnostics (Settings → Developer), floating above the
          // content just over the player bar.
          const Positioned(right: 12, bottom: 12, child: DebugOverlay()),
        ],
      ),
      bottomNavigationBar: const PlayerBar(),
    );
  }

  Widget _buildColumns(BuildContext context, PlayerNavigator nav) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final forceCollapsed = constraints.maxWidth < 820;
        final sidebarWidth =
            (forceCollapsed || nav.sidebarCollapsed) ? 76.0 : 256.0;
        final quickJump = context.read<QuickJumpService?>();
        if (quickJump != null) {
          quickJump.isSidebarOpen = !forceCollapsed && !nav.sidebarCollapsed;
        }
        final showRightPanel =
            nav.rightPanelOpen && constraints.maxWidth >= 980;
        const panelWidth = 300.0;
        final rule = BorderSide(color: context.colors.border);
        // One flat surface: the columns are divided by hairline rules, not
        // floated as separate panels.
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.emphasized,
              width: sidebarWidth,
              decoration: BoxDecoration(border: Border(right: rule)),
              child: LibrarySidebar(forceCollapsed: forceCollapsed),
            ),
            Expanded(
              child: Column(
                children: [
                  const TopBar(),
                  const _OfflineBanner(),
                  const MusicAvailabilityBanner(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      reverseDuration: const Duration(milliseconds: 200),
                      transitionBuilder: Motion.fadeThrough,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previous,
                          if (current != null) current,
                        ],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey<PlayerView>(nav.current),
                        child: _CenterContent(view: nav.current),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.emphasized,
              width: showRightPanel ? panelWidth : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: AnimatedSwitcher(
                duration: Motion.medium,
                switchInCurve: Motion.emphasized,
                switchOutCurve: Motion.emphasized,
                transitionBuilder: Motion.revealHorizontal,
                child: showRightPanel
                    ? DecoratedBox(
                        key: const ValueKey('now-playing'),
                        decoration: BoxDecoration(border: Border(left: rule)),
                        child: const OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: panelWidth,
                          maxWidth: panelWidth,
                          child: NowPlayingPanel(),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-panel')),
              ),
            ),
          ],
        );

        // The sidebar's selection bar floats over the whole layout, not
        // inside the sidebar: its actions need the room.
        final sidebarSelection = context.watch<SidebarSelectionController>();
        if (quickJump != null) {
          quickJump.isMultiSelecting = sidebarSelection.active;
        }
        if (!sidebarSelection.active) return row;
        return Stack(
          children: [
            row,
            SidebarSelectionBar(
              selectedKeys: sidebarSelection.orderedSelection,
              onSelectAll: () =>
                  sidebarSelection.selectAll(sidebarSelection.visibleKeys),
              onDone: sidebarSelection.exit,
            ),
          ],
        );
      },
    );
  }
}

/// Slim strip shown while offline (manual or auto), mirroring mobile's
/// offline mode: downloads keep playing, and the strip explains what's
/// happening plus offers the way back online.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    if (!connection.isOfflineActive) return const SizedBox.shrink();

    final manual = connection.isManualOffline;
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: colors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              manual
                  ? 'Offline mode — playing downloaded music.'
                  : 'You\'re offline — playing downloaded music while we '
                      'reconnect to ${connection.serverInfo?.name ?? 'your server'}…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (manual)
            TextButton(
              onPressed: connection.goOnline,
              child: const Text('Go online'),
            )
          else ...[
            if (connection.isReconnectionAttemptInFlight)
              TextButton.icon(
                onPressed: null,
                icon: const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Reconnecting…'),
              )
            else
              TextButton(
                onPressed: connection.retryReconnectNow,
                child: const Text('Retry now'),
              ),
            TextButton(
              onPressed: connection.goOffline,
              child: const Text('Stay offline'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CenterContent extends StatelessWidget {
  const _CenterContent({required this.view});
  final PlayerView view;

  @override
  Widget build(BuildContext context) {
    // Guard: if the connection drops we should not try to render content —
    // except in offline mode (manual or auto), where the downloaded library
    // keeps the player usable.
    final usable = context.select<ConnectionController, bool>(
      (c) => c.isConnected || c.isOfflineActive,
    );
    if (!usable) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (view.kind) {
      case PlayerViewKind.home:
        return const BrowseView();
      case PlayerViewKind.albums:
        return const AlbumsView();
      case PlayerViewKind.songs:
        return const SongsView();
      case PlayerViewKind.album:
        return AlbumDetailView(albumId: view.id!);
      case PlayerViewKind.playlist:
        return PlaylistDetailView(playlistId: view.id!);
      case PlayerViewKind.artist:
        return ArtistDetailView(artistName: view.id!);
      case PlayerViewKind.search:
        return const SearchView();
      case PlayerViewKind.discovery:
        return const MusicDiscoveryView();
      case PlayerViewKind.recentlyPlayed:
        return const RecentlyPlayedView();
      case PlayerViewKind.settings:
        return const SettingsView();
    }
  }
}
