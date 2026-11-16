import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../services/api/connection_service.dart';
import '../../../../services/cache/cache_manager.dart';
import '../../../../utils/constants.dart';
import '../../../../utils/dynamic_theme_seed.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import 'stats_share_card.dart';

Future<void> showStatsShareSheet({
  required BuildContext context,
  required StatsShareSnapshot snapshot,
  required int initialTabIndex,
}) {
  return showAriamiSheet<void>(
    context: context,
    child: _StatsShareSheetBody(
      snapshot: snapshot,
      initialTabIndex: initialTabIndex,
    ),
  );
}

class _StatsShareSheetBody extends StatefulWidget {
  const _StatsShareSheetBody({
    required this.snapshot,
    required this.initialTabIndex,
  });

  final StatsShareSnapshot snapshot;
  final int initialTabIndex;

  @override
  State<_StatsShareSheetBody> createState() => _StatsShareSheetBodyState();
}

class _StatsShareSheetBodyState extends State<_StatsShareSheetBody> {
  static const MethodChannel _filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
    StandardMethodCodec(),
  );

  final GlobalKey _boundaryKey = GlobalKey();
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
    final preferred = switch (widget.initialTabIndex) {
      1 => StatsShareMode.artists,
      2 => StatsShareMode.albums,
      _ => StatsShareMode.tracks,
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
    final identity = widget.snapshot.primaryArtworkFor(_mode);
    final coverKey =
        identity == null ? null : '${identity.cacheId}|${identity.artworkUrl}';
    if (coverKey == _resolvedCoverKey) return;
    _resolvedCoverKey = coverKey;
    final seq = ++_paletteSeq;

    if (identity == null) {
      if (mounted) setState(() => _coverColors = null);
      return;
    }

    PlayerColors? extracted;
    try {
      ImageProvider? provider;
      final cachedPath = await CacheManager().getArtworkPathWithFallback(
        '${identity.cacheId}_thumb',
        identity.cacheId,
      );
      if (cachedPath != null && await File(cachedPath).exists()) {
        provider = FileImage(File(cachedPath));
      } else if (identity.artworkUrl != null &&
          ConnectionService().isConnected) {
        final resolvedUrl =
            ConnectionService().resolveServerUrl(identity.artworkUrl);
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          provider = NetworkImage(
            resolvedUrl,
            headers: ConnectionService().authHeaders,
          );
        }
      }

      if (provider != null) {
        final palette = await PaletteGenerator.fromImageProvider(
          provider,
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

  PlayerColors _effectiveColors() {
    switch (_themeMode) {
      case StatsShareThemeMode.cover:
        return _coverColors ?? PlayerColors.dark;
      case StatsShareThemeMode.dark:
        return PlayerColors.dark;
      case StatsShareThemeMode.light:
        return PlayerColors.light;
    }
  }

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

  Future<void> _saveImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePngBytes();
      if (bytes == null) {
        _showError('Could not render stats image');
        return;
      }
      final savedPath = await _filePickerChannel.invokeMethod<String>('save', {
        'fileName': _exportFilename(),
        'fileType': FileType.custom.name,
        'initialDirectory': null,
        'allowedExtensions': ['png'],
        'bytes': bytes,
      });
      if (!mounted) return;
      if (savedPath != null) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.of(context).pop();
        messenger?.showSnackBar(
          const SnackBar(content: Text('Saved stats image')),
        );
      }
    } catch (e) {
      _showError('Failed to save image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePngBytes();
      if (bytes == null) {
        _showError('Could not render stats image');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${_exportFilename()}');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null ? box.localToGlobal(Offset.zero) & box.size : null;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      _showError('Failed to share image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardLimit = _mode == StatsShareMode.combined ? 5 : _limit;
    final colorScheme = Theme.of(context).colorScheme;
    final actionPadding = const EdgeInsets.symmetric(vertical: 12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AriamiSheetHeader(
          title: 'Export stats card',
          subtitle: 'Tap card to switch theme',
          trailing: _mode == StatsShareMode.combined
              ? null
              : _LimitPill(
                  limit: _limit,
                  onTap: () => setState(() => _limit = _limit == 5 ? 10 : 5),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              GestureDetector(
                onTap: () => setState(() {
                  _themeMode = StatsShareThemeMode.values[
                      (_themeMode.index + 1) %
                          StatsShareThemeMode.values.length];
                }),
                child: Center(
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: actionPadding,
                        side: BorderSide(color: context.colors.border),
                      ),
                      onPressed: _busy ? null : _saveImage,
                      icon: const Icon(LucideIcons.download, size: 17),
                      label: const Text('Save image'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: actionPadding,
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      onPressed: _busy ? null : _shareImage,
                      icon: const Icon(LucideIcons.share2, size: 17),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : (selected ? colorScheme.onSecondary : colorScheme.onSurfaceVariant);
    final background = selected ? colorScheme.secondary : Colors.transparent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: foreground,
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
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.tileRadius),
          border: Border.all(color: context.colors.border),
        ),
        child: Text(
          'Top $limit',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
            fontFeatures: AppTheme.tabular,
          ),
        ),
      ),
    );
  }
}
