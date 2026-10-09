import 'package:flutter/material.dart';
import '../../utils/shared_preferences_cache.dart';

/// A collapsible section widget with animated expansion.
/// Used by the library screen's Playlists section.
class CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  /// Optional key for persisting expanded/collapsed state across app restarts
  final String? persistenceKey;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.persistenceKey,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    // Load persisted state synchronously if persistence key is provided
    // Uses the pre-loaded sharedPrefs from main.dart - no async, no flicker
    if (widget.persistenceKey != null) {
      final savedState = sharedPrefs.getBool(widget.persistenceKey!);
      _isExpanded = savedState ?? widget.initiallyExpanded;
    } else {
      _isExpanded = widget.initiallyExpanded;
    }

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5, // 180 degrees (0.5 * 2π)
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  void _saveState() {
    sharedPrefs.setBool(widget.persistenceKey!, _isExpanded);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });

    if (widget.persistenceKey != null) {
      _saveState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                RotationTransition(
                  turns: _rotationAnimation,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? widget.child
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
