import 'package:ariami_core/models/music_availability.dart';
import 'package:flutter/material.dart';

import '../services/api/connection_service.dart';

/// Keep the storage warning visible while browsing any tab or cached music.
class MusicAvailabilityBanner extends StatelessWidget {
  const MusicAvailabilityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = ConnectionService();
    return StreamBuilder<bool>(
      stream: connection.connectionStateStream,
      initialData: connection.isConnected,
      builder: (context, snapshot) => ValueListenableBuilder<MusicAvailability>(
        valueListenable: connection.musicAvailability,
        builder: (context, availability, _) {
          if (snapshot.data != true || !availability.needsAttention) {
            return const SizedBox.shrink();
          }
          return Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          '${availability.title}\n${availability.message}',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
