import 'package:ariami_core/models/music_availability.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';

class MusicAvailabilityBanner extends StatelessWidget {
  const MusicAvailabilityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final availability =
        connection.client?.musicAvailability ?? MusicAvailability.unknown;
    if (!connection.isConnected || !availability.needsAttention) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.folder_off_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${availability.title}\n${availability.message}',
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}
