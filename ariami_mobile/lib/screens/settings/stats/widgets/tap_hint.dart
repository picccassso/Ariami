import 'package:flutter/material.dart';

/// Overlays a little finger that periodically taps the child — the metric
/// dips under the press and a ripple ring expands, demonstrating the real
/// gesture. Only mounted while the PLAYTIME hint is still pending.
class TapHint extends StatefulWidget {
  const TapHint({super.key, required this.child});

  final Widget child;

  @override
  State<TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<TapHint> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// Progress of [t] through the [from]→[to] slice of the loop, curved.
  static double _seg(double t, double from, double to, Curve curve) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Loop: finger slides in (0–.25), presses (.25–.35), ripple +
        // release (.35–.7), fades out (.7–.85), rests (.85–1).
        final approach = _seg(t, 0.0, 0.25, Curves.easeOutCubic);
        final press = t < 0.25
            ? 0.0
            : t < 0.35
                ? _seg(t, 0.25, 0.35, Curves.easeIn)
                : 1.0 - _seg(t, 0.35, 0.5, Curves.easeOut);
        final ripple = _seg(t, 0.33, 0.7, Curves.easeOut);
        final visible = approach * (1.0 - _seg(t, 0.7, 0.85, Curves.easeIn));

        // Where the fake tap lands, relative to the metric's centre.
        const target = Offset(14, -6);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: 1.0 - 0.06 * press, child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (ripple > 0 && ripple < 1)
                      Transform.translate(
                        offset: target,
                        child: Opacity(
                          opacity: (1.0 - ripple) * 0.7,
                          child: Container(
                            width: 8 + 26 * ripple,
                            height: 8 + 26 * ripple,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      // Fingertip sits just under the tap point; slides in
                      // from below-right and dips slightly on the press.
                      offset: target +
                          Offset(
                            6 + 20 * (1 - approach),
                            12 + 16 * (1 - approach) - 2 * press,
                          ),
                      child: Opacity(
                        opacity: visible.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 1.0 - 0.15 * press,
                          child: Icon(
                            Icons.touch_app_rounded,
                            size: 22,
                            color: color,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
