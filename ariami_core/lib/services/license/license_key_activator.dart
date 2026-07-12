import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Endpoint of the license activation service. Overridable at build time:
/// `--dart-define=ARIAMI_LICENSE_WORKER=https://...`
const String licenseActivationBaseUrl = String.fromEnvironment(
  'ARIAMI_LICENSE_WORKER',
  defaultValue: 'https://ariami-license.apetrisorbeje.workers.dev',
);

/// Exchanges a license key for an opaque, signed license file.
///
/// This is deliberately a dumb relay client: it never parses, verifies, or
/// stores license files — the device the license is for verifies the file
/// itself. That keeps it safe to use from any app, including those that
/// carry no verification code at all (they just forward the blob to the
/// household server). Web-safe: only `package:http`, no `dart:io`.
class LicenseKeyActivator {
  LicenseKeyActivator({
    this.baseUrl = licenseActivationBaseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final String baseUrl;
  final http.Client? _httpClient;

  /// Activates [licenseKey] for [product] (an entitlement name such as
  /// `'tv'`). The activation service confirms the key actually includes
  /// that product before issuing a license file, so callers can trust a
  /// success result without inspecting the file.
  Future<LicenseKeyActivationResult> activate({
    required String licenseKey,
    required String product,
    required String deviceName,
  }) async {
    final trimmedKey = licenseKey.trim();
    if (trimmedKey.isEmpty) {
      return const LicenseKeyActivationFailure(
        LicenseKeyActivationError.emptyKey,
      );
    }

    final http.Response response;
    try {
      final client = _httpClient ?? http.Client();
      try {
        response = await client
            .post(
              Uri.parse('$baseUrl/v1/activate'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'licenseKey': trimmedKey,
                'deviceName': deviceName,
                'product': product,
              }),
            )
            .timeout(const Duration(seconds: 20));
      } finally {
        if (_httpClient == null) client.close();
      }
    } catch (_) {
      return const LicenseKeyActivationFailure(
        LicenseKeyActivationError.unreachable,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return const LicenseKeyActivationFailure(
        LicenseKeyActivationError.serviceError,
      );
    }
    if (response.statusCode != 200) {
      final code = decoded is Map<String, dynamic>
          ? ((decoded['error'] as Map<String, dynamic>?)?['code'] as String?)
          : null;
      return LicenseKeyActivationFailure(_errorForCode(code));
    }

    final licenseFile = decoded is Map<String, dynamic>
        ? decoded['licenseFile'] as String?
        : null;
    if (licenseFile == null || licenseFile.trim().isEmpty) {
      return const LicenseKeyActivationFailure(
        LicenseKeyActivationError.serviceError,
      );
    }
    // Defensive double-check against an activation service that predates
    // the server-side product check: when it reports what the key
    // includes, honour that over a blind success.
    final products = decoded is Map<String, dynamic>
        ? decoded['products'] as List<dynamic>?
        : null;
    if (products != null && !products.contains(product)) {
      return const LicenseKeyActivationFailure(
        LicenseKeyActivationError.wrongProduct,
      );
    }

    return LicenseKeyActivationSuccess(licenseFile: licenseFile);
  }

  static LicenseKeyActivationError _errorForCode(String? code) {
    switch (code) {
      case 'INVALID_KEY':
        return LicenseKeyActivationError.invalidKey;
      case 'ACTIVATION_LIMIT':
        return LicenseKeyActivationError.activationLimit;
      case 'KEY_DISABLED':
        return LicenseKeyActivationError.keyDisabled;
      case 'WRONG_PRODUCT':
        return LicenseKeyActivationError.wrongProduct;
      case 'RATE_LIMITED':
        return LicenseKeyActivationError.rateLimited;
      default:
        return LicenseKeyActivationError.serviceError;
    }
  }
}

sealed class LicenseKeyActivationResult {
  const LicenseKeyActivationResult();
}

class LicenseKeyActivationSuccess extends LicenseKeyActivationResult {
  const LicenseKeyActivationSuccess({required this.licenseFile});

  /// The opaque license file to relay to the household server.
  final String licenseFile;
}

class LicenseKeyActivationFailure extends LicenseKeyActivationResult {
  const LicenseKeyActivationFailure(this.error);

  final LicenseKeyActivationError error;

  /// User-facing copy shared by every app, parameterized on the display
  /// name of the product being activated (e.g. `'Ariami TV'`).
  String message(String productLabel) {
    switch (error) {
      case LicenseKeyActivationError.emptyKey:
        return 'Enter your license key first.';
      case LicenseKeyActivationError.unreachable:
        return 'Couldn\'t reach the activation service. Check your '
            'internet connection and try again.';
      case LicenseKeyActivationError.invalidKey:
        return 'That license key wasn\'t recognized. Check it for typos '
            'and try again.';
      case LicenseKeyActivationError.activationLimit:
        return 'This key has reached its activation limit. Contact support '
            'and we\'ll raise it for you.';
      case LicenseKeyActivationError.keyDisabled:
        return 'This license key is no longer active.';
      case LicenseKeyActivationError.wrongProduct:
        return 'This key doesn\'t include $productLabel. Check which '
            'product you purchased.';
      case LicenseKeyActivationError.rateLimited:
        return 'Too many attempts. Wait a minute and try again.';
      case LicenseKeyActivationError.serviceError:
        return 'The activation service is temporarily unavailable. Try '
            'again shortly.';
    }
  }
}

enum LicenseKeyActivationError {
  emptyKey,
  unreachable,
  invalidKey,
  activationLimit,
  keyDisabled,
  wrongProduct,
  rateLimited,
  serviceError,
}
