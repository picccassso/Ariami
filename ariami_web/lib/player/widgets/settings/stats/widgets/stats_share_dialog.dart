import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../../services/player_host.dart';
import '../../../../theme/dynamic_theme_seed.dart';
import '../../../../theme/player_theme.dart';
import '../../../artwork_image_provider.dart';
import '../stats_models.dart';
import 'stats_share_card.dart';

Future<void> showStatsShareDialog({
  required BuildContext context,
  required StatsShareSnapshot snapshot,
  required StatsCategory initialCategory,
  StatsShareHandler? shareHandler,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final handler = shareHandler ?? maybeReadHost(context)?.statsShareHandler;
  return showDialog<void>(
    context: context,
    builder: (_) => _StatsShareDialog(
      snapshot: snapshot,
      initialCategory: initialCategory,
      messenger: messenger,
      shareHandler: handler,
    ),
  );
}

class _StatsShareDialog extends StatefulWidget {
  const _StatsShareDialog({
    required this.snapshot,
    required this.initialCategory,
    this.messenger,
    this.shareHandler,
  });

  final StatsShareSnapshot snapshot;
  final StatsCategory initialCategory;
  final ScaffoldMessengerState? messenger;
  final StatsShareHandler? shareHandler;

  @override
  State<_StatsShareDialog> createState() => _StatsShareDialogState();
}

class _StatsShareDialogState extends State<_StatsShareDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _shareButtonKey = GlobalKey();
  late StatsShareMode _mode;
  int _limit = 5;
  StatsShareThemeMode _themeMode = StatsShareThemeMode.cover;
  PlayerColors? _coverColors;
  String? _resolvedCoverKey;
  int _paletteSeq = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final preferred = switch (widget.initialCategory) {
      StatsCategory.tracks => StatsShareMode.tracks,
      StatsCategory.artists => StatsShareMode.artists,
      StatsCategory.albums => StatsShareMode.albums,
    };
    _mode = widget.snapshot.hasDataFor(preferred)
        ? preferred
        : StatsShareMode.values.firstWhere(
            widget.snapshot.hasDataFor,
            orElse: () => StatsShareMode.combined,
          );
    unawaited(_resolveCoverPalette());
  }

  Future<void> _resolveCoverPalette() async {
    final target = widget.snapshot.primaryArtworkFor(_mode);
    final client = widget.snapshot.client;
    final coverKey = target == null || client == null
        ? null
        : '${target.albumId ?? ''}|${target.songId ?? ''}';
    if (coverKey == _resolvedCoverKey) return;
    _resolvedCoverKey = coverKey;
    final seq = ++_paletteSeq;

    if (target == null || client == null) {
      if (mounted) setState(() => _coverColors = null);
      return;
    }

    final url = target.albumId != null && target.albumId!.isNotEmpty
        ? client.albumArtworkUrl(target.albumId!, thumbnail: true)
        : (target.songId != null && target.songId!.isNotEmpty
            ? client.songArtworkUrl(target.songId!, thumbnail: true)
            : null);
    if (url == null) {
      if (mounted) setState(() => _coverColors = null);
      return;
    }

    PlayerColors? extracted;
    try {
      final bytes = await ArtworkImageProvider.loadBytes(
        url,
        headers: client.artworkHeaders,
      ).timeout(const Duration(seconds: 8));
      if (bytes.isNotEmpty) {
        final palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(bytes),
          size: const Size(120, 120),
          maximumColorCount: 16,
        );
        final swatches = palette.paletteColors
            .map((s) => (color: s.color, population: s.population))
            .toList();
        final seed =
            selectDynamicThemeSeed(swatches) ?? palette.dominantColor?.color;
        if (seed != null) {
          final ambient = selectAmbientColors(swatches, seed);
          extracted = PlayerColors.fromSeed(seed, ambient: ambient);
        }
      }
    } catch (_) {
      extracted = null;
    }

    if (!mounted || seq != _paletteSeq) return;
    setState(() => _coverColors = extracted);
  }

  PlayerColors _effectiveColors() => switch (_themeMode) {
        StatsShareThemeMode.cover => _coverColors ?? PlayerColors.dark,
        StatsShareThemeMode.dark => PlayerColors.dark,
        StatsShareThemeMode.light => PlayerColors.light,
      };

  String _exportFilename() {
    final token = widget.snapshot.range.token
        .replaceAll(':', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'ariami_stats_${token}_${_mode.name}.png';
  }

  Future<Uint8List?> _capturePngBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = widget.messenger ?? ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyImage() async {
    final handler = widget.shareHandler;
    if (_busy || handler == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePngBytes();
      if (bytes == null) {
        _showMessage('Could not render stats image');
        return;
      }
      final copied = await handler.copyPng(bytes);
      _showMessage(
        copied
            ? 'Copied stats image to clipboard'
            : 'Could not copy stats image to clipboard',
      );
    } catch (e) {
      _showMessage('Failed to copy image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveImage() async {
    final handler = widget.shareHandler;
    if (_busy || handler == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePngBytes();
      if (bytes == null) {
        _showMessage('Could not render stats image');
        return;
      }
      final saved = await handler.savePng(bytes, _exportFilename());
      if (!mounted) return;
      if (saved) {
        _showMessage('Saved stats image');
      }
    } catch (e) {
      _showMessage('Failed to save image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() async {
    final handler = widget.shareHandler;
    if (_busy || handler == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePngBytes();
      if (bytes == null) {
        _showMessage('Could not render stats image');
        return;
      }
      if (!mounted) return;
      final box = (_shareButtonKey.currentContext?.findRenderObject() ??
          context.findRenderObject()) as RenderBox?;
      final origin =
          box != null ? box.localToGlobal(Offset.zero) & box.size : null;
      await handler.sharePng(
        bytes,
        _exportFilename(),
        sharePositionOrigin: origin,
      );
    } catch (e) {
      _showMessage('Failed to share image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardLimit = _mode == StatsShareMode.combined ? 5 : _limit;
    final handler = widget.shareHandler;
    final showCopy = handler?.supportsCopy ?? false;
    final showSave = handler?.supportsSave ?? false;
    final showShare = handler?.supportsShare ?? false;
    final buttonPadding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 11);

    return Dialog(
      backgroundColor: colors.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayerTheme.panelRadius),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export stats card',
                          style: PlayerTheme.heading(
                            16,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Click card to switch theme',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_mode != StatsShareMode.combined) ...[
                    _LimitPill(
                      limit: _limit,
                      onTap: () =>
                          setState(() => _limit = _limit == 5 ? 10 : 5),
                    ),
                    const SizedBox(width: 6),
                  ],
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final entry in const [
                    (StatsShareMode.tracks, 'Tracks'),
                    (StatsShareMode.artists, 'Artists'),
                    (StatsShareMode.albums, 'Albums'),
                    (StatsShareMode.combined, 'All'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _ModeTab(
                          label: entry.$2,
                          selected: _mode == entry.$1,
                          enabled: widget.snapshot.hasDataFor(entry.$1),
                          onTap: () {
                            setState(() => _mode = entry.$1);
                            unawaited(_resolveCoverPalette());
                          },
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Center(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _themeMode = StatsShareThemeMode.values[
                              (_themeMode.index + 1) %
                                  StatsShareThemeMode.values.length];
                        }),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: StatsShareCard(
                              snapshot: widget.snapshot,
                              mode: _mode,
                              limit: cardLimit,
                              colors: _effectiveColors(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showCopy || showSave || showShare) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (showCopy)
                      Expanded(
                        child: FilledButton.icon(
                          style:
                              FilledButton.styleFrom(padding: buttonPadding),
                          onPressed: _busy ? null : _copyImage,
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy image'),
                        ),
                      ),
                    if (showCopy && (showSave || showShare))
                      const SizedBox(width: 8),
                    if (showSave)
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              padding: buttonPadding),
                          onPressed: _busy ? null : _saveImage,
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Save image'),
                        ),
                      ),
                    if (showSave && showShare) const SizedBox(width: 8),
                    if (showShare)
                      Expanded(
                        child: OutlinedButton.icon(
                          key: _shareButtonKey,
                          style: OutlinedButton.styleFrom(
                              padding: buttonPadding),
                          onPressed: _busy ? null : _shareImage,
                          icon: const Icon(Icons.share_rounded, size: 16),
                          label: const Text('Share'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = !enabled
        ? colors.textSecondary.withValues(alpha: 0.4)
        : (selected ? colors.base : colors.textSecondary);
    final background = selected ? colors.textPrimary : Colors.transparent;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitPill extends StatelessWidget {
  const _LimitPill({required this.limit, required this.onTap});

  final int limit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            'Top $limit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: PlayerTheme.tabular,
            ),
          ),
        ),
      ),
    );
  }
}
