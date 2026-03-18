import 'package:flutter/material.dart';

/// Fallback gradient header with icon for when no artwork is available
class FallbackHeader extends StatelessWidget {
  /// The playlist name used to generate a consistent color
  final String? playlistName;

  const FallbackHeader({
    super.key,
    this.playlistName,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = (playlistName?.hashCode ?? 0) % 5;
    final gradients = [
      [Colors.grey[700]!, Colors.grey[900]!],
      [Colors.grey[600]!, Colors.grey[800]!],
      [Colors.grey[500]!, Colors.grey[700]!],
      [Colors.grey[400]!, Colors.grey[600]!],
      [Colors.grey[300]!, Colors.grey[500]!],
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients[colorIndex],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.queue_music,
          size: 80,
          color: Colors.white,
        ),
      ),
    );
  }
}
