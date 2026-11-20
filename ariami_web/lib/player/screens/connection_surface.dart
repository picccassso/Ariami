import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connection_controller.dart';
import '../theme/motion.dart';

/// How long [ConnectionStage.connecting] has to last before its spinner earns
/// the screen. A LAN handshake resolves well inside this.
const Duration _showProgressAfter = Duration(milliseconds: 150);

/// Once the spinner is up it stays at least this long, so a handshake that
/// completes just after it appears can't blink it straight back out.
const Duration _minProgressVisible = Duration(milliseconds: 400);

/// Renders the surface for the current [ConnectionStage] and animates the
/// moves between them as steps along the connection flow.
///
/// Two things happen here that the raw stage sequence can't express on its own:
///
///  * **The progress surface is debounced.** Pairing sets `connecting`, awaits
///    a `/server-info` round trip, then sets `needsAuth`. On a LAN server that
///    round trip is tens of milliseconds — far too short to read a spinner,
///    but long enough to interrupt the transition between the two forms and
///    leave a blank beat where neither is on screen. So `connecting` only
///    becomes visible once it has outlasted [_showProgressAfter], and is then
///    held for [_minProgressVisible]. A fast connect steps straight from the
///    connect form to sign-in as one clean move; a slow one gets a spinner
///    that behaves.
///  * **The move has a direction.** Surfaces are ranked in flow order, so
///    advancing slides forward and backing out slides back.
class ConnectionSurface extends StatefulWidget {
  const ConnectionSurface({
    super.key,
    required this.stage,
    required this.builder,
  });

  /// The live stage. What is drawn may lag it — see [_showProgressAfter].
  final ConnectionStage stage;

  final Widget Function(ConnectionStage stage) builder;

  @override
  State<ConnectionSurface> createState() => _ConnectionSurfaceState();
}

class _ConnectionSurfaceState extends State<ConnectionSurface> {
  late ConnectionStage _shown = widget.stage;
  Timer? _pending;
  DateTime? _progressShownAt;
  bool _forward = true;

  @override
  void didUpdateWidget(ConnectionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stage != oldWidget.stage) _retarget(widget.stage);
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  /// Moves the visible surface towards [stage], honouring the progress-surface
  /// timing. Any move supersedes one still waiting to happen.
  void _retarget(ConnectionStage stage) {
    _pending?.cancel();

    if (stage == ConnectionStage.connecting) {
      // Keep showing whatever is up. If the work finishes first this timer is
      // cancelled and the spinner is simply never seen.
      _pending = Timer(_showProgressAfter, () {
        _progressShownAt = DateTime.now();
        _show(stage);
      });
      return;
    }

    final shownAt = _progressShownAt;
    if (shownAt != null) {
      final remaining =
          _minProgressVisible - DateTime.now().difference(shownAt);
      if (remaining > Duration.zero) {
        _pending = Timer(remaining, () {
          _progressShownAt = null;
          _show(stage);
        });
        return;
      }
      _progressShownAt = null;
    }
    _show(stage);
  }

  void _show(ConnectionStage stage) {
    if (!mounted) return;
    setState(() {
      // Equal ranks (sign-in ↔ register) count as forward: a lateral swap
      // between two steps of the same depth still reads as going on.
      _forward = _rankOf(stage) >= _rankOf(_shown);
      _shown = stage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.step,
      transitionBuilder: _forward ? Motion.stepForward : Motion.stepBack,
      child: KeyedSubtree(
        key: ValueKey(_surfaceOf(_shown)),
        child: widget.builder(_shown),
      ),
    );
  }
}

/// Identity of the screen a stage renders, for the [AnimatedSwitcher] key.
///
/// Stages sharing a surface must share a key so the switcher updates the
/// existing screen instead of animating it against a copy of itself — which
/// also keeps typed input alive on a direct idle → error.
Object _surfaceOf(ConnectionStage stage) {
  switch (stage) {
    case ConnectionStage.idle:
    case ConnectionStage.error:
      return 'connect';
    case ConnectionStage.initializing:
    case ConnectionStage.connecting:
      return 'progress';
    default:
      return stage;
  }
}

/// Depth of a surface in the connection flow, so a move knows which way it is
/// travelling.
int _rankOf(ConnectionStage stage) {
  switch (stage) {
    case ConnectionStage.idle:
    case ConnectionStage.error:
      return 0;
    case ConnectionStage.initializing:
    case ConnectionStage.connecting:
      return 1;
    case ConnectionStage.needsAuth:
    case ConnectionStage.needsRegistration:
      return 2;
    case ConnectionStage.connected:
    case ConnectionStage.offline:
    case ConnectionStage.reconnecting:
      return 3;
  }
}
