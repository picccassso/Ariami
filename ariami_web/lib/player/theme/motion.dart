import 'package:flutter/material.dart';

/// Shared animation vocabulary so motion feels consistent across the player.
///
/// A handful of durations and curves, plus ready-made [AnimatedSwitcher]
/// transition builders, keep every fade/slide on the same rhythm.
class Motion {
  Motion._();

  /// Quick feedback: hover highlights, icon swaps.
  static const Duration fast = Duration(milliseconds: 160);

  /// Standard UI transitions: view changes, panel reveals.
  static const Duration medium = Duration(milliseconds: 280);

  /// Larger, more deliberate moves.
  static const Duration slow = Duration(milliseconds: 420);

  /// A full-screen step through a flow (connect → sign in → player). Longer
  /// than [slow] so the move reads as one continuous gesture rather than a cut.
  static const Duration step = Duration(milliseconds: 520);

  /// Revealing a whole secondary view (lyrics). Unhurried, so the layout
  /// change reads as a calm glide rather than a snap.
  static const Duration reveal = Duration(milliseconds: 720);

  /// Decelerating curve for things entering/settling.
  static const Curve standard = Curves.easeOutCubic;

  /// Symmetric curve for reversible state (open/close).
  static const Curve emphasized = Curves.easeInOutCubic;

  /// Fade + a small upward slide. Good for swapping page-level content.
  static Widget fadeSlideUp(Widget child, Animation<double> animation) {
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: standard));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: offset, child: child),
    );
  }

  /// Fade-through for full-page navigation.
  ///
  /// The old page disappears during the first half before the new page appears
  /// during the second, avoiding translucent overlap on dense track lists.
  static Widget fadeThrough(Widget child, Animation<double> animation) {
    final opacity = animation.drive(
      CurveTween(
        curve: const Interval(0.5, 1, curve: Curves.easeOutCubic),
      ),
    );
    return FadeTransition(
      opacity: opacity,
      child: RepaintBoundary(child: child),
    );
  }

  /// Distance a stepping surface travels, as a fraction of its own width.
  static const double _stepTravel = 0.05;

  /// Steps forward through a flow: the new surface enters from the trailing
  /// edge while the old one leaves by the leading edge.
  static final Widget Function(Widget, Animation<double>) stepForward =
      _sharedAxis(forward: true);

  /// Steps back out of a flow — [stepForward] mirrored.
  static final Widget Function(Widget, Animation<double>) stepBack =
      _sharedAxis(forward: false);

  /// Shared-axis transition builder for [stepForward] / [stepBack].
  ///
  /// [AnimatedSwitcher] drives the outgoing child through this same builder in
  /// reverse, so the two are told apart by status: both tween towards rest,
  /// the entering surface from the side it arrives on and the leaving one from
  /// the side it departs to. That opposition is what makes the pair read as a
  /// single move along an axis instead of two unrelated fades.
  ///
  /// Unlike [fadeThrough] the fades deliberately overlap. Sequencing them
  /// leaves a beat where neither surface is on screen, which on two
  /// full-screen forms reads as a blank flash rather than a transition.
  static Widget Function(Widget, Animation<double>) _sharedAxis({
    required bool forward,
  }) {
    return (child, animation) {
      final leaving = animation.status == AnimationStatus.reverse ||
          animation.status == AnimationStatus.dismissed;
      final sign = (forward == leaving) ? -1.0 : 1.0;
      // The leaving surface clears out earlier than the entering one arrives,
      // so they cross over rather than stacking at full opacity.
      final opacity = animation.drive(CurveTween(
        curve: leaving
            ? const Interval(0.45, 1, curve: Curves.easeIn)
            : const Interval(0.25, 1, curve: Curves.easeOut),
      ));
      return FadeTransition(
        opacity: opacity,
        child: SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: Offset(_stepTravel * sign, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: standard)),
          ),
          child: RepaintBoundary(child: child),
        ),
      );
    };
  }

  /// Cross-fade with a gentle scale. Good for artwork / now-playing swaps.
  static Widget fadeScale(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: standard);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }

  /// Horizontal reveal used for the collapsible side panel.
  static Widget revealHorizontal(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: emphasized);
    return FadeTransition(
      opacity: curved,
      child: SizeTransition(
        axis: Axis.horizontal,
        alignment: Alignment.centerLeft,
        sizeFactor: curved,
        child: child,
      ),
    );
  }
}
