/// Maps setup/connect failures to specific, user-actionable messages.
///
/// The QR and manual-entry flows previously collapsed every failure into one
/// generic "couldn't reach the server" string. This helper distinguishes the
/// cases a user can actually act on — unreachable host, wrong port/refused,
/// timeout, a server that isn't Ariami, auth problems, rate limiting — while
/// keeping messages free of tokens, passwords, and raw payloads.
library;

import 'dart:async';

import '../models/api_models.dart';
import '../services/api/api_client.dart';

String describeSetupConnectError(Object error, {String? address}) {
  final where = address == null || address.isEmpty ? 'the server' : address;

  final message = _flatten(error);

  if (error is ApiException) {
    switch (error.code) {
      case ApiErrorCodes.rateLimited:
        return error.message;
      case ApiErrorCodes.authRequired:
      case ApiErrorCodes.sessionExpired:
      case ApiErrorCodes.invalidCredentials:
        return 'The server requires you to sign in. Continue to the login '
            'step and enter your account details.';
    }
  }

  if (message.contains('TimeoutException')) {
    return 'Connecting to $where timed out. The server may be busy or on a '
        'different network — check WiFi/Tailscale and try again.';
  }

  if (message.contains('Connection refused')) {
    return 'Nothing is listening at $where. Check the port and that the '
        'Ariami server is running.';
  }

  if (message.contains('SocketException') ||
      message.contains('Network is unreachable') ||
      message.contains('No route to host') ||
      message.contains('Failed host lookup')) {
    return 'Couldn\'t reach $where. Check the address and that this phone is '
        'on the same network or VPN as the server.';
  }

  // A web server that answered but not with Ariami's JSON API.
  if (message.contains('FormatException') ||
      message.contains('HTTP 404') ||
      message.contains('HTTP 405') ||
      message.contains('type ') && message.contains('is not a subtype')) {
    return 'Something answered at $where, but it doesn\'t look like an '
        'Ariami server. Double-check the address and port.';
  }

  if (error is ApiException) {
    // Trust the server's own message for remaining structured errors.
    return error.message;
  }

  return 'Couldn\'t connect to $where. Check the address and that the server '
      'is running, then try again.';
}

String _flatten(Object error) {
  if (error is TimeoutException) return 'TimeoutException';
  return error.toString();
}
