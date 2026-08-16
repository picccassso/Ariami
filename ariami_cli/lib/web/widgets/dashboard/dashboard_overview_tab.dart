import 'package:flutter/material.dart';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/models/playlist_suggestion.dart';

import '../../utils/layout.dart';
import 'auth_required_banner.dart';
import 'dashboard_keep_alive_tab.dart';
import 'library_stats_section.dart';
import 'server_status_card.dart';
import 'spotify_stats_section.dart';
import 'suggested_playlists_section.dart';

class DashboardOverviewTab extends StatelessWidget {
  const DashboardOverviewTab({
    super.key,
    required this.serverRunning,
    required this.isScanning,
    required this.pulseController,
    required this.authRequired,
    required this.songCount,
    required this.albumCount,
    required this.connectedClients,
    required this.connectedUsers,
    required this.activeSessions,
    required this.lastScanTimeFormatted,
    required this.playlistSuggestions,
    required this.decidingSuggestionPaths,
    required this.onImportSuggestion,
    required this.onIgnoreSuggestion,
    required this.onRescanLibrary,
    required this.onImportSpotifyStats,
    required this.onRemoveSpotifyStats,
    required this.spotifyImportStatus,
    this.lanServer,
    this.tailscaleServer,
  });

  final bool serverRunning;
  final bool isScanning;
  final AnimationController pulseController;
  final bool authRequired;
  final int songCount;
  final int albumCount;
  final int connectedClients;
  final int connectedUsers;
  final int activeSessions;
  final String lastScanTimeFormatted;
  final List<PlaylistSuggestion> playlistSuggestions;
  final Set<String> decidingSuggestionPaths;
  final void Function(PlaylistSuggestion suggestion) onImportSuggestion;
  final void Function(PlaylistSuggestion suggestion) onIgnoreSuggestion;
  final VoidCallback onRescanLibrary;
  final VoidCallback onImportSpotifyStats;
  final VoidCallback onRemoveSpotifyStats;
  final SpotifyImportStatus? spotifyImportStatus;
  final String? lanServer;
  final String? tailscaleServer;

  @override
  Widget build(BuildContext context) {
    final gap = AppLayout.sectionGap(AppLayout.of(context));

    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerStatusCard(
            serverRunning: serverRunning,
            isScanning: isScanning,
            pulseController: pulseController,
            lanServer: lanServer,
            tailscaleServer: tailscaleServer,
          ),
          if (authRequired) ...[
            const SizedBox(height: 12),
            const AuthRequiredBanner(),
          ],
          SizedBox(height: gap),
          LibraryStatsSection(
            songCount: songCount,
            albumCount: albumCount,
            connectedClients: connectedClients,
            connectedUsers: connectedUsers,
            activeSessions: activeSessions,
            lastScanTimeFormatted: lastScanTimeFormatted,
            isScanning: isScanning,
            onRescanLibrary: onRescanLibrary,
          ),
          if (playlistSuggestions.isNotEmpty) ...[
            SizedBox(height: gap),
            SuggestedPlaylistsSection(
              suggestions: playlistSuggestions,
              decidingFolderPaths: decidingSuggestionPaths,
              onImport: onImportSuggestion,
              onIgnore: onIgnoreSuggestion,
            ),
          ],
          SizedBox(height: gap),
          SpotifyStatsSection(
            importStatus: spotifyImportStatus,
            onImportSpotifyStats: onImportSpotifyStats,
            onRemoveSpotifyStats: onRemoveSpotifyStats,
          ),
        ],
      ),
    );
  }
}
