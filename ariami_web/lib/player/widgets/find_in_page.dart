import 'package:ariami_core/services/search/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/player_models.dart';
import '../theme/player_theme.dart';

/// Page-local track filter opened with Cmd/Ctrl+F on album/playlist views.
///
/// The shell owns one instance and toggles it; whichever detail view is on
/// screen watches it and narrows its track list to matches while active.
class FindInPageController extends ChangeNotifier {
  bool _active = false;
  String _query = '';
  SearchQuery? _parsedQuery;
  int _selected = 0;
  int _refocusTick = 0;

  bool get active => _active;
  String get query => _query;

  /// Bumped when Cmd/Ctrl+F is pressed while the bar is already open; the bar
  /// listens for this and refocuses its field (browser behavior).
  int get refocusTick => _refocusTick;

  /// Index of the keyboard-selected row within the currently visible matches,
  /// clamped to [matchCount] (which shrinks as the user types). -1 when there
  /// are no matches.
  int selectionFor(int matchCount) =>
      matchCount == 0 ? -1 : _selected.clamp(0, matchCount - 1);

  void open() {
    if (_active) {
      _refocusTick++;
      notifyListeners();
      return;
    }
    _active = true;
    _selected = 0;
    notifyListeners();
  }

  void close() {
    if (!_active && _query.isEmpty) return;
    _active = false;
    _query = '';
    _parsedQuery = null;
    _selected = 0;
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _parsedQuery = value.trim().isEmpty ? null : SearchQuery.parse(value);
    _selected = 0;
    notifyListeners();
  }

  void moveSelection(int delta, int matchCount) {
    if (matchCount == 0) return;
    final next = (selectionFor(matchCount) + delta).clamp(0, matchCount - 1);
    if (next == _selected) return;
    _selected = next;
    notifyListeners();
  }

  /// Whether [track] matches the current query (title, artist or album).
  ///
  /// Uses the shared engine's matching (normalization, transliteration,
  /// keyboard-layout correction, fuzz) but never its ranking: find-in-page
  /// highlights rows of the on-screen list in their existing order.
  bool matches(Track track) {
    final parsed = _parsedQuery;
    if (parsed == null) return true;
    return LibrarySearchEngine.matches(parsed, [
      SearchField(track.title, isPrimary: true),
      SearchField(track.artist),
      if (track.albumTitle != null) SearchField(track.albumTitle!),
    ]);
  }
}

class FindInPageBar extends StatefulWidget {
  const FindInPageBar({
    super.key,
    required this.controller,
    required this.matchCount,
    required this.totalCount,
    required this.onPlaySelected,
  });

  final FindInPageController controller;
  final int matchCount;
  final int totalCount;

  /// Invoked when the user hits Enter; receives the selected index within the
  /// currently visible matches.
  final void Function(int matchIndex) onPlaySelected;

  @override
  State<FindInPageBar> createState() => _FindInPageBarState();
}

class _FindInPageBarState extends State<FindInPageBar> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.query);
  final _fieldFocus = FocusNode(debugLabel: 'FindInPageField');
  late int _lastRefocusTick = widget.controller.refocusTick;

  @override
  void initState() {
    super.initState();
    // `autofocus` is a no-op when the scope already has a focused node — and
    // it always does here, because the Cmd+F keystroke that opens this bar is
    // handled by the shell's focused shortcut node. Claim focus explicitly so
    // the user can type immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
    widget.controller.addListener(_onControllerChanged);
  }

  /// Cmd/Ctrl+F while the bar is already open refocuses the field and selects
  /// the existing query so typing replaces it, like a browser's find bar.
  void _onControllerChanged() {
    if (widget.controller.refocusTick == _lastRefocusTick) return;
    _lastRefocusTick = widget.controller.refocusTick;
    _fieldFocus.requestFocus();
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _fieldFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.controller.close();
      return KeyEventResult.handled;
    }
    // Repeats allowed: holding ↓ walks the list.
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      widget.controller.moveSelection(
        key == LogicalKeyboardKey.arrowDown ? 1 : -1,
        widget.matchCount,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        final selected = widget.controller.selectionFor(widget.matchCount);
        if (selected >= 0) widget.onPlaySelected(selected);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) => _handleKey(event),
                child: TextField(
                  controller: _text,
                  focusNode: _fieldFocus,
                  onChanged: widget.controller.setQuery,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Find in tracks…',
                    hintStyle: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ),
            ),
            if (widget.controller.query.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${widget.matchCount} of ${widget.totalCount}',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Close (Esc)',
              iconSize: 18,
              color: colors.textSecondary,
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.controller.close,
            ),
          ],
        ),
      ),
    );
  }
}
