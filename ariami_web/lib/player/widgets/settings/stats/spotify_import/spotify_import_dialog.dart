import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/player_models.dart';
import '../../../../services/player_api_client.dart';
import '../../../../services/player_host.dart';
import '../../../../services/spotify_import_controller.dart';
import '../../../../theme/player_theme.dart';

/// The Spotify Extended Streaming History import flow, driven by a
/// [SpotifyImportController]: pick the export files → preview the match
/// quality → upload in chunks → done.
class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({
    super.key,
    required this.librarySongs,
    required this.accountUserId,
    required this.apiClient,
    required this.supportsListeningSourceReset,
    this.picker,
    this.clientKind = 'web',
    this.onImported,
  });

  final List<Track> librarySongs;

  /// The signed-in account's stable identifier (its username), baked into
  /// the imported events' deterministic ids.
  final String accountUserId;

  final PlayerApiClient apiClient;

  /// Whether the server can safely remove a Spotify import. When false the
  /// 'Remove Spotify import' action is never offered (the controller also
  /// refuses undo on its own, as defense in depth).
  final bool supportsListeningSourceReset;

  final SpotifyExportPicker? picker;
  final String clientKind;
  final VoidCallback? onImported;

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  late final SpotifyImportController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SpotifyImportController(
      supportsListeningSourceReset: widget.supportsListeningSourceReset,
      picker: widget.picker,
      clientKind: widget.clientKind,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startPicker() {
    unawaited(_controller.pickAndAnalyze(
      widget.librarySongs,
      widget.accountUserId,
    ));
  }

  void _confirm() {
    unawaited(_controller.confirmUpload(widget.apiClient).then((_) {
      if (_controller.phase == SpotifyImportPhase.done) {
        widget.onImported?.call();
      }
    }));
  }

  void _undo() {
    unawaited(_controller
        .undo(
      widget.apiClient,
      accountUserId: widget.accountUserId,
    )
        .then((_) {
      if (_controller.undoDeletedCount != null) widget.onImported?.call();
    }));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.phase;
        return AlertDialog(
          title: const Text('Import from Spotify'),
          content: SizedBox(
            width: 440,
            child: _contentFor(phase),
          ),
          actions: _actionsFor(phase),
        );
      },
    );
  }

  Widget _contentFor(SpotifyImportPhase phase) {
    switch (phase) {
      case SpotifyImportPhase.idle:
        return Text(
          widget.picker?.idleDescription ??
              'Bring your Spotify listening history into Ariami. Request your '
                  '"Extended streaming history" from Spotify\'s privacy '
                  'settings, unzip it, then select your '
                  'Streaming_History_Audio_*.json files here. Your plays are '
                  'matched against this library and added to your listening '
                  'stats.',
        );
      case SpotifyImportPhase.reading:
      case SpotifyImportPhase.matching:
        return _BusyContent(message: _controller.statusMessage);
      case SpotifyImportPhase.preview:
        return _PreviewContent(controller: _controller);
      case SpotifyImportPhase.uploading:
        return _UploadingContent(controller: _controller);
      case SpotifyImportPhase.done:
        return _DoneContent(controller: _controller);
      case SpotifyImportPhase.error:
        return Text(_controller.statusMessage);
    }
  }

  List<Widget> _actionsFor(SpotifyImportPhase phase) {
    switch (phase) {
      case SpotifyImportPhase.idle:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _startPicker,
            child: Text(widget.picker?.chooseLabel ??
                'Choose Spotify history files'),
          ),
        ];
      case SpotifyImportPhase.reading:
      case SpotifyImportPhase.matching:
      case SpotifyImportPhase.uploading:
        return const [];
      case SpotifyImportPhase.preview:
        final count = _controller.result?.events.length ?? 0;
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: count == 0 ? null : _confirm,
            child: Text('Import $count plays'),
          ),
        ];
      case SpotifyImportPhase.done:
        return [
          if (_controller.undoDeletedCount == null &&
              widget.supportsListeningSourceReset)
            TextButton(
              onPressed: _controller.undoInProgress ? null : _undo,
              child: Text(
                'Remove Spotify import',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ];
      case SpotifyImportPhase.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _controller.reset,
            child: const Text('Try again'),
          ),
        ];
    }
  }
}

class _BusyContent extends StatelessWidget {
  const _BusyContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.controller});

  final SpotifyImportController controller;

  static String _percent(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    if (result == null) return const SizedBox.shrink();
    final summary = result.summary;
    final (matched, unmatched) = controller.matchedTrackCounts;
    final excluded = summary.podcastsExcluded + summary.audiobooksExcluded;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewRow(label: 'Total records', value: '${summary.totalRecords}'),
        _PreviewRow(
            label: 'Plays to import', value: '${summary.eligiblePlays}'),
        _PreviewRow(
          label: 'Matched tracks',
          value: '$matched (${_percent(result.trackMatchRate)})',
        ),
        _PreviewRow(label: 'Unmatched tracks', value: '$unmatched'),
        _PreviewRow(
          label: 'Matched plays',
          value: _percent(result.playMatchRate),
        ),
        if (excluded > 0)
          _PreviewRow(label: 'Podcasts excluded', value: '$excluded'),
        if (summary.incognitoExcluded > 0)
          _PreviewRow(
            label: 'Incognito plays excluded',
            value: '${summary.incognitoExcluded}',
          ),
        if (summary.offlineCorrected > 0)
          _PreviewRow(
            label: 'Offline plays time-corrected',
            value: '${summary.offlineCorrected}',
          ),
        if (unmatched > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Unmatched plays still count in your stats; they just aren\'t '
            'linked to a library song.',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _UploadingContent extends StatelessWidget {
  const _UploadingContent({required this.controller});

  final SpotifyImportController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.totalCount;
    final uploaded = controller.uploadedCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: total > 0 ? uploaded / total : null,
        ),
        const SizedBox(height: 12),
        Text(
          'Uploading $uploaded of $total plays…',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

class _DoneContent extends StatelessWidget {
  const _DoneContent({required this.controller});

  final SpotifyImportController controller;

  @override
  Widget build(BuildContext context) {
    final deleted = controller.undoDeletedCount;
    if (deleted != null) {
      return Text(
        'Removed $deleted imported ${deleted == 1 ? 'play' : 'plays'}.',
      );
    }
    final accepted = controller.acceptedCount;
    final duplicates = controller.duplicatesCount;
    final rejected = controller.rejectedCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Imported $accepted ${accepted == 1 ? 'play' : 'plays'} '
          '($duplicates already present).',
        ),
        if (rejected > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$rejected ${rejected == 1 ? 'play was' : 'plays were'} rejected '
            'by the server.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ],
        if (controller.undoInProgress) ...[
          const SizedBox(height: 12),
          const _BusyContent(message: 'Removing imported plays…'),
        ],
      ],
    );
  }
}
