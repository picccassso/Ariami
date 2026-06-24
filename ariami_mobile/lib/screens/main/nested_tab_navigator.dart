import 'package:flutter/material.dart';
import '../../utils/constants.dart';

/// Wraps a tab's nested [Navigator] so the system back gesture is handled
/// exactly once per gesture.
///
/// Why this isn't just a [PopScope] (or [NavigatorPopHandler]):
///
/// The original code used a single `PopScope(canPop: false)` whose callback
/// re-checked `navigator.canPop()` to decide between popping the nested stack
/// and running [onBackAtRoot]. That re-check is the bug: if anything pops the
/// nested route as part of the same gesture, the callback then sees
/// `canPop() == false` and also fires [onBackAtRoot], collapsing two levels
/// into one swipe (e.g. a settings submenu jumped straight to the library tab).
///
/// [NavigatorPopHandler] solves the nested-pop case correctly but only supports
/// "pop the nested navigator, otherwise bubble up (exit the app)". Layering our
/// own `PopScope` on top to run [onBackAtRoot] doesn't work either: both that
/// PopScope and NavigatorPopHandler's internal one register on the SAME route,
/// so a single back fires BOTH callbacks.
///
/// So this widget uses ONE [PopScope] and decides which branch to take from the
/// [NavigationNotification] the nested [Navigator] emits — the same signal
/// [NavigatorPopHandler] relies on — rather than re-deriving it after a pop may
/// already have happened. `canPop` stays false so the gesture is always routed
/// to our callback (never exiting the app on its own); the callback either pops
/// the nested navigator or runs [onBackAtRoot], never both.
class NestedTabNavigator extends StatefulWidget {
  const NestedTabNavigator({
    super.key,
    required this.navigatorKey,
    required this.onGenerateRoute,
    this.onBackAtRoot,
    this.initialRoute = '/',
  });

  /// Key for the nested [Navigator] so tab taps can pop it to its root.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Route table for the nested [Navigator].
  final RouteFactory onGenerateRoute;

  /// Called when the system back gesture fires while the nested navigator is
  /// already at its root route.
  final VoidCallback? onBackAtRoot;

  /// Initial route for the nested [Navigator].
  final String initialRoute;

  @override
  State<NestedTabNavigator> createState() => _NestedTabNavigatorState();
}

class _NestedTabNavigatorState extends State<NestedTabNavigator> {
  /// Whether the nested navigator subtree currently has a route it can pop.
  /// Kept in sync with the [NavigationNotification] the nested [Navigator]
  /// dispatches, so the back decision never depends on re-reading state after a
  /// pop has already begun.
  bool _nestedCanPop = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Always intercept: at the nested root we still want a custom action
      // (onBackAtRoot) rather than letting the gesture exit the app, and while
      // a route can be popped we drive that pop ourselves below.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_nestedCanPop) {
          widget.navigatorKey.currentState?.maybePop();
        } else {
          widget.onBackAtRoot?.call();
        }
      },
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          // Track the nested navigator's pop-ability for the back decision.
          if (notification.canHandlePop != _nestedCanPop) {
            setState(() => _nestedCanPop = notification.canHandlePop);
          }
          // We always intercept back (to pop the nested stack OR run
          // onBackAtRoot), so ancestors must always believe this subtree can
          // handle a pop. Otherwise, once the nested navigator reaches its root
          // and reports canHandlePop: false, that notification bubbles to the
          // app root, which de-registers the system back handler and lets the
          // OS exit the app on the next gesture. Absorb the false and
          // re-dispatch true, mirroring how the root Navigator absorbs its
          // children (see NavigatorState.build).
          if (!notification.canHandlePop) {
            const NavigationNotification(canHandlePop: true).dispatch(context);
            return true;
          }
          return false;
        },
        child: Theme(
          // Disable predictive back on nested routes so the system back gesture
          // isn't double-handled when a full-screen route sits above this tab.
          data: Theme.of(context).copyWith(
            pageTransitionsTheme: AppTheme.nestedNavigatorPageTransitions,
          ),
          child: Navigator(
            key: widget.navigatorKey,
            initialRoute: widget.initialRoute,
            onGenerateRoute: widget.onGenerateRoute,
          ),
        ),
      ),
    );
  }
}
