import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/api_models.dart';
import '../../../utils/constants.dart';
import '../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../../widgets/settings/settings_header.dart';
import 'curation_rows.dart';

/// Opens a bottom sheet showing all tracks in [album] so the user can toggle
/// individual tracks right from the Albums tab.
Future<void> showAlbumTracksCurationSheet(
  BuildContext context, {
  required AlbumModel album,
  required List<CurationCatalogSong> tracks,
  required CurationDraft draft,
  required VoidCallback onChanged,
}) {
  final catalogAlbum = CurationCatalogAlbum(
    id: album.id,
    title: album.title,
    artist: album.artist,
    songCount: album.songCount,
  );

  return showAriamiSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    header: AriamiSheetHeader(
      title: album.title,
      subtitle: '${album.artist} · ${tracks.length} tracks',
      leading: CurationAlbumArtwork(
        albumId: album.id,
        coverArt: album.coverArt,
        size: 40,
      ),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final colors = sheetContext.colors;
          final filter = draft.filter;
          final albumIncluded = filter.isAlbumIncluded(
            albumId: album.id,
            artist: album.artist,
          );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              InkWell(
                onTap: () {
                  draft.toggleAlbum(catalogAlbum);
                  setSheetState(() {});
                  onChanged();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Include entire album',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      CurationCheckCircle(
                        state: albumIncluded
                            ? CurationArtistSelectionState.all
                            : CurationArtistSelectionState.none,
                        onTap: () {
                          draft.toggleAlbum(catalogAlbum);
                          setSheetState(() {});
                          onChanged();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: colors.border),
              if (tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No tracks found for this album.',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                )
              else
                for (final song in tracks)
                  _TrackToggleRow(
                    song: song,
                    included: filter.isSongIncluded(
                      songId: song.id,
                      artist: song.artist,
                      albumId: album.id,
                      albumArtist: album.artist,
                    ),
                    onTap: () {
                      draft.toggleSong(song, albumArtist: album.artist);
                      setSheetState(() {});
                      onChanged();
                    },
                  ),
            ],
          );
        },
      ),
    ),
  );
}

/// Artist drill-down showing "Include all albums & future releases", all albums
/// (expandable to individual tracks), and standalone singles.
class ArtistCurationDetailPane extends StatefulWidget {
  const ArtistCurationDetailPane({
    super.key,
    required this.group,
    required this.draft,
    required this.songsByAlbum,
    required this.onChanged,
    this.albumCoverArtById = const <String, String>{},
  });

  final CurationArtistGroup group;
  final CurationDraft draft;
  final Map<String, List<CurationCatalogSong>> songsByAlbum;
  final VoidCallback onChanged;
  final Map<String, String> albumCoverArtById;

  @override
  State<ArtistCurationDetailPane> createState() =>
      _ArtistCurationDetailPaneState();
}

class _ArtistCurationDetailPaneState extends State<ArtistCurationDetailPane> {
  final Set<String> _expandedAlbumIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = widget.group;
    final draft = widget.draft;
    final filter = draft.filter;
    final artistWhole = draft.isArtistWholeEnabled(group.key);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: Text(
            'Include all albums & future releases',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Text(
            'New albums synced for ${group.displayName} appear automatically.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          value: artistWhole,
          onChanged: (value) {
            draft.setArtistAllToggle(group, value);
            widget.onChanged();
          },
        ),
        Divider(height: 1, color: colors.border),
        for (final album in group.albums) ...[
          _buildAlbumRow(context, album, filter, draft),
          if (_expandedAlbumIds.contains(album.id))
            for (final song in widget.songsByAlbum[album.id] ??
                const <CurationCatalogSong>[])
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: _TrackToggleRow(
                  song: song,
                  included: filter.isSongIncluded(
                    songId: song.id,
                    artist: song.artist,
                    albumId: album.id,
                    albumArtist: album.artist,
                  ),
                  onTap: () {
                    draft.toggleSong(song, albumArtist: album.artist);
                    widget.onChanged();
                  },
                ),
              ),
        ],
        if (group.standaloneSongs.isNotEmpty) ...[
          Divider(height: 1, color: colors.border),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SettingsLabel('Standalone singles'),
          ),
          for (final song in group.standaloneSongs)
            _TrackToggleRow(
              song: song,
              showTrackNumber: false,
              included: filter.isSongIncluded(
                songId: song.id,
                artist: song.artist,
              ),
              onTap: () {
                draft.toggleSong(song);
                widget.onChanged();
              },
            ),
        ],
      ],
    );
  }

  Widget _buildAlbumRow(
    BuildContext context,
    CurationCatalogAlbum album,
    LibraryCurationFilter filter,
    CurationDraft draft,
  ) {
    final colors = context.colors;
    final expanded = _expandedAlbumIds.contains(album.id);
    final included = filter.isAlbumIncluded(
      albumId: album.id,
      artist: album.artist,
    );

    return InkWell(
      onTap: () {
        draft.toggleAlbum(album);
        widget.onChanged();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            CurationAlbumArtwork(
              albumId: album.id,
              coverArt: widget.albumCoverArtById[album.id],
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
              tooltip: expanded ? 'Hide tracks' : 'Show tracks',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  if (!expanded) {
                    _expandedAlbumIds.add(album.id);
                  } else {
                    _expandedAlbumIds.remove(album.id);
                  }
                });
              },
            ),
            CurationCheckCircle(
              state: included
                  ? CurationArtistSelectionState.all
                  : CurationArtistSelectionState.none,
              onTap: () {
                draft.toggleAlbum(album);
                widget.onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackToggleRow extends StatelessWidget {
  const _TrackToggleRow({
    required this.song,
    required this.included,
    required this.onTap,
    this.showTrackNumber = true,
  });

  final CurationCatalogSong song;
  final bool included;
  final VoidCallback onTap;
  final bool showTrackNumber;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackNumber = song.trackNumber;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            if (showTrackNumber && trackNumber != null && trackNumber > 0)
              SizedBox(
                width: 28,
                child: Text(
                  '$trackNumber',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
            CurationCheckCircle(
              state: included
                  ? CurationArtistSelectionState.all
                  : CurationArtistSelectionState.none,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}
