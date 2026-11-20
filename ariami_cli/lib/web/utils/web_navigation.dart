import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Opens the bundled Ariami Web Player served at `/play/`.
Future<void> openWebPlayer({bool newTab = true}) async {
  final target = Uri.base.resolve('/play/');
  await launchUrl(
    target,
    webOnlyWindowName: newTab ? '_blank' : '_self',
  );
}
