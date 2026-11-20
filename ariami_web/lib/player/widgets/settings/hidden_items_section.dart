import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../curation/curation_rows.dart';
import '../../models/player_models.dart';
import '../../services/library_controller.dart';
import '../../theme/player_theme.dart';
import '../curate_library_dialog.dart';
import 'settings_widgets.dart';

/// Library curation controls and excluded/hidden items for the signed-in user.
class HiddenItemsSection extends StatelessWidget {
  const HiddenItemsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final curation = library.curation;
    final hidden = library.hiddenItems;
    final colors = context.colors;
    final isCurated = curation.mode == LibraryCurationMode.curated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionCard(
          title: 'My Library Curation',
          subtitle: isCurated
              ? 'Curated Mode: only artists, albums, server playlists, and '
                  'songs you pick appear in your library. (${UserLibraryCuration.formatSummaryLabel(curation.toSummaryJson())})'
              : 'Include Everything: the whole server catalog shows '
                  'automatically unless you hide an item.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isCurated
                          ? 'Active mode: Curated Mode'
                          : 'Active mode: Include Everything',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => showPlayerLibraryCurationDialog(context),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Curate My Library…'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DesktopSegmentedControl<LibraryCurationMode>(
                options: const [
                  DesktopSegmentedOption(
                    value: LibraryCurationMode.full,
                    label: 'Include Everything',
                  ),
                  DesktopSegmentedOption(
                    value: LibraryCurationMode.curated,
                    label: 'Curated Mode',
                  ),
                ],
                selectedValue: curation.mode,
                onChanged: (mode) {
                  if (mode == curation.mode) return;
                  if (mode == LibraryCurationMode.full) {
                    library.saveCuration(
                      mode: LibraryCurationMode.full,
                      rules: curation.rules,
                      onboardingCompleted: true,
                    );
                  } else {
                    showPlayerLibraryCurationDialog(
                      context,
                      initialModeOverride: LibraryCurationMode.curated,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          title: 'Excluded / Hidden items',
          subtitle: hidden.isEmpty
              ? 'Right-click an album, playlist or artist in the sidebar to '
                  'remove it from your library view.'
              : '${hidden.length} ${hidden.length == 1 ? 'item is' : 'items are'} '
                  'excluded from your library view.',
          child: hidden.isEmpty
              ? Text(
                  'Nothing is excluded.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                )
              : Column(
                  children: [
                    for (final item in hidden)
                      _HiddenRow(
                        item: item,
                        onUnhide: () =>
                            library.unhideItem(item.type, item.targetId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HiddenRow extends StatelessWidget {
  const _HiddenRow({required this.item, required this.onUnhide});

  final HiddenMediaItem item;
  final VoidCallback onUnhide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = context.read<LibraryController>();
    final kind = '${item.type[0].toUpperCase()}${item.type.substring(1)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildThumbnail(library),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    // A target whose album has left the library can still be
                    // unhidden; it just has nothing to come back to yet.
                    color: item.missing ? colors.textSecondary : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    kind,
                    if (item.subtitle != null) item.subtitle!,
                    if (item.missing) 'no longer in your library',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onUnhide, child: const Text('Unhide')),
        ],
      ),
    );
  }

  Widget _buildThumbnail(LibraryController library) {
    switch (item.type) {
      case HiddenMediaItem.albumType:
        return CurationAlbumArtwork(
          albumId: item.targetId,
          artworkClient: library.client,
          size: 36,
        );
      case HiddenMediaItem.artistType:
        final key = item.name.trim().toLowerCase();
        Album? firstAlbum;
        for (final a in library.rawAlbums) {
          if (a.artist.toLowerCase().contains(key)) {
            firstAlbum = a;
            break;
          }
        }
        return CurationArtistArtwork(
          artistName: item.name,
          fallbackAlbum: firstAlbum == null
              ? null
              : CurationCatalogAlbum(
                  id: firstAlbum.id,
                  title: firstAlbum.title,
                  artist: firstAlbum.artist,
                  songCount: firstAlbum.songCount,
                ),
          artworkClient: library.client,
          customImageVersion: library.artistImageVersion(item.name),
          size: 36,
        );
      case HiddenMediaItem.playlistType:
        final playlist = library.rawServerPlaylists
            .where((p) => p.id == item.targetId)
            .firstOrNull;
        final albumIds = <String>[];
        if (playlist != null) {
          final songAlbumById = <String, String>{
            for (final s in library.rawSongs)
              if (s.albumId != null && s.albumId!.trim().isNotEmpty)
                s.id: s.albumId!,
          };
          for (final songId in playlist.songIds) {
            final albumId = songAlbumById[songId];
            if (albumId != null && !albumIds.contains(albumId)) {
              albumIds.add(albumId);
              if (albumIds.length == 4) break;
            }
          }
        }
        return CurationPlaylistArtwork(
          playlistId: item.targetId,
          playlistName: item.name,
          albumIds: albumIds,
          artworkClient: library.client,
          customImageVersion: library.playlistImageVersion(item.targetId),
          size: 36,
        );
      default:
        return SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.visibility_off_rounded, size: 18),
        );
    }
  }
}
