import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/motion.dart';
import '../../theme/player_theme.dart';

class DesktopSegmentedOption<T> {
  const DesktopSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? tooltip;
}

/// A horizontal segmented control styled for desktop settings.
///
/// Features a sleek rounded track, smooth hover transitions, an animated
/// active-segment pill highlight ([Motion.fast]), and keyboard navigation
/// (Arrow keys, Space/Enter).
class DesktopSegmentedControl<T> extends StatefulWidget {
  const DesktopSegmentedControl({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.minSegmentWidth,
    this.expanded = false,
  });

  final List<DesktopSegmentedOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onChanged;
  final double? minSegmentWidth;
  final bool expanded;

  @override
  State<DesktopSegmentedControl<T>> createState() =>
      _DesktopSegmentedControlState<T>();
}

class _DesktopSegmentedControlState<T>
    extends State<DesktopSegmentedControl<T>> {
  int? _hoveredIndex;
  int? _focusedIndex;

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final count = widget.options.length;
    if (count == 0) return;

    var currentIndex = -1;
    if (widget.selectedValue != null) {
      currentIndex =
          widget.options.indexWhere((o) => o.value == widget.selectedValue);
    }
    if (currentIndex == -1 && _focusedIndex != null) {
      currentIndex = _focusedIndex!;
    }

    if (currentIndex == -1) {
      final targetIndex = (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowUp)
          ? count - 1
          : 0;
      setState(() => _focusedIndex = targetIndex);
      widget.onChanged(widget.options[targetIndex].value);
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final nextIndex = (currentIndex + 1) % count;
      setState(() => _focusedIndex = nextIndex);
      widget.onChanged(widget.options[nextIndex].value);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final prevIndex = (currentIndex - 1 + count) % count;
      setState(() => _focusedIndex = prevIndex);
      widget.onChanged(widget.options[prevIndex].value);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (_focusedIndex != null &&
          _focusedIndex! >= 0 &&
          _focusedIndex! < count) {
        widget.onChanged(widget.options[_focusedIndex!].value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = widget.selectedValue != null
        ? widget.options.indexWhere((o) => o.value == widget.selectedValue)
        : -1;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _handleKey(event);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        setState(() {
          _focusedIndex =
              hasFocus ? (selectedIndex >= 0 ? selectedIndex : 0) : null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          border: Border.all(
            color: _focusedIndex != null
                ? scheme.secondary.withValues(alpha: 0.6)
                : context.colors.border.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.options.length; i++) ...[
              if (i > 0)
                _Divider(
                  visible: i != selectedIndex && (i - 1) != selectedIndex,
                ),
              widget.expanded
                  ? Expanded(
                      child: _SegmentItem<T>(
                        option: widget.options[i],
                        isSelected: i == selectedIndex,
                        isHovered: i == _hoveredIndex,
                        isFocused: i == _focusedIndex,
                        minWidth: widget.minSegmentWidth,
                        onHoverChange: (hovered) {
                          setState(() {
                            _hoveredIndex = hovered
                                ? i
                                : (_hoveredIndex == i ? null : _hoveredIndex);
                          });
                        },
                        onTap: () {
                          widget.onChanged(widget.options[i].value);
                        },
                      ),
                    )
                  : Flexible(
                      child: _SegmentItem<T>(
                        option: widget.options[i],
                        isSelected: i == selectedIndex,
                        isHovered: i == _hoveredIndex,
                        isFocused: i == _focusedIndex,
                        minWidth: widget.minSegmentWidth,
                        onHoverChange: (hovered) {
                          setState(() {
                            _hoveredIndex = hovered
                                ? i
                                : (_hoveredIndex == i ? null : _hoveredIndex);
                          });
                        },
                        onTap: () {
                          widget.onChanged(widget.options[i].value);
                        },
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentItem<T> extends StatelessWidget {
  const _SegmentItem({
    required this.option,
    required this.isSelected,
    required this.isHovered,
    required this.isFocused,
    required this.onHoverChange,
    required this.onTap,
    this.minWidth,
  });

  final DesktopSegmentedOption<T> option;
  final bool isSelected;
  final bool isHovered;
  final bool isFocused;
  final ValueChanged<bool> onHoverChange;
  final VoidCallback onTap;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChange(true),
      onExit: (_) => onHoverChange(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minWidth: minWidth ?? 0,
            minHeight: 30,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: Motion.fast,
                  curve: Motion.standard,
                  opacity:
                      ((isHovered || isFocused) && !isSelected) ? 1.0 : 0.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(PlayerTheme.cardRadius),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: Motion.fast,
                  curve: Motion.standard,
                  opacity: isSelected ? 1.0 : 0.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius:
                          BorderRadius.circular(PlayerTheme.cardRadius),
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (option.icon != null) ...[
                      Icon(
                        option.icon,
                        size: 15,
                        color: isSelected
                            ? scheme.onSecondary
                            : ((isHovered || isFocused)
                                ? context.colors.textPrimary
                                : context.colors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: Motion.fast,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? scheme.onSecondary
                              : ((isHovered || isFocused)
                                  ? context.colors.textPrimary
                                  : context.colors.textSecondary),
                        ),
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (option.tooltip != null) {
      content = Tooltip(
        message: option.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: content,
      );
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: content,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: visible ? 1.0 : 0.0,
      child: Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        color: context.colors.border.withValues(alpha: 0.6),
      ),
    );
  }
}
