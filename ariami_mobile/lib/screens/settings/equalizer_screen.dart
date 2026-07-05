import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/audio/equalizer_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final EqualizerService _equalizerService = EqualizerService();
  bool _isLoading = true;

  // Last whole-dB value per band, used to fire haptics only when the
  // slider crosses an integer boundary rather than on every drag tick.
  final Map<int, int> _lastHapticStep = {};

  @override
  void initState() {
    super.initState();
    _initializeEqualizer();
  }

  Future<void> _initializeEqualizer() async {
    await _equalizerService.initialize();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Equalizer'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            LucideIcons.chevronLeft,
            size: 20,
            color: colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: _equalizerService,
        builder: (context, _) {
          final parameters = _equalizerService.parameters;

          if (_isLoading) {
            return Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            );
          }

          if (!_equalizerService.isSupported) {
            return _buildEmptyState();
          }

          // On Android the device band parameters only become available once
          // audio playback has started at least once, so show the rest of the
          // controls with a hint card in place of the sliders until then.
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              getMiniPlayerScrollBottomPadding(context) + 20,
            ),
            children: [
              _buildEnableCard(),
              const SizedBox(height: 12),
              _buildSectionHeader('PRESETS'),
              _buildPresetsCard(),
              const SizedBox(height: 12),
              _buildBandsHeader(parameters != null),
              if (parameters == null)
                _buildBandsPendingCard()
              else
                _buildBandsCard(parameters),
              if (parameters != null &&
                  _equalizerService.selectedPresetName ==
                      EqualizerService.customPresetName) ...[
                const SizedBox(height: 16),
                _buildSavePresetButton(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.equalizer_rounded,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Equalizer is not available on this device',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnableCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _equalizerService.setEnabled(!_equalizerService.isEnabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.tune_rounded,
                  color: colorScheme.onSurface,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Enable Equalizer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Switch(
                value: _equalizerService.isEnabled,
                activeThumbColor: colorScheme.onPrimary,
                activeTrackColor: colorScheme.primary,
                inactiveThumbColor: colorScheme.onSurfaceVariant,
                inactiveTrackColor: colorScheme.surfaceContainerHighest,
                onChanged: _equalizerService.setEnabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetsCard() {
    final presetNames = [
      ..._equalizerService.builtInPresetNames,
      ..._equalizerService.userPresetNames,
      if (_equalizerService.selectedPresetName ==
          EqualizerService.customPresetName)
        EqualizerService.customPresetName,
    ];

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final presetName in presetNames)
              _buildPresetChip(
                presetName,
                isUserPreset:
                    _equalizerService.userPresetNames.contains(presetName),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String presetName, {required bool isUserPreset}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _equalizerService.selectedPresetName == presetName;

    return GestureDetector(
      onLongPress:
          isUserPreset ? () => _showDeletePresetDialog(presetName) : null,
      child: ChoiceChip(
        label: Text(presetName),
        selected: isSelected,
        showCheckmark: false,
        avatar: isUserPreset
            ? Icon(
                Icons.person_rounded,
                size: 14,
                color:
                    isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              )
            : null,
        backgroundColor: Colors.transparent,
        selectedColor: colorScheme.primary,
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          _equalizerService.applyPreset(presetName);
        },
      ),
    );
  }

  Widget _buildBandsHeader(bool showReset) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'BANDS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (showReset)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Reset to flat',
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _equalizerService.resetToFlat();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBandsPendingCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 28,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Band sliders become available once playback starts. '
                'Play a song and they will appear here.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandsCard(EqParameters parameters) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = _equalizerService.isEnabled;
    final gains = _equalizerService.currentBandGains;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: _buildCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            children: [
              // Live frequency-response curve for the current gains.
              SizedBox(
                height: 96,
                width: double.infinity,
                child: CustomPaint(
                  painter: _FrequencyResponsePainter(
                    frequencies: parameters.bandFrequencies,
                    gains: [
                      for (var i = 0; i < parameters.bandCount; i++)
                        i < gains.length ? gains[i] : 0.0,
                    ],
                    minDecibels: parameters.minDecibels,
                    maxDecibels: parameters.maxDecibels,
                    curveColor: colorScheme.primary,
                    gridColor: colorScheme.onSurface.withValues(alpha: 0.18),
                    labelColor: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IgnorePointer(
                ignoring: !enabled,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < parameters.bandCount; i++)
                      Expanded(
                        child: _buildBandColumn(
                          index: i,
                          gain: i < gains.length ? gains[i] : 0.0,
                          minDecibels: parameters.minDecibels,
                          maxDecibels: parameters.maxDecibels,
                          centerFrequency: parameters.bandFrequencies[i],
                          enabled: enabled,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBandColumn({
    required int index,
    required double gain,
    required double minDecibels,
    required double maxDecibels,
    required double centerFrequency,
    required bool enabled,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 18,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatGain(gain),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: gain.abs() < 0.05
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 150,
          width: 36,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.onSurface.withValues(
                  alpha: 0.12,
                ),
                thumbColor: colorScheme.primary,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                min: minDecibels,
                max: maxDecibels,
                value: gain.clamp(minDecibels, maxDecibels),
                onChanged: enabled
                    ? (value) {
                        final step = value.round();
                        if (_lastHapticStep[index] != step) {
                          _lastHapticStep[index] = step;
                          HapticFeedback.selectionClick();
                        }
                        _equalizerService.setBandGain(index, value);
                      }
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatFrequency(centerFrequency),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSavePresetButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: _showSavePresetDialog,
      icon: const Icon(Icons.save_rounded, size: 18),
      label: const Text('Save as preset'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: colorScheme.onSurface,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(15),
      child: child,
    );
  }

  String _formatGain(double gain) {
    if (gain > 0.05) return '+${gain.toStringAsFixed(1)}';
    return gain.toStringAsFixed(1);
  }

  String _formatFrequency(double frequency) {
    if (frequency < 1000) return '${frequency.round()}Hz';

    final khz = frequency / 1000;
    if (khz == khz.roundToDouble()) return '${khz.round()}kHz';
    return '${khz.toStringAsFixed(1)}kHz';
  }

  Future<void> _showDeletePresetDialog(String presetName) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'DELETE PRESET',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Delete "$presetName"? This action cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _equalizerService.deleteUserPreset(presetName);
              if (!mounted) return;
              navigator.pop();
            },
            child: const Text(
              'DELETE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: Color(0xFFFF4B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSavePresetDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> savePreset() async {
              final presetName = controller.text.trim();
              if (presetName.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter a preset name';
                });
                return;
              }

              if (_equalizerService.isReservedPresetName(presetName)) {
                setDialogState(() {
                  errorText = 'That name is reserved';
                });
                return;
              }

              final navigator = Navigator.of(context);
              await _equalizerService.saveCurrentAsPreset(presetName);
              if (!mounted) return;
              navigator.pop();
            }

            return AlertDialog(
              backgroundColor: colorScheme.surface,
              title: Text(
                'SAVE PRESET',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: colorScheme.onSurface,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Preset name',
                  errorText: errorText,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  if (errorText == null) return;
                  setDialogState(() {
                    errorText = null;
                  });
                },
                onSubmitted: (_) => savePreset(),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              actions: [
                TextButton(
                  onPressed: Navigator.of(context).pop,
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: savePreset,
                  child: Text(
                    'SAVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

/// Paints a smooth frequency-response curve for the current band gains on a
/// log-frequency axis, with a dashed 0 dB reference line and dots at each
/// band's center frequency.
class _FrequencyResponsePainter extends CustomPainter {
  final List<double> frequencies;
  final List<double> gains;
  final double minDecibels;
  final double maxDecibels;
  final Color curveColor;
  final Color gridColor;
  final Color labelColor;

  _FrequencyResponsePainter({
    required this.frequencies,
    required this.gains,
    required this.minDecibels,
    required this.maxDecibels,
    required this.curveColor,
    required this.gridColor,
    required this.labelColor,
  });

  static const int _samples = 64;

  double _xForLogHz(double logHz, double logMin, double logMax, Size size) {
    return (logHz - logMin) / (logMax - logMin) * size.width;
  }

  double _yForGain(double gain, Size size) {
    final t = (gain - maxDecibels) / (minDecibels - maxDecibels);
    return t * size.height;
  }

  // Same log-frequency linear interpolation the service applies to presets,
  // so the curve matches what the DSP is actually asked to do.
  double _gainAt(double logHz) {
    if (frequencies.isEmpty) return 0;
    if (logHz <= math.log(frequencies.first)) return gains.first;
    if (logHz >= math.log(frequencies.last)) return gains.last;
    for (var i = 0; i < frequencies.length - 1; i++) {
      final lower = math.log(frequencies[i]);
      final upper = math.log(frequencies[i + 1]);
      if (logHz < lower || logHz > upper) continue;
      if (lower == upper) return gains[i];
      final ratio = (logHz - lower) / (upper - lower);
      return gains[i] + (gains[i + 1] - gains[i]) * ratio;
    }
    return gains.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (frequencies.length < 2 || gains.length != frequencies.length) return;

    // Pad half an octave beyond the outer bands so their dots aren't glued
    // to the edges.
    final logMin = math.log(frequencies.first) - math.ln2 / 2;
    final logMax = math.log(frequencies.last) + math.ln2 / 2;

    // Dashed 0 dB reference line.
    final zeroY = _yForGain(0, size);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashGap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, zeroY),
        Offset(math.min(x + dashWidth, size.width), zeroY),
        gridPaint,
      );
      x += dashWidth + dashGap;
    }

    // Response curve.
    final curvePath = Path();
    for (var i = 0; i <= _samples; i++) {
      final logHz = logMin + (logMax - logMin) * i / _samples;
      final point = Offset(
        _xForLogHz(logHz, logMin, logMax, size),
        _yForGain(_gainAt(logHz), size),
      );
      if (i == 0) {
        curvePath.moveTo(point.dx, point.dy);
      } else {
        curvePath.lineTo(point.dx, point.dy);
      }
    }

    // Soft fill between the curve and the 0 dB line.
    final fillPath = Path.from(curvePath)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = curveColor.withValues(alpha: 0.14),
    );

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at band centers.
    final dotPaint = Paint()..color = curveColor;
    for (var i = 0; i < frequencies.length; i++) {
      final center = Offset(
        _xForLogHz(math.log(frequencies[i]), logMin, logMax, size),
        _yForGain(gains[i], size),
      );
      canvas.drawCircle(center, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_FrequencyResponsePainter oldDelegate) {
    return !listEquals(oldDelegate.gains, gains) ||
        !listEquals(oldDelegate.frequencies, frequencies) ||
        oldDelegate.curveColor != curveColor ||
        oldDelegate.gridColor != gridColor;
  }
}
