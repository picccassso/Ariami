import 'package:flutter/material.dart';

import '../models/player_models.dart';
import 'playback_helpers.dart';
import 'record_tile.dart';

class PlaylistPlayFab extends StatelessWidget {
  const PlaylistPlayFab({super.key, required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) =>
      CoverPlayButton(onPressed: () => playPlaylist(context, playlist));
}
