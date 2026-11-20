import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/audio_controller.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';

/// A slim, quiet [Slider] that comes alive under the pointer: the track
/// thickens, fills with the accent colour and reveals its thumb.
class HoverSlider extends StatefulWidget {
  const HoverSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.onChanged,
    this.onChangeEnd,
    this.animateValueChanges = false,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Interpolates external updates; pointer dragging stays immediate.
  final bool animateValueChanges;

  @override
  State<HoverSlider> createState() => _HoverSliderState();
}

class _HoverSliderState extends State<HoverSlider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final accent = Theme.of(context).colorScheme.secondary;
    final colors = context.colors;
    final animateValue = !_dragging && !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: enabled && (_hovering || _dragging) ? 1 : 0),
        duration: Motion.fast,
        curve: Motion.standard,
        builder: (context, t, _) => SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: lerpDouble(3.5, 5.5, t),
            activeTrackColor: Color.lerp(colors.textPrimary, accent, t),
            inactiveTrackColor: colors.textPrimary.withValues(alpha: 0.16),
            disabledInactiveTrackColor:
                colors.textPrimary.withValues(alpha: 0.10),
            thumbColor: Colors.white,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: 6.5 * t,
              elevation: 3 * t,
              pressedElevation: 4,
            ),
            // A fixed overlay radius keeps the track's inset constant while
            // the thumb grows, so the bar never shifts sideways on hover.
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            overlayColor: Colors.transparent,
          ),
          child: widget.animateValueChanges
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: widget.value, end: widget.value),
                  duration: animateValue ? Motion.fast : Duration.zero,
                  curve: Motion.standard,
                  builder: (context, value, _) =>
                      _buildSlider(animateValue ? value : widget.value),
                )
              : _buildSlider(widget.value),
        ),
      ),
    );
  }

  Widget _buildSlider(double value) => Slider(
        min: widget.min,
        max: widget.max,
        value: value,
        onChangeStart: (_) => setState(() => _dragging = true),
        onChanged: widget.onChanged,
        onChangeEnd: (v) {
          setState(() => _dragging = false);
          widget.onChangeEnd?.call(v);
        },
      );
}

/// Mute toggle and volume slider with mouse-wheel and trackpad scroll support.
///
/// Only desktops honour a remote volume command, so this hides itself when
/// mirroring a TV or phone.
class VolumeControl extends StatelessWidget {
  const VolumeControl({
    super.key,
    required this.audio,
    this.sliderWidth = 120,
    this.iconSize = 20,
  });

  final AudioController audio;
  final double sliderWidth;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (audio.isRemoteActive && audio.remoteDeviceType != 'desktop') {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 4),
        IconButton(
          tooltip: audio.isMuted ? 'Unmute' : 'Mute',
          iconSize: iconSize,
          visualDensity: VisualDensity.compact,
          color: context.colors.textSecondary,
          icon: Icon(
            audio.isMuted
                ? Icons.volume_off_rounded
                : Icons.volume_down_rounded,
          ),
          onPressed: audio.toggleMute,
        ),
        SizedBox(
          width: sliderWidth,
          // Wheel notches step the volume; trackpads arrive as pan/zoom
          // gestures, not scroll signals, so they adjust it continuously with
          // the fingers.
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                audio.setVolume(
                  audio.volume - event.scrollDelta.dy.sign * 0.05,
                );
              }
            },
            onPointerPanZoomUpdate: (event) => audio.setVolume(
              audio.volume - event.panDelta.dy * 0.005,
            ),
            child: HoverSlider(
              value: audio.volume,
              onChanged: audio.setVolume,
              animateValueChanges: true,
            ),
          ),
        ),
      ],
    );
  }
}
