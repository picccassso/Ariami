import 'package:flutter/material.dart';

/// Empty state widget shown when the library has no content.
class LibraryEmptyState extends StatelessWidget {
  final bool isOfflineMode;

  const LibraryEmptyState({
    super.key,
    required this.isOfflineMode,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOfflineMode ? Icons.cloud_off : Icons.library_music,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            isOfflineMode ? 'No Downloaded Music' : 'Your Music Library',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              isOfflineMode
                  ? 'Download songs while online to listen offline'
                  : 'Add music to your desktop library to see it here',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
