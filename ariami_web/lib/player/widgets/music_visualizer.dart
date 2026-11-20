import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ariami_core/utils/music_voices.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../services/audio/audio_level_meter.dart';
import '../services/theme_controller.dart';
import '../theme/player_theme.dart';

/// A backdrop that moves with every voice of the music at once: a warped
/// fluid in the cover's own colours (in cover-art mode; otherwise the
/// theme's glows), where kicks send out shockwaves, bass swells and folds
/// it, snares ripple it, hi-hats glitter, vocals weave ribbons of light and
/// wide instruments drift the colours.
///
/// It animates every frame and holds [levels] for as long as it is shown, so
/// show it only while music plays here.
class MusicVisualizer extends StatefulWidget {
  const MusicVisualizer({super.key, this.levels});

  final AudioLevelMeter? levels;

  @override
  State<MusicVisualizer> createState() => _MusicVisualizerState();
}

class _MusicVisualizerState extends State<MusicVisualizer>
    with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram> _loadProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'shaders/music_visualizer.frag',
      );
    } catch (_) {
      return ui.FragmentProgram.fromAsset(
        'packages/ariami_web/shaders/music_visualizer.frag',
      );
    }
  }

  static final _program = _loadProgram();
  // The fluid is soft, so it is shaded at a fraction of the screen's
  // resolution and scaled up. A GPU that can't keep up (frames keep missing
  // their 60 Hz slot) is given fewer pixels, for the rest of the session, so
  // it settles once rather than every time the player opens.
  static var _resolution = 0.6;
  static const _minResolution = 0.25;
  static const _lateFrame = Duration(milliseconds: 25);

  late final Ticker _ticker;
  final _scene = _Scene();
  final _frames = ValueNotifier(0);
  ui.FragmentShader? _shader;
  Duration _last = Duration.zero;
  bool _calm = false;
  int _judged = 0, _late = 0;
  List<Color> _glowTargets = const [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    widget.levels?.acquire();
    _program.then(
      (program) {
        if (mounted) setState(() => _shader = program.fragmentShader());
      },
      // No shader on this renderer: the backdrop stays its base colour.
      onError: (_) {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(MusicVisualizer old) {
    super.didUpdateWidget(old);
    if (old.levels == widget.levels) return;
    old.levels?.release();
    widget.levels?.acquire();
  }

  void _tick(Duration elapsed) {
    final interval = elapsed - _last;
    final dt = math.min(0.05, interval.inMicroseconds / 1e6);
    _last = elapsed;
    _judgePace(interval);
    _scene.advance(
      widget.levels?.sample() ?? MusicVoices.silent,
      dt,
      speed: _calm ? 0.4 : 1,
    );
    _scene.fadeGlows(_glowTargets, dt);
    _frames.value++;
  }

  // Over each 60 frames, if more than a tenth arrived late, drops the
  // resolution a step.
  void _judgePace(Duration interval) {
    if (interval > _lateFrame) _late++;
    if (++_judged < 60) return;
    if (_late > 6 && _resolution > _minResolution) {
      setState(
        () => _resolution = math.max(_minResolution, _resolution * 0.8),
      );
    }
    _judged = _late = 0;
  }

  @override
  void dispose() {
    widget.levels?.release();
    _ticker.dispose();
    _frames.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final artwork = context.select<ThemeController?, List<Color>>(
      (theme) => theme?.artworkColors ?? const [],
    );
    _glowTargets = artwork.length == 3
        ? artwork
        : [colors.glowA, colors.glowB, colors.glowC];
    return SizedBox.expand(
      child: CustomPaint(
        painter: _VisualizerPainter(
          shader: _shader,
          scene: _scene,
          colors: colors,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          resolution: _resolution,
          // Reduced motion keeps the movement but drops the flashes and the
          // shake.
          flash: _calm ? 0 : 0.6,
          shake: _calm ? 0 : 1,
          repaint: _frames,
        ),
      ),
    );
  }
}

/// Where the visualizer's motion has got to, advanced once per frame.
class _Scene {
  static const _kickGain = 1.95;
  // How fast everything drifts, at 120 BPM.
  static const _speed = 0.65;
  // Levels arrive in steps, on Linux only about 43 times a second (libmpv
  // meters every 1024 samples), so they are eased toward every frame rather
  // than snapped to, or the fluid would hold still between readings.
  static const _levelEase = 0.025;

  final _random = math.Random();
  double time = 0, flow = 0, hue = 0, snarePhase = 0;
  // Where the fluid is jumping to, and has got to.
  double _jumpToX = 0, _jumpToY = 0, jumpX = 0, jumpY = 0;
  double kick = 0, snare = 0, hats = 0;
  double bass = 0, vocal = 0, instruments = 0;
  double drumPan = 0, instrumentPan = 0;
  // A heavy bass hit's shake: how hard (0–1, fading fast) and the knock
  // and punch it gives the picture now.
  double shake = 0, shakeX = 0, shakeY = 0;
  double _shakeTime = 0;

  // The glows painted now, fading toward each new cover's colours.
  List<Color> glows = const [];

  // How the music's tempo scales the drift; 1 at 120 BPM.
  double _pace = 0.6;

  // The last four shockwaves (kicks and snares), launched in turn.
  final kickAge = List.filled(4, 9.0);
  final kickAmp = List.filled(4, 0.0);
  final kickX = List.filled(4, 0.0);
  final kickY = List.filled(4, 0.0);
  int _slot = 0;
  double _sinceKick = 9, _sinceSnare = 9;
  // A bass surge jumps the fluid once, then must ease off before the next.
  bool _bassArmed = true;

  void advance(MusicVoices v, double dt, {required double speed}) {
    // Faster songs move faster and slower ones slower, easing between them
    // over a couple of seconds; with no steady beat it drifts calmly.
    final pace = v.tempo == 0 ? 0.6 : (v.tempo / 120).clamp(0.6, 1.5);
    _pace += (pace - _pace) * (1 - math.exp(-dt / 1.5));
    speed *= _speed * _pace;

    // Each kick launches a ring from anywhere on screen; a kick still rising
    // in the next few frames feeds its ring rather than launching another.
    // Snares launch rings on whichever side the kit is panned.
    final hit = math.min(1.5, v.kick * _kickGain);
    kick = math.max(kick * math.exp(-dt / 0.16), hit);
    final ease = 1 - math.exp(-dt / _levelEase);
    drumPan += (v.drumPan - drumPan) * ease;
    instrumentPan += (v.instrumentPan - instrumentPan) * ease;
    _sinceKick += dt;
    _sinceSnare += dt;
    for (var i = 0; i < 4; i++) {
      kickAge[i] += dt;
    }
    if (hit > 0.12 && _sinceKick > 0.15) {
      _launch(hit, 0.1 + 0.8 * _random.nextDouble());
      _sinceKick = 0;
    } else if (_sinceKick < 0.1) {
      kickAmp[_slot] = math.max(kickAmp[_slot], hit);
    }
    if (v.snare > 0.35 && _sinceSnare > 0.15) {
      final side = 0.5 + 0.4 * drumPan + 0.08 * (_random.nextDouble() - 0.5);
      _launch(0.8 * v.snare, side);
      _sinceSnare = 0;
    }

    snare = math.max(snare * math.exp(-dt / 0.12), v.snare);
    hats = math.max(hats * math.exp(-dt / 0.08), v.hats);
    bass += (v.bass - bass) * ease;
    vocal += (v.vocal - vocal) * ease;
    instruments += (v.instruments - instruments) * ease;

    // Only a strong kick-band hit landing while the bass surges above its
    // usual level shakes: drops and big 808s, not every kick of a groove.
    final surge = ((bass - 0.55) / 0.35).clamp(0.0, 1.0);
    final heavy = v.kick * surge * surge * (3 - 2 * surge);
    if (heavy > 0.5) shake = math.max(shake, (heavy - 0.5) * 2);
    shake *= math.exp(-dt / 0.25);
    _shakeTime += dt;
    shakeX = 0.012 * shake * math.sin(_shakeTime * 57);
    shakeY = 0.012 * shake * math.cos(_shakeTime * 43);

    // Each bass surge throws the fluid somewhere new, leaning toward the
    // side the drums are panned. The fluid is sampled at an offset, so
    // moving the offset left moves the picture right.
    if (_bassArmed && bass > 0.75) {
      _bassArmed = false;
      _jumpToX += (_random.nextDouble() - 0.5) * 1.4 - 0.7 * drumPan;
      _jumpToY += (_random.nextDouble() - 0.5) * 1.4;
    } else if (bass < 0.55) {
      _bassArmed = true;
    }

    // Glide most of the way there in about a second.
    final lunge = 1 - math.exp(-dt * speed / 0.3);
    jumpX += (_jumpToX - jumpX) * lunge;
    jumpY += (_jumpToY - jumpY) * lunge;

    time += dt * speed;
    flow += dt * (0.08 + 0.5 * bass) * speed;
    hue += dt * (0.004 + 0.05 * instruments) * speed;
    snarePhase += dt * (0.5 + 6 * snare) * speed;
  }

  void fadeGlows(List<Color> targets, double dt) {
    if (glows.length != targets.length) {
      glows = targets;
      return;
    }
    final t = 1 - math.exp(-dt / 0.6);
    glows = [
      for (var i = 0; i < targets.length; i++)
        Color.lerp(glows[i], targets[i], t)!,
    ];
  }

  // A shockwave from [x] across the screen (0–1) at a random height.
  void _launch(double amp, double x) {
    _slot = (_slot + 1) % 4;
    kickAge[_slot] = 0;
    kickAmp[_slot] = amp;
    kickX[_slot] = x;
    kickY[_slot] = 0.1 + 0.8 * _random.nextDouble();
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({
    required this.shader,
    required this.scene,
    required this.colors,
    required this.pixelRatio,
    required this.resolution,
    required this.flash,
    required this.shake,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.FragmentShader? shader;
  final _Scene scene;
  final PlayerColors colors;
  final double pixelRatio;
  final double resolution;
  final double flash;
  final double shake;

  static const _weird = 0.93;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shader = this.shader;
    if (shader == null || size.isEmpty) {
      canvas.drawRect(bounds, Paint()..color = colors.base);
    } else {
      final width = (size.width * pixelRatio * resolution).ceil();
      final height = (size.height * pixelRatio * resolution).ceil();
      _setUniforms(shader, width.toDouble(), height.toDouble());
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..shader = shader,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.medium,
      );
      image.dispose();
    }

    // Settle the very bottom toward the base, so the player dock sits on
    // calm ground.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.base.withValues(alpha: 0),
            colors.base.withValues(alpha: 0.55),
          ],
          stops: const [0.7, 1],
        ).createShader(bounds),
    );
  }

  // In the order shaders/music_visualizer.frag declares them.
  void _setUniforms(ui.FragmentShader shader, double width, double height) {
    var i = 0;
    void set(double value) => shader.setFloat(i++, value);
    void color(Color c) => [c.r, c.g, c.b].forEach(set);
    final s = scene;
    [width, height, s.time, s.flow, s.hue, s.snarePhase].forEach(set);
    [s.jumpX, s.jumpY].forEach(set);
    [s.shakeX * shake, s.shakeY * shake, 0.02 * s.shake * shake].forEach(set);
    final glows = s.glows.length == 3
        ? s.glows
        : [colors.glowA, colors.glowB, colors.glowC];
    [colors.base, ...glows].forEach(color);
    [s.bass, s.vocal, s.instruments, s.hats, s.snare, s.kick].forEach(set);
    [_weird, flash, s.drumPan, s.instrumentPan].forEach(set);
    [...s.kickAge, ...s.kickAmp, ...s.kickX, ...s.kickY].forEach(set);
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.shader != shader ||
      old.colors != colors ||
      old.pixelRatio != pixelRatio ||
      old.resolution != resolution ||
      old.flash != flash ||
      old.shake != shake;
}
