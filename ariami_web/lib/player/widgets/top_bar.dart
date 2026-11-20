import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'curate_library_dialog.dart';
import 'hover_builder.dart';
import 'search_view.dart';
import 'shell_column_header.dart';
import 'spotlight_modal.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  static const Duration searchDebounce = Duration(milliseconds: 100);

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  SearchQueryHolder? _queryHolder;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = _handleSearchKey;
  }

  /// Moves the ↑/↓ highlight through the current song results and handles Escape
  /// to clear the query or navigate back. Runs on the search field's own focus
  /// node so it preempts default caret-movement / editing handling.
  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final holder = _queryHolder;
    if (holder == null) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      _searchDebounceTimer?.cancel();
      if (holder.query.value.isNotEmpty ||
          _searchController.text.isNotEmpty ||
          holder.selectedIndex.value != -1) {
        _searchController.clear();
        holder.clear();
        _searchFocus.requestFocus();
      } else {
        final nav = context.read<PlayerNavigator>();
        if (nav.current.kind == PlayerViewKind.search && nav.canGoBack) {
          nav.goBack();
          _searchFocus.unfocus();
        } else {
          _searchFocus.unfocus();
        }
      }
      return KeyEventResult.handled;
    }

    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    _flushPendingSearchQuery();
    unawaited(_moveSelection(holder, down: down));
    return KeyEventResult.handled;
  }

  Future<void> _moveSelection(
    SearchQueryHolder holder, {
    required bool down,
  }) async {
    final songs = await holder.songs;
    if (songs.isEmpty) return;
    final current = holder.selectedIndex.value;
    holder.selectedIndex.value = down
        ? (current + 1).clamp(0, songs.length - 1)
        : (current <= 0 ? 0 : current - 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final holder = context.read<SearchQueryHolder>();
    if (!identical(holder, _queryHolder)) {
      _queryHolder?.query.removeListener(_onQueryChangedExternally);
      _queryHolder?.refocusTick.removeListener(_onRefocusRequested);
      _queryHolder = holder;
      holder.query.addListener(_onQueryChangedExternally);
      holder.refocusTick.addListener(_onRefocusRequested);
    }
  }

  /// Keeps the field's text in sync when something other than typing clears
  /// or sets the query (e.g. picking a search result clears it for us).
  void _onQueryChangedExternally() {
    final value = _queryHolder!.query.value;
    if (_searchController.text != value) {
      _searchDebounceTimer?.cancel();
      _searchController.text = value;
    }
  }

  void _onSearchChanged(String value) {
    final holder = _queryHolder ?? context.read<SearchQueryHolder>();
    final nav = context.read<PlayerNavigator>();
    holder.selectedIndex.value = -1;
    if (value.isNotEmpty && nav.current.kind != PlayerViewKind.search) {
      nav.go(PlayerView.search);
    }
    _searchDebounceTimer?.cancel();
    if (value.trim().isEmpty) {
      if (holder.query.value != value) {
        holder.query.value = value;
      }
      return;
    }
    _searchDebounceTimer = Timer(TopBar.searchDebounce, () {
      if (!mounted) return;
      if (holder.query.value != value) {
        holder.query.value = value;
      }
    });
  }

  void _flushPendingSearchQuery() {
    _searchDebounceTimer?.cancel();
    final holder = _queryHolder ?? context.read<SearchQueryHolder>();
    final value = _searchController.text;
    if (holder.query.value != value) {
      holder.query.value = value;
    }
  }

  void _onRefocusRequested() {
    if (!mounted) return;
    _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _queryHolder?.query.removeListener(_onQueryChangedExternally);
    _queryHolder?.refocusTick.removeListener(_onRefocusRequested);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<PlayerNavigator>();
    final connection = context.watch<ConnectionController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return ShellColumnHeader(
          padding: const EdgeInsets.only(left: 10, right: 14),
          children: [
            _NavButton(
              tooltip: 'Back',
              icon: Icons.chevron_left_rounded,
              enabled: nav.canGoBack,
              onTap: nav.goBack,
            ),
            if (!compact) ...[
              _NavButton(
                tooltip: 'Forward',
                icon: Icons.chevron_right_rounded,
                enabled: nav.canGoForward,
                onTap: nav.goForward,
              ),
              _NavButton(
                tooltip: 'Home',
                icon: Icons.home_outlined,
                enabled: nav.current.kind != PlayerViewKind.home,
                onTap: () => nav.go(PlayerView.home),
              ),
            ],
            SizedBox(width: compact ? 6 : 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SizedBox(
                    height: 36,
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        TextField(
                          key: const Key('top-bar-search-field'),
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onTap: () {
                            if (nav.current.kind != PlayerViewKind.search) {
                              nav.go(PlayerView.search);
                            }
                          },
                          onChanged: _onSearchChanged,
                          onSubmitted: (value) async {
                            _flushPendingSearchQuery();
                            if (value.trim().isEmpty) return;
                            final holder = context.read<SearchQueryHolder>();
                            final songs = await holder.songs;
                            if (!context.mounted || songs.isEmpty) return;
                            // Enter plays the ↑/↓-highlighted song, falling back to
                            // the top result when nothing is highlighted.
                            final idx = holder.selectedIndex.value;
                            final track = (idx >= 0 && idx < songs.length)
                                ? songs[idx]
                                : songs.first;
                            playFromSearch(context, track);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search your library',
                            hintStyle: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: context.colors.textSecondary,
                            ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 0,
                            ),
                            suffixIcon:
                                ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchController,
                              builder: (context, value, _) {
                                if (value.text.isEmpty) {
                                  if (compact) return const SizedBox.shrink();
                                  // Reserve horizontal room for the overlay pill
                                  // so long placeholder text clips cleanly before
                                  // reaching it.
                                  return IgnorePointer(
                                    child: Opacity(
                                      opacity: 0,
                                      child: _SpotlightHintPill(
                                        label: spotlightShortcutHint(),
                                        onTap: () {},
                                      ),
                                    ),
                                  );
                                }
                                return IconButton(
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  tooltip: 'Clear search',
                                  splashRadius: 18,
                                  onPressed: () {
                                    _searchDebounceTimer?.cancel();
                                    _searchController.clear();
                                    context.read<SearchQueryHolder>().clear();
                                  },
                                );
                              },
                            ),
                            isDense: true,
                            fillColor: context.colors.surfaceHigh,
                            border: _searchBorder(Colors.transparent),
                            enabledBorder: _searchBorder(Colors.transparent),
                            focusedBorder:
                                _searchBorder(context.colors.textPrimary),
                          ),
                        ),
                        if (!compact)
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              if (value.text.isNotEmpty) {
                                return const SizedBox.shrink();
                              }
                              return _SpotlightHintPill(
                                key: const Key('top-bar-spotlight-hint'),
                                label: spotlightShortcutHint(),
                                onTap: () =>
                                    unawaited(showSpotlightModal(context)),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 6 : 16),
            const _DownloadsIndicator(),
            IconButton(
              tooltip: 'Discover music',
              icon: Icon(
                nav.current.kind == PlayerViewKind.discovery
                    ? Icons.explore_rounded
                    : Icons.explore_outlined,
              ),
              color: nav.current.kind == PlayerViewKind.discovery
                  ? Theme.of(context).colorScheme.secondary
                  : context.colors.textSecondary,
              onPressed: () => nav.go(PlayerView.discovery),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Recently played',
              icon: Icon(
                nav.current.kind == PlayerViewKind.recentlyPlayed
                    ? Icons.history_rounded
                    : Icons.history_outlined,
              ),
              color: nav.current.kind == PlayerViewKind.recentlyPlayed
                  ? Theme.of(context).colorScheme.secondary
                  : context.colors.textSecondary,
              onPressed: () => nav.go(PlayerView.recentlyPlayed),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: nav.rightPanelOpen ? 'Hide up next' : 'Show up next',
              icon: Icon(
                nav.rightPanelOpen
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
              ),
              color: nav.rightPanelOpen
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
              onPressed: nav.toggleRightPanel,
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Account',
              offset: const Offset(0, 46),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                overlayColor: Colors.transparent,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const CircleBorder(),
              ),
              onSelected: (value) async {
                switch (value) {
                  case 'curate':
                    await showPlayerLibraryCurationDialog(context);
                    break;
                  case 'settings':
                    context.read<PlayerNavigator>().go(PlayerView.settings);
                    break;
                  case 'offline':
                    await connection.goOffline();
                    break;
                  case 'online':
                    await connection.goOnline();
                    break;
                  case 'signout':
                    await connection.disconnect();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.username ?? 'Signed in',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        connection.serverInfo?.name ?? '',
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                if (!connection.isManualOffline)
                  const PopupMenuItem(
                    value: 'curate',
                    child: Text('Curate My Library…'),
                  ),
                const PopupMenuItem(value: 'settings', child: Text('Settings')),
                // Manual offline mode, like mobile: play downloads only,
                // no reconnect attempts until the user goes back online.
                if (connection.isConnected && connection.canGoOffline)
                  const PopupMenuItem(
                      value: 'offline', child: Text('Go offline')),
                if (connection.isManualOffline)
                  const PopupMenuItem(
                      value: 'online', child: Text('Go online')),
                const PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ],
              icon: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.border, width: 1.5),
                ),
                child: _AccountAvatar(
                  bytes: connection.avatarBytes,
                  radius: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static InputBorder _searchBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
        borderSide: BorderSide(color: color),
      );
}

/// Shown only while downloads are running: a progress ring around a download
/// glyph. Clicking it opens Settings → Downloads.
class _DownloadsIndicator extends StatelessWidget {
  const _DownloadsIndicator();

  @override
  Widget build(BuildContext context) {
    final downloads = maybeWatchProvider<PlayerDownloadsBridge?>(context) ??
        maybeWatchProvider<PlayerDownloadsBridge>(context);
    if (downloads == null) return const SizedBox.shrink();
    final inFlight = downloads.inFlightCount;
    if (inFlight == 0) return const SizedBox.shrink();

    final total = downloads.sessionTotal;
    final done = downloads.sessionDone;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip:
            total > 1 ? 'Downloading — $done of $total done' : 'Downloading…',
        onPressed: () => context
            .read<PlayerNavigator>()
            .go(const PlayerView(PlayerViewKind.settings, id: 'downloads')),
        icon: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: downloads.sessionProgress,
                strokeWidth: 2,
              ),
              const Icon(Icons.download_rounded, size: 13),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.bytes,
    required this.radius,
  });

  final Uint8List? bytes;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.surfaceHover,
      child: ClipOval(
        child: bytes == null
            ? _fallbackIcon(context)
            : Image.memory(
                bytes!,
                width: size,
                height: size,
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context) * 2).round(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _fallbackIcon(context),
              ),
      ),
    );
  }

  Widget _fallbackIcon(BuildContext context) {
    return Icon(
      Icons.person_rounded,
      size: radius + 2,
      color: context.colors.textPrimary,
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: context.colors.textPrimary,
      disabledColor: context.colors.textSecondary.withValues(alpha: 0.4),
      onPressed: enabled ? onTap : null,
    );
  }
}

class _SpotlightHintPill extends StatelessWidget {
  const _SpotlightHintPill({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hover) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hover ? colors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: hover
                    ? colors.textPrimary
                    : colors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
