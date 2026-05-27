import 'package:flutter/material.dart';

/// Shared route observer for [RouteAware] screens (e.g. welcome re-check on pop).
final RouteObserver<ModalRoute<void>> webRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Clears the navigator stack and shows the dashboard as the only route.
void navigateToDashboard(BuildContext context) {
  Navigator.pushNamedAndRemoveUntil(
    context,
    '/dashboard',
    (route) => false,
  );
}
