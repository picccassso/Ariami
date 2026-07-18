import 'package:flutter/material.dart';

class PlaylistOfflineCopyBanner extends StatelessWidget {
  const PlaylistOfflineCopyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        'Offline copy: this playlist is no longer available on the server.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
