import 'package:flutter/material.dart';

/// A collapsible section widget with animated expansion
/// Used in the library screen to show/hide Playlists, Albums, and Songs sections
class CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
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
    _isExpanded = widget.initiallyExpanded;

    // Animation controller for expansion
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    // Rotation animation for chevron icon
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5, // 180 degrees (0.5 * 2π)
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Set initial state
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with title and chevron
        InkWell(
          onTap: _toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                // Section title
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Animated chevron icon
                RotationTransition(
                  turns: _rotationAnimation,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        // Animated expansion of child content
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
