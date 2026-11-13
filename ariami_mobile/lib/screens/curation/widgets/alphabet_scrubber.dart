import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/constants.dart';

const List<String> kAlphabetIndexLetters = <String>[
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

/// Normalizes a display name into `#` or `A`–`Z` for alphabetical grouping.
String curationIndexLetter(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return '#';
  final first = trimmed.substring(0, 1).toUpperCase();
  final code = first.codeUnitAt(0);
  if (code >= 65 && code <= 90) return first;
  return '#';
}

sealed class _IndexedRow<T> {
  const _IndexedRow();
}

class _HeaderRow<T> extends _IndexedRow<T> {
  const _HeaderRow(this.letter);
  final String letter;
}

class _ItemRow<T> extends _IndexedRow<T> {
  const _ItemRow(this.item, this.itemIndex);
  final T item;
  final int itemIndex;
}

/// Scrollable list with optional inline alphabetical section headers and a
/// right-edge A–Z scrub rail for fast jumping across large catalogs.
class AlphabetScrubberList<T> extends StatefulWidget {
  const AlphabetScrubberList({
    super.key,
    required this.items,
    required this.labelOf,
    required this.itemBuilder,
    this.itemExtent = 64.0,
    this.headerExtent = 28.0,
    this.showScrubber = true,
    this.showSectionHeaders = true,
    this.controller,
    this.padding = EdgeInsets.zero,
  });

  final List<T> items;
  final String Function(T item) labelOf;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double itemExtent;
  final double headerExtent;
  final bool showScrubber;
  final bool showSectionHeaders;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<AlphabetScrubberList<T>> createState() =>
      _AlphabetScrubberListState<T>();
}

class _AlphabetScrubberListState<T> extends State<AlphabetScrubberList<T>> {
  ScrollController? _ownedController;
  ScrollController get _scrollController =>
      widget.controller ?? (_ownedController ??= ScrollController());

  late List<_IndexedRow<T>> _rows;
  late Map<String, double> _letterOffsets;
  late Set<String> _availableLetters;

  String? _activeScrubLetter;
  double? _activeScrubY;

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant AlphabetScrubberList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.showSectionHeaders != widget.showSectionHeaders ||
        oldWidget.itemExtent != widget.itemExtent ||
        oldWidget.headerExtent != widget.headerExtent) {
      _rebuildIndex();
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _rebuildIndex() {
    final rows = <_IndexedRow<T>>[];
    final offsets = <String, double>{};
    final available = <String>{};

    var y = widget.padding.top;
    String? currentLetter;

    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final letter = curationIndexLetter(widget.labelOf(item));
      available.add(letter);

      if (widget.showSectionHeaders && letter != currentLetter) {
        currentLetter = letter;
        offsets.putIfAbsent(letter, () => y);
        rows.add(_HeaderRow<T>(letter));
        y += widget.headerExtent;
      } else {
        offsets.putIfAbsent(letter, () => y);
      }

      rows.add(_ItemRow<T>(item, i));
      y += widget.itemExtent;
    }

    _rows = rows;
    _letterOffsets = offsets;
    _availableLetters = available;
  }

  String _resolveNearestLetter(String target) {
    if (_letterOffsets.containsKey(target)) return target;
    final startIdx = kAlphabetIndexLetters.indexOf(target);
    if (startIdx == -1) return _letterOffsets.keys.first;

    // Prefer the next available letter downward; fall back upward if past end.
    for (var i = startIdx + 1; i < kAlphabetIndexLetters.length; i++) {
      final candidate = kAlphabetIndexLetters[i];
      if (_letterOffsets.containsKey(candidate)) return candidate;
    }
    for (var i = startIdx - 1; i >= 0; i--) {
      final candidate = kAlphabetIndexLetters[i];
      if (_letterOffsets.containsKey(candidate)) return candidate;
    }
    return _letterOffsets.keys.first;
  }

  void _jumpToRailPosition(double localY, double railHeight) {
    if (_letterOffsets.isEmpty || railHeight <= 0) return;
    final fraction = (localY / railHeight).clamp(0.0, 0.9999);
    final letterIndex = (fraction * kAlphabetIndexLetters.length)
        .floor()
        .clamp(0, kAlphabetIndexLetters.length - 1);
    final rawLetter = kAlphabetIndexLetters[letterIndex];
    final targetLetter = _resolveNearestLetter(rawLetter);
    final targetOffset = _letterOffsets[targetLetter];
    if (targetOffset == null) return;

    if (_activeScrubLetter != targetLetter) {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _activeScrubLetter = targetLetter;
      _activeScrubY = localY.clamp(0.0, railHeight);
    });

    if (_scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(targetOffset.clamp(0.0, maxExtent));
    }
  }

  void _endScrub() {
    if (_activeScrubLetter != null || _activeScrubY != null) {
      setState(() {
        _activeScrubLetter = null;
        _activeScrubY = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showRail = widget.showScrubber && _availableLetters.length > 1;
    final listPadding = EdgeInsets.fromLTRB(
      widget.padding.left,
      widget.padding.top,
      widget.padding.right + (showRail ? 26.0 : 0.0),
      widget.padding.bottom,
    );

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: listPadding,
          itemCount: _rows.length,
          itemExtentBuilder: (index, _) {
            if (index < 0 || index >= _rows.length) return widget.itemExtent;
            return _rows[index] is _HeaderRow<T>
                ? widget.headerExtent
                : widget.itemExtent;
          },
          itemBuilder: (context, index) {
            final row = _rows[index];
            return switch (row) {
              _HeaderRow<T>(:final letter) => _AlphabetSectionHeader(
                  letter: letter,
                  height: widget.headerExtent,
                ),
              _ItemRow<T>(:final item, :final itemIndex) =>
                widget.itemBuilder(context, item, itemIndex),
            };
          },
        ),
        if (showRail)
          Positioned(
            top: 4,
            bottom: 4,
            right: 2,
            width: 24,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final railHeight = constraints.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _jumpToRailPosition(details.localPosition.dy, railHeight),
                  onTapUp: (_) => _endScrub(),
                  onTapCancel: _endScrub,
                  onVerticalDragStart: (details) =>
                      _jumpToRailPosition(details.localPosition.dy, railHeight),
                  onVerticalDragUpdate: (details) =>
                      _jumpToRailPosition(details.localPosition.dy, railHeight),
                  onVerticalDragEnd: (_) => _endScrub(),
                  onVerticalDragCancel: _endScrub,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final letter in kAlphabetIndexLetters)
                        Expanded(
                          child: Center(
                            child: Text(
                              letter,
                              style: TextStyle(
                                fontSize: 9.5,
                                height: 1.0,
                                fontWeight: _activeScrubLetter == letter
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: _activeScrubLetter == letter
                                    ? colors.textPrimary
                                    : _availableLetters.contains(letter)
                                        ? colors.textSecondary
                                        : colors.textSecondary
                                            .withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (showRail && _activeScrubLetter != null && _activeScrubY != null)
          Positioned(
            right: 36,
            top: (_activeScrubY! - 22).clamp(8.0, 600.0),
            child: IgnorePointer(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.popover,
                  borderRadius: BorderRadius.circular(AppTheme.panelRadius),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _activeScrubLetter!,
                  style: AppTheme.heading(22, color: colors.textPrimary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlphabetSectionHeader extends StatelessWidget {
  const _AlphabetSectionHeader({
    required this.letter,
    required this.height,
  });

  final String letter;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Text(
        letter,
        style: AppTheme.heading(13, color: colors.textSecondary),
      ),
    );
  }
}
