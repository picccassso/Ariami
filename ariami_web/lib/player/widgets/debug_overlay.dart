import 'dart:async';

import 'package:ariami_core/models/quality_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio/equalizer_service.dart';
import '../services/audio/gapless_playback_service.dart';
import '../services/sensitive_info_service.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/debug_overlay_service.dart';
import '../theme/player_theme.dart';

/// Live playback diagnostics, shown in the corner of the player shell when the
/// user enables it in Settings → Developer.
///
/// Collapsed it is a single chip with the three signals that answer "is the
/// file or the stream at fault": what is actually playing (format + effective
/// bitrate, original vs transcoded), buffer headroom, and EQ. Tapping it
/// expands a full panel with a copyable report for sharing with support.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  static const _green = Color(0xFF4ADE80);
  static const _amber = Color(0xFFE8B33D);

  bool _expanded = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuilds when either the overlay toggle or the sensitive-info setting
      // flips, so masking follows Settings → General live.
      listenable: Listenable.merge(
        [DebugOverlayService.instance, SensitiveInfoService.instance],
      ),
      builder: (context, _) {
        if (!DebugOverlayService.instance.enabled) {
          return const SizedBox.shrink();
        }
        final audio = context.watch<AudioController>();
        final connection = context.watch<ConnectionController>();
        final eq = context.watch<EqualizerService>();
        final gapless = context.watch<GaplessPlaybackService>();
        // Position/buffer ticks come through the coalesced progress listenable,
        // not the controller itself, so the headroom stays live.
        return ListenableBuilder(
          listenable: audio.progress,
          builder: (context, _) => _build(
            context,
            audio: audio,
            connection: connection,
            eq: eq,
            gapless: gapless,
          ),
        );
      },
    );
  }

  Widget _build(
    BuildContext context, {
    required AudioController audio,
    required ConnectionController connection,
    required EqualizerService eq,
    required GaplessPlaybackService gapless,
  }) {
    final colors = context.colors;
    final errorColor = Theme.of(context).colorScheme.error;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: colors.textPrimary,
    );
    final info = audio.lastSource;
    final track = audio.currentTrack;
    final rows = _reportRows(
      audio: audio,
      connection: connection,
      eq: eq,
      gapless: gapless,
    );

    final chip = GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceHigh.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: _dotColor(audio, errorColor),
                shape: BoxShape.circle,
              ),
            ),
            Flexible(
              child: Text(
                _chipText(audio, eq, info, track),
                style: mono,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (!_expanded) return chip;

    return Container(
      width: 340,
      constraints: const BoxConstraints(maxHeight: 380),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Playback debug',
                style: mono.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                tooltip: _copied ? 'Copied' : 'Copy report',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                onPressed: () => _copyReport(rows),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  color: _copied ? _green : colors.textSecondary,
                ),
              ),
              IconButton(
                tooltip: 'Collapse',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _expanded = false),
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              ),
            ],
          ),
          Divider(color: colors.border, height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Text.rich(
                        TextSpan(
                          style: mono,
                          children: [
                            TextSpan(
                              text: '${row.label}: ',
                              style: mono.copyWith(color: colors.textSecondary),
                            ),
                            TextSpan(text: row.value),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _chipText(
    AudioController audio,
    EqualizerService eq,
    PlaybackSourceInfo? info,
    Track? track,
  ) {
    final parts = <String>[];
    final summary = _sourceSummary(info, track?.durationSeconds ?? 0);
    if (summary != null) parts.add(summary);
    if (audio.isRemoteActive) {
      parts.add('remote: ${audio.remoteDeviceName ?? 'device'}');
    } else if (audio.isCastActive) {
      parts.add('cast: ${audio.castDeviceName ?? 'device'}');
    } else {
      final headroom = audio.bufferedPosition - audio.position;
      parts.add('buf ${_fmtSeconds(headroom)}');
    }
    if (eq.isSupported && eq.isEnabled) parts.add('EQ ${eq.selectedPresetName}');
    return parts.isEmpty ? 'idle' : parts.join(' · ');
  }

  Color _dotColor(AudioController audio, Color errorColor) {
    if (audio.errorMessage != null) return errorColor;
    if (audio.isRemoteActive || audio.isCastActive || !audio.isPlayingHere) {
      return context.colors.textSecondary;
    }
    final headroom = audio.bufferedPosition - audio.position;
    if (headroom < const Duration(seconds: 3)) return errorColor;
    if (headroom < const Duration(seconds: 10)) return _amber;
    return _green;
  }

  List<({String label, String value})> _reportRows({
    required AudioController audio,
    required ConnectionController connection,
    required EqualizerService eq,
    required GaplessPlaybackService gapless,
  }) {
    final info = audio.lastSource;
    final track = audio.currentTrack;
    final durationSeconds = track?.durationSeconds ?? 0;
    final headroom = audio.bufferedPosition - audio.position;
    final server = connection.serverInfo;

    String mode;
    if (audio.isOfflinePlayback || connection.isOfflineActive) {
      mode = 'offline';
    } else if (connection.isLocalServer) {
      mode = 'local server';
    } else {
      mode = 'remote';
    }
    final endpoint = server != null ? '${server.host}:${server.port}' : '—';

    // Follow the same rule as SensitiveText: when the user hides sensitive
    // info (Settings → General), mask hosts and local paths here too, so a
    // shared screen or copied report doesn't leak them.
    final reveal = SensitiveInfoService.instance.visible;

    return <({String label, String value})>[
      (
        label: 'track',
        value: track == null ? 'nothing playing' : '${track.title} — ${track.artist}',
      ),
      if (track != null) (label: 'id', value: track.id),
      (label: 'source', value: _sourceKindLabel(info)),
      if (info?.filePath case final path?)
        (
          label: 'file',
          value:
              '${reveal ? path : _maskPath(path)} (${_fmtBytes(info!.fileSizeBytes)})',
        ),
      if (info?.redactedStreamUri case final uri?)
        (label: 'url', value: reveal ? '$uri' : _maskHostInUrl(uri)),
      if (info?.sourceFormat case final fmt?)
        (
          label: 'source file',
          value:
              '${fmt.toUpperCase()} ${info!.sourceBitrateKbps ?? '?'} kbps',
        ),
      (label: 'audio', value: _sourceSummary(info, durationSeconds) ?? '—'),
      (
        label: 'quality',
        value:
            'requested ${audio.quality.name}, effective ${audio.effectiveQuality.name}'
            '${audio.isLocalPlayback ? ' (local playback pins original)' : ''}',
      ),
      (
        label: 'position',
        value:
            '${_fmtDuration(audio.position)} / ${audio.duration != null ? _fmtDuration(audio.duration!) : '—'}',
      ),
      (
        label: 'buffer',
        value: (audio.isRemoteActive || audio.isCastActive)
            ? '— (remote playback)'
            : '${_fmtSeconds(headroom)} headroom',
      ),
      (
        label: 'state',
        value:
            '${audio.isPlaying ? 'playing' : audio.isLoading ? 'loading' : 'paused'} · ${audio.localProcessingState.name}',
      ),
      (label: 'volume', value: '${(audio.volume * 100).round()}%'),
      (
        label: 'eq',
        value: !eq.isSupported
            ? 'unsupported'
            : eq.isEnabled
                ? eq.selectedPresetName
                : 'off',
      ),
      (label: 'gapless', value: gapless.isEnabled ? 'on' : 'off'),
      (
        label: 'mode',
        value: '$mode · ${reveal ? endpoint : _maskEndpoint(endpoint)}',
      ),
      if (server != null)
        (label: 'server', value: '${server.name} v${server.version}'),
      if (audio.isRemoteActive)
        (label: 'remote device', value: audio.remoteDeviceName ?? '—'),
      if (audio.isCastActive)
        (label: 'cast device', value: audio.castDeviceName ?? '—'),
      if (audio.errorMessage case final error?) (label: 'error', value: error),
    ];
  }

  void _copyReport(List<({String label, String value})> rows) {
    final buffer = StringBuffer('Ariami playback debug report\n');
    buffer.writeln('${DateTime.now().toIso8601String()}\n');
    for (final row in rows) {
      buffer.writeln('${row.label}: ${row.value}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

/// One line of the chip: what is actually playing, e.g. `FLAC 1411 kbps`,
/// `AAC 128 kbps (transcoded)` or `original stream`.
String? _sourceSummary(PlaybackSourceInfo? info, int durationSeconds) {
  if (info == null) return null;
  switch (info.kind) {
    case PlaybackSourceKind.offlineFile:
    case PlaybackSourceKind.serverFile:
    case PlaybackSourceKind.downloadedFile:
      final ext = info.fileExtension;
      final format = ext.isEmpty ? 'file' : ext.toUpperCase();
      final kbps = info.fileBitrateKbps(durationSeconds);
      return kbps == null ? format : '$format $kbps kbps';
    case PlaybackSourceKind.stream:
      // StreamQuality and QualityPreset share the high/medium/low order.
      final preset = QualityPreset.values[info.quality.index];
      final bitrate = preset.bitrate;
      if (bitrate != null) {
        // Transcoded: the preset is the exact streamed bitrate (CBR AAC);
        // mention the source file's specs when the server reported them.
        final source = info.sourceFormat != null && info.sourceBitrateKbps != null
            ? ' from ${info.sourceFormat!.toUpperCase()} ${info.sourceBitrateKbps} kbps'
            : '';
        return 'AAC $bitrate kbps (transcoded$source)';
      }
      // Original file streamed: the ticket reports the source's real specs.
      final fmt = info.sourceFormat;
      final kbps = info.sourceBitrateKbps;
      if (fmt != null && kbps != null) return '${fmt.toUpperCase()} $kbps kbps · stream';
      return 'original stream';
  }
}

String _sourceKindLabel(PlaybackSourceInfo? info) {
  if (info == null) return '—';
  return switch (info.kind) {
    PlaybackSourceKind.offlineFile => 'offline file',
    PlaybackSourceKind.serverFile => 'library file (local)',
    PlaybackSourceKind.downloadedFile => 'downloaded file',
    PlaybackSourceKind.stream => 'stream',
  };
}

String _fmtDuration(Duration d) {
  final total = d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String _fmtSeconds(Duration d) {
  if (d.inSeconds >= 10) return '${d.inSeconds}s';
  return '${d.inMilliseconds / 1000}s';
}

String _fmtBytes(int? bytes) {
  if (bytes == null) return 'unknown size';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Masks just the host of a stream URL, keeping scheme/port/path (and the
/// already-redacted query) so the row stays useful in a shared report.
String _maskHostInUrl(Uri uri) {
  final host = uri.host;
  if (host.isEmpty) return uri.toString();
  return uri.toString().replaceFirst(host, SensitiveInfoService.mask);
}

/// Masks the host of a `host:port` endpoint, keeping the port.
String _maskEndpoint(String endpoint) {
  final colon = endpoint.lastIndexOf(':');
  if (colon <= 0) return SensitiveInfoService.mask;
  return '${SensitiveInfoService.mask}:${endpoint.substring(colon + 1)}';
}

/// Masks a local file path down to its basename.
String _maskPath(String path) {
  final slash = path.lastIndexOf('/');
  final base = slash < 0 ? path : path.substring(slash + 1);
  return '${SensitiveInfoService.mask}/$base';
}
