import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'curation_rows.dart';

/// Opens a dialog showing all tracks in [album] so the user can toggle
/// individual tracks right from the Albums tab.
Future<void> showAlbumTracksCurationDialog(
  BuildContext context, {
  required CurationCatalogAlbum album,
  required List<CurationCatalogSong> initialTracks,
  required CurationDraft draft,
  required VoidCallback onChanged,
  CurationArtworkClient? artworkClient,
  Future<List<CurationCatalogSong>> Function(String albumId)? onRequestTracks,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _AlbumTracksCurationDialog(
      album: album,
      initialTracks: initialTracks,
      draft: draft,
      onChanged: onChanged,
      artworkClient: artworkClient,
      onRequestTracks: onRequestTracks,
    ),
  );
}

class _AlbumTracksCurationDialog extends StatefulWidget {
  const _AlbumTracksCurationDialog({
    required this.album,
    required this.initialTracks,
    required this.draft,
    required this.onChanged,
    this.artworkClient,
    this.onRequestTracks,
  });

  final CurationCatalogAlbum album;
  final List<CurationCatalogSong> initialTracks;
  final CurationDraft draft;
  final VoidCallback onChanged;
  final CurationArtworkClient? artworkClient;
  final Future<List<CurationCatalogSong>> Function(String albumId)?
      onRequestTracks;

  @override
  State<_AlbumTracksCurationDialog> createState() =>
      _AlbumTracksCurationDialogState();
}

class _AlbumTracksCurationDialogState
    extends State<_AlbumTracksCurationDialog> {
  late List<CurationCatalogSong> _tracks;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tracks = widget.initialTracks;
    if (_tracks.isEmpty && widget.onRequestTracks != null) {
      unawaited(_loadTracks());
    }
  }

  Future<void> _loadTracks() async {
    setState(() => _isLoading = true);
    try {
      final fetched = await widget.onRequestTracks!(widget.album.id);
      if (!mounted) return;
      setState(() {
        _tracks = fetched;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.draft.filter;
    final albumIncluded = filter.isAlbumIncluded(
      albumId: widget.album.id,
      artist: widget.album.artist,
    );

    return Dialog(
      backgroundColor: AppColors.popover,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Row(
                children: [
                  CurationAlbumArtwork(
                    albumId: widget.album.id,
                    artworkClient: widget.artworkClient,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.heading(
                            17,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.album.artist} · ${_tracks.isNotEmpty ? _tracks.length : widget.album.songCount} tracks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: () {
                setState(() => widget.draft.toggleAlbum(widget.album));
                widget.onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Include entire album',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    CurationCheckCircle(
                      state: albumIncluded
                          ? CurationArtistSelectionState.all
                          : CurationArtistSelectionState.none,
                      onTap: () {
                        setState(() => widget.draft.toggleAlbum(widget.album));
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _tracks.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No tracks found for this album.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _tracks.length,
                          itemBuilder: (context, index) {
                            final song = _tracks[index];
                            return CurationTrackToggleRow(
                              song: song,
                              included: filter.isSongIncluded(
                                songId: song.id,
                                artist: song.artist,
                                albumId: widget.album.id,
                                albumArtist: widget.album.artist,
                              ),
                              onTap: () {
                                setState(
                                  () => widget.draft.toggleSong(
                                    song,
                                    albumArtist: widget.album.artist,
                                  ),
                                );
                                widget.onChanged();
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
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
    this.artworkClient,
    this.artistImageVersion,
    this.fallbackAlbumId,
    this.fallbackSongId,
    this.onRequestAlbumTracks,
    this.showHeader = true,
    this.shrinkWrap = false,
  });

  final CurationArtistGroup group;
  final CurationDraft draft;
  final Map<String, List<CurationCatalogSong>> songsByAlbum;
  final VoidCallback onChanged;
  final CurationArtworkClient? artworkClient;
  final int? artistImageVersion;
  final String? fallbackAlbumId;
  final String? fallbackSongId;
  final Future<List<CurationCatalogSong>> Function(String albumId)?
      onRequestAlbumTracks;
  final bool showHeader;
  final bool shrinkWrap;

  @override
  State<ArtistCurationDetailPane> createState() =>
      _ArtistCurationDetailPaneState();
}

class _ArtistCurationDetailPaneState extends State<ArtistCurationDetailPane> {
  final Set<String> _expandedAlbumIds = <String>{};
  final Set<String> _loadingAlbumIds = <String>{};

  Future<void> _toggleAlbumExpanded(String albumId) async {
    if (_expandedAlbumIds.contains(albumId)) {
      setState(() => _expandedAlbumIds.remove(albumId));
      return;
    }
    setState(() => _expandedAlbumIds.add(albumId));
    if (widget.songsByAlbum.containsKey(albumId) ||
        widget.onRequestAlbumTracks == null) {
      return;
    }
    setState(() => _loadingAlbumIds.add(albumId));
    try {
      await widget.onRequestAlbumTracks!(albumId);
    } finally {
      if (mounted) {
        setState(() => _loadingAlbumIds.remove(albumId));
      }
    }
  }

  CurationArtistSelectionState _albumSelectionState(
    CurationCatalogAlbum album,
    LibraryCurationFilter filter,
  ) {
    final albumIncluded = filter.isAlbumIncluded(
      albumId: album.id,
      artist: album.artist,
    );
    final tracks = widget.songsByAlbum[album.id];
    if (tracks == null || tracks.isEmpty) {
      return albumIncluded
          ? CurationArtistSelectionState.all
          : CurationArtistSelectionState.none;
    }
    var includedCount = 0;
    for (final song in tracks) {
      if (filter.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: album.id,
        albumArtist: album.artist,
      )) {
        includedCount++;
      }
    }
    if (includedCount == 0) return CurationArtistSelectionState.none;
    if (includedCount == tracks.length && albumIncluded) {
      return CurationArtistSelectionState.all;
    }
    return CurationArtistSelectionState.partial;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final draft = widget.draft;
    final filter = draft.filter;
    final artistWhole = draft.isArtistWholeEnabled(group.key);

    return ListView(
      shrinkWrap: widget.shrinkWrap,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                CurationArtistArtwork(
                  artistName: group.displayName,
                  fallbackAlbum: group.albums.firstOrNull,
                  fallbackAlbumId: widget.fallbackAlbumId,
                  fallbackSongId: widget.fallbackSongId ??
                      group.standaloneSongs.firstOrNull?.id,
                  artworkClient: widget.artworkClient,
                  customImageVersion: widget.artistImageVersion,
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    group.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(18, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: const Text(
            'Include all albums & future releases',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            'New albums synced for ${group.displayName} appear automatically.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          value: artistWhole,
          onChanged: (value) {
            draft.setArtistAllToggle(group, value);
            widget.onChanged();
          },
        ),
        const Divider(height: 1, color: AppColors.border),
        for (final album in group.albums) ...[
          _buildAlbumRow(context, album, filter, draft),
          if (_expandedAlbumIds.contains(album.id))
            if (_loadingAlbumIds.contains(album.id))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              for (final song in widget.songsByAlbum[album.id] ??
                  const <CurationCatalogSong>[])
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: CurationTrackToggleRow(
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
          const Divider(height: 1, color: AppColors.border),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'STANDALONE SINGLES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final song in group.standaloneSongs)
            CurationTrackToggleRow(
              song: song,
              leading: CurationSongArtwork(
                song: song,
                artworkClient: widget.artworkClient,
                size: 36,
              ),
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
    final expanded = _expandedAlbumIds.contains(album.id);
    final hasTracks =
        (widget.songsByAlbum[album.id]?.isNotEmpty ?? false) ||
            widget.onRequestAlbumTracks != null;

    return InkWell(
      onTap: () {
        draft.toggleAlbum(album);
        widget.onChanged();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            CurationAlbumArtwork(
              albumId: album.id,
              artworkClient: widget.artworkClient,
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
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${album.year != null ? '${album.year} · ' : ''}${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (hasTracks)
              IconButton(
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                tooltip: expanded ? 'Hide tracks' : 'Show tracks',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_toggleAlbumExpanded(album.id)),
              ),
            CurationCheckCircle(
              state: _albumSelectionState(album, filter),
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

class CurationTrackToggleRow extends StatelessWidget {
  const CurationTrackToggleRow({
    super.key,
    required this.song,
    required this.included,
    required this.onTap,
    this.leading,
    this.showTrackNumber = true,
  });

  final CurationCatalogSong song;
  final bool included;
  final VoidCallback onTap;
  final Widget? leading;
  final bool showTrackNumber;

  @override
  Widget build(BuildContext context) {
    final trackNumber = song.trackNumber;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: leading != null ? 54 : 46,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            if (showTrackNumber && trackNumber != null && trackNumber > 0)
              SizedBox(
                width: 28,
                child: Text(
                  '$trackNumber',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
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
