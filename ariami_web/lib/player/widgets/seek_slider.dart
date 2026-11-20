import 'package:ariami_core/utils/format.dart';
import 'package:flutter/material.dart';

import '../services/audio_controller.dart';
import 'hover_slider.dart';
import 'listenable_selector.dart';

/// The playback seek bar. Drags preview locally and seek on release; playback
/// redraws it only once the thumb moves a whole pixel.
class SeekSlider extends StatefulWidget {
  const SeekSlider({super.key, required this.audio});

  final AudioController audio;

  @override
  State<SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<SeekSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    final totalMs = (audio.duration ?? Duration.zero).inMilliseconds.toDouble();
    if (totalMs <= 0) return const HoverSlider(value: 0);
    double value() =>
        _dragValue ??
        audio.position.inMilliseconds.toDouble().clamp(0.0, totalMs);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) => ListenableSelector(
        listenable: audio.progress,
        select: () => (value() / totalMs * constraints.maxWidth * dpr).round(),
        builder: (_) => HoverSlider(
          max: totalMs,
          value: value(),
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            audio.seek(Duration(milliseconds: v.round()));
            setState(() => _dragValue = null);
          },
        ),
      ),
    );
  }
}

/// The elapsed time beside a [SeekSlider], redrawn once a second.
class PositionClock extends StatelessWidget {
  const PositionClock({super.key, required this.audio, this.style});

  final AudioController audio;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ListenableSelector(
        listenable: audio.progress,
        select: () => audio.position.inSeconds,
        builder: (_) => Text(
          formatClockDuration(audio.position),
          textAlign: TextAlign.right,
          style: style,
        ),
      );
}
