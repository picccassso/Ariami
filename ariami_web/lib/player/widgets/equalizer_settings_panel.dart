import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio/equalizer_service.dart';
import '../theme/player_theme.dart';
import 'settings/settings_widgets.dart' show SettingsLabel;
import 'queue_intent.dart';

class EqualizerSettingsPanel extends StatelessWidget {
  const EqualizerSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final equalizer = context.watch<EqualizerService>();
    final parameters = equalizer.parameters;
    final presets = <String>[
      ...equalizer.builtInPresetNames,
      ...equalizer.userPresetNames,
      if (equalizer.selectedPresetName == EqualizerService.customPresetName)
        EqualizerService.customPresetName,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equalizer',
                      style: TextStyle(
                        fontFamily: PlayerTheme.headingFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Shape how playback sounds on this device.'),
                  ],
                ),
              ),
              Switch(
                value: equalizer.isEnabled,
                onChanged: (value) => unawaited(equalizer.setEnabled(value)),
              ),
            ],
          ),
          if (!equalizer.isSupported) ...[
            const SizedBox(height: 18),
            Text(
              'The equalizer is unavailable on this platform.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 20),
            const SettingsLabel('Preset'),
            const SizedBox(height: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: equalizer.isEnabled ? 1 : 0.45,
              child: IgnorePointer(
                ignoring: !equalizer.isEnabled,
                child: _EqualizerPresetDropdown(
                  equalizer: equalizer,
                  presets: presets,
                  onConfirmDelete: (preset) => unawaited(
                    _confirmDeletePreset(context, equalizer, preset),
                  ),
                  onSavePreset: () => _savePreset(context, equalizer),
                ),
              ),
            ),
            if (parameters != null) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  const SettingsLabel('Bands'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: equalizer.isEnabled
                        ? () {
                            final previous = equalizer.selectedPresetName;
                            unawaited(equalizer.resetToFlat());
                            showUndoToast(
                              ScaffoldMessenger.maybeOf(context),
                              'Equalizer reset to flat',
                              onUndo: () =>
                                  unawaited(equalizer.applyPreset(previous)),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Reset'),
                  ),
                ],
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: equalizer.isEnabled ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !equalizer.isEnabled,
                  child: _EqualizerGraph(
                    frequencies: parameters.bandFrequencies,
                    gains: [
                      for (var index = 0; index < parameters.bandCount; index++)
                        index < equalizer.currentBandGains.length
                            ? equalizer.currentBandGains[index]
                            : 0.0,
                    ],
                    minimum: parameters.minDecibels,
                    maximum: parameters.maxDecibels,
                    onChanged: (index, gain) => unawaited(
                      equalizer.setBandGain(index, gain),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static Future<void> _savePreset(
    BuildContext context,
    EqualizerService equalizer,
  ) async {
    final controller = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Save equalizer preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Preset name',
              errorText: error,
            ),
            onChanged: (_) => setState(() => error = null),
            onSubmitted: (_) => _submitPreset(
              dialogContext,
              equalizer,
              controller.text,
              (message) => setState(() => error = message),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _submitPreset(
                dialogContext,
                equalizer,
                controller.text,
                (message) => setState(() => error = message),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  static Future<void> _submitPreset(
    BuildContext context,
    EqualizerService equalizer,
    String rawName,
    ValueChanged<String> showError,
  ) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      showError('Enter a preset name');
      return;
    }
    if (equalizer.isReservedPresetName(name)) {
      showError('That name is reserved');
      return;
    }
    await equalizer.saveCurrentAsPreset(name);
    if (context.mounted) Navigator.pop(context);
  }

  static Future<void> _confirmDeletePreset(
    BuildContext context,
    EqualizerService equalizer,
    String name,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('“$name” will be removed from your presets.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) await equalizer.deleteUserPreset(name);
  }
}

/// Graphic-equalizer presentation of the bands: one vertical fader per band
/// over a dB grid, with the frequency-response curve drawn behind the thumbs.
class _EqualizerGraph extends StatefulWidget {
  const _EqualizerGraph({
    required this.frequencies,
    required this.gains,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final List<double> frequencies;
  final List<double> gains;
  final double minimum;
  final double maximum;
  final void Function(int index, double gain) onChanged;

  @override
  State<_EqualizerGraph> createState() => _EqualizerGraphState();
}

class _EqualizerGraphState extends State<_EqualizerGraph> {
  static const double _graphHeight = 220;
  static const double _dbGutter = 36;
  static const double _thumbRadius = 7;

  int? _activeBand;

  double _bandCenterX(int index, double width) {
    final plotWidth = width - _dbGutter;
    return _dbGutter + (index + 0.5) * plotWidth / widget.gains.length;
  }

  int _nearestBand(double dx, double width) {
    var nearest = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < widget.gains.length; index++) {
      final distance = (dx - _bandCenterX(index, width)).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = index;
      }
    }
    return nearest;
  }

  double _gainForOffset(double dy) {
    const top = _thumbRadius + 2;
    const bottom = _graphHeight - _thumbRadius - 2;
    final fraction = ((bottom - dy) / (bottom - top)).clamp(0.0, 1.0);
    return widget.minimum + fraction * (widget.maximum - widget.minimum);
  }

  void _updateBand(Offset position, double width, {bool pickBand = false}) {
    if (pickBand || _activeBand == null) {
      _activeBand = _nearestBand(position.dx, width);
    }
    widget.onChanged(_activeBand!, _gainForOffset(position.dy));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).sliderTheme.activeTrackColor ??
        Theme.of(context).colorScheme.secondary;
    final labelStyle = TextStyle(
      color: context.colors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: _dbGutter),
          child: Row(
            children: [
              for (final gain in widget.gains)
                Expanded(
                  child: Text(
                    '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _graphHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _updateBand(
                  details.localPosition,
                  constraints.maxWidth,
                  pickBand: true,
                ),
                onVerticalDragStart: (details) => _updateBand(
                  details.localPosition,
                  constraints.maxWidth,
                  pickBand: true,
                ),
                onVerticalDragUpdate: (details) =>
                    _updateBand(details.localPosition, constraints.maxWidth),
                onVerticalDragEnd: (_) => setState(() => _activeBand = null),
                onVerticalDragCancel: () => setState(() => _activeBand = null),
                child: CustomPaint(
                  painter: _EqualizerGraphPainter(
                    gains: widget.gains,
                    minimum: widget.minimum,
                    maximum: widget.maximum,
                    activeBand: _activeBand,
                    accent: accent,
                    gridColor: context.colors.border,
                    centerLineColor:
                        context.colors.textSecondary.withValues(alpha: 0.55),
                    trackColor: context.colors.border,
                    thumbColor: context.colors.textPrimary,
                    labelColor: context.colors.textSecondary,
                    gutterWidth: _dbGutter,
                    thumbRadius: _thumbRadius,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: _dbGutter),
          child: Row(
            children: [
              for (final frequency in widget.frequencies)
                Expanded(
                  child: Text(
                    frequency >= 1000
                        ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
                        : '${frequency.round()}',
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EqualizerGraphPainter extends CustomPainter {
  const _EqualizerGraphPainter({
    required this.gains,
    required this.minimum,
    required this.maximum,
    required this.activeBand,
    required this.accent,
    required this.gridColor,
    required this.centerLineColor,
    required this.trackColor,
    required this.thumbColor,
    required this.labelColor,
    required this.gutterWidth,
    required this.thumbRadius,
  });

  final List<double> gains;
  final double minimum;
  final double maximum;
  final int? activeBand;
  final Color accent;
  final Color gridColor;
  final Color centerLineColor;
  final Color trackColor;
  final Color thumbColor;
  final Color labelColor;
  final double gutterWidth;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final top = thumbRadius + 2;
    final bottom = size.height - thumbRadius - 2;
    final plotLeft = gutterWidth;
    final plotRight = size.width;

    double yFor(double db) =>
        top + (maximum - db) / (maximum - minimum) * (bottom - top);
    double xFor(int index) =>
        plotLeft + (index + 0.5) * (plotRight - plotLeft) / gains.length;

    // dB grid: labelled lines at max/0/min, unlabelled ones halfway between.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1.2;
    for (final db in [maximum, maximum / 2, 0.0, minimum / 2, minimum]) {
      final y = yFor(db);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(plotRight, y),
        db == 0 ? centerPaint : gridPaint,
      );
      if (db == 0 || db == maximum || db == minimum) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: db == 0 ? '0' : '${db > 0 ? '+' : ''}${db.round()}',
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(plotLeft - textPainter.width - 8, y - textPainter.height / 2),
        );
      }
    }

    // Frequency-response curve through the band thumbs, with a soft fill
    // underneath so the shape reads as a curve rather than isolated dots.
    final points = [
      for (var index = 0; index < gains.length; index++)
        Offset(xFor(index), yFor(gains[index].clamp(minimum, maximum))),
    ];
    final curve = Path()..moveTo(plotLeft, points.first.dy);
    curve.lineTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final from = points[index];
      final to = points[index + 1];
      final midX = (from.dx + to.dx) / 2;
      curve.cubicTo(midX, from.dy, midX, to.dy, to.dx, to.dy);
    }
    curve.lineTo(plotRight, points.last.dy);

    final fill = Path.from(curve)
      ..lineTo(plotRight, bottom)
      ..lineTo(plotLeft, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.26),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(
          Rect.fromLTRB(plotLeft, top, plotRight, bottom),
        ),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Faders: a slim full-height track per band, the accent run from the
    // 0 dB line to the thumb, then the thumb itself.
    final centerY = yFor(0);
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.6)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final activeTrackPaint = Paint()
      ..color = accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < points.length; index++) {
      final x = points[index].dx;
      final thumbY = points[index].dy;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), trackPaint);
      if ((thumbY - centerY).abs() > 0.5) {
        canvas.drawLine(
          Offset(x, centerY),
          Offset(x, thumbY),
          activeTrackPaint,
        );
      }
      if (index == activeBand) {
        canvas.drawCircle(
          Offset(x, thumbY),
          thumbRadius * 2,
          Paint()..color = accent.withValues(alpha: 0.22),
        );
      }
      canvas.drawCircle(
        Offset(x, thumbY),
        index == activeBand ? thumbRadius + 1 : thumbRadius,
        Paint()..color = thumbColor,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerGraphPainter oldDelegate) {
    if (oldDelegate.activeBand != activeBand ||
        oldDelegate.accent != accent ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum ||
        oldDelegate.gains.length != gains.length) {
      return true;
    }
    for (var index = 0; index < gains.length; index++) {
      if (oldDelegate.gains[index] != gains[index]) return true;
    }
    return false;
  }
}

class _EqualizerPresetDropdown extends StatelessWidget {
  const _EqualizerPresetDropdown({
    required this.equalizer,
    required this.presets,
    required this.onConfirmDelete,
    required this.onSavePreset,
  });

  final EqualizerService equalizer;
  final List<String> presets;
  final ValueChanged<String> onConfirmDelete;
  final VoidCallback onSavePreset;

  @override
  Widget build(BuildContext context) {
    final selectedPreset = equalizer.selectedPresetName;
    final isUserPreset = equalizer.userPresetNames.contains(selectedPreset);
    final isCustom =
        equalizer.selectedPresetName == EqualizerService.customPresetName;
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            popupMenuTheme: PopupMenuThemeData(
              color: context.colors.popover,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: context.colors.border),
              ),
              elevation: 8,
            ),
          ),
          child: PopupMenuButton<String>(
            enabled: equalizer.isEnabled,
            tooltip: 'Select preset',
            offset: const Offset(0, 42),
            onSelected: (preset) => unawaited(equalizer.applyPreset(preset)),
            itemBuilder: (context) {
              return [
                if (equalizer.builtInPresetNames.isNotEmpty) ...[
                  const PopupMenuItem<String>(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'Built-in',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final preset in equalizer.builtInPresetNames)
                    PopupMenuItem<String>(
                      value: preset,
                      height: 38,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              preset,
                              style: TextStyle(
                                fontWeight: preset == selectedPreset
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (preset == selectedPreset)
                            Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: scheme.secondary,
                            ),
                        ],
                      ),
                    ),
                ],
                if (equalizer.userPresetNames.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'My presets',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final preset in equalizer.userPresetNames)
                    PopupMenuItem<String>(
                      value: preset,
                      height: 38,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              preset,
                              style: TextStyle(
                                fontWeight: preset == selectedPreset
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 17,
                            ),
                            tooltip: 'Delete preset',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              onConfirmDelete(preset);
                            },
                          ),
                          if (preset == selectedPreset)
                            Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: scheme.secondary,
                            ),
                        ],
                      ),
                    ),
                ],
                if (isCustom) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: EqualizerService.customPresetName,
                    height: 38,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            EqualizerService.customPresetName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: scheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ];
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: context.colors.surfaceHover,
                borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    selectedPreset,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isUserPreset)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: 'Delete preset',
            color: context.colors.textSecondary,
            onPressed: () => onConfirmDelete(selectedPreset),
          ),
        if (isCustom)
          OutlinedButton.icon(
            onPressed: onSavePreset,
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save as preset'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}
