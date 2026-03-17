import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/playlist_service.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Bottom sheet widget for importing playlists from the server.
class ServerPlaylistsSheet extends StatelessWidget {
  final PlaylistService playlistService;
  final List<ServerPlaylist> visiblePlaylists;
  final Function(ServerPlaylist) onImportPlaylist;
  final VoidCallback onImportAll;

  const ServerPlaylistsSheet({
    super.key,
    required this.playlistService,
    required this.visiblePlaylists,
    required this.onImportPlaylist,
    required this.onImportAll,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          minimum: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(context),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.cloud_download, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Import from Server',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (visiblePlaylists.isNotEmpty)
                      TextButton.icon(
                        onPressed: onImportAll,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Import All'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Folder playlists found on your server. Tap to import as a local playlist.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              // Playlist list
              Expanded(
                child: visiblePlaylists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle,
                                size: 48, color: Colors.green[400]),
                            const SizedBox(height: 16),
                            Text(
                              'All playlists imported!',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: visiblePlaylists.length,
                        itemBuilder: (context, index) {
                          final serverPlaylist = visiblePlaylists[index];
                          return ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.blue[400]!,
                                    Colors.blue[700]!
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child:
                                  const Icon(Icons.folder, color: Colors.white),
                            ),
                            title: Text(serverPlaylist.name),
                            subtitle: Text('${serverPlaylist.songCount} songs'),
                            trailing: const Icon(Icons.download),
                            onTap: () => onImportPlaylist(serverPlaylist),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows the server playlists import bottom sheet.
Future<void> showServerPlaylistsSheet({
  required BuildContext context,
  required PlaylistService playlistService,
  required Function(ServerPlaylist) onImportPlaylist,
  required VoidCallback onImportAll,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return ServerPlaylistsSheet(
        playlistService: playlistService,
        visiblePlaylists: playlistService.visibleServerPlaylists,
        onImportPlaylist: onImportPlaylist,
        onImportAll: onImportAll,
      );
    },
  );
}
