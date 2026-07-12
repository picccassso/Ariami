import 'package:ariami_core/services/license/license_key_activator.dart';

import '../api/api_client.dart';
import '../api/connection_service.dart';

/// Activates an Ariami TV license key on the TVs' behalf.
///
/// The phone never verifies or keeps the license: the activation service
/// exchanges the key for a signed license file, and this service relays the
/// file (an opaque blob to us) to the connected household server. Every TV
/// picks it up on its next connect and verifies it itself — no typing with
/// a TV remote.
class TvLicenseService {
  static const String _product = 'tv';
  static const String _productLabel = 'Ariami TV';

  TvLicenseService({
    LicenseKeyActivator? activator,
    ApiClient? Function()? apiClientProvider,
    Future<String?> Function()? deviceNameProvider,
  })  : _activator = activator ?? LicenseKeyActivator(),
        _apiClientProvider =
            apiClientProvider ?? (() => ConnectionService().apiClient),
        _deviceNameProvider = deviceNameProvider ??
            (() => ConnectionService().getCurrentDeviceName());

  final LicenseKeyActivator _activator;
  final ApiClient? Function() _apiClientProvider;
  final Future<String?> Function() _deviceNameProvider;

  /// Whether a server is currently attached to relay the license to. Used
  /// by the UI for its "connect first" hint.
  bool get hasServerConnection => _apiClientProvider() != null;

  /// Activates [rawKey] and stores the license file on the connected
  /// server. Returns null on success or a user-facing error message.
  Future<String?> activateKey(String rawKey) async {
    final apiClient = _apiClientProvider();
    if (apiClient == null) {
      return 'Connect to your Ariami server first — the license is stored '
          'there for your TV to find.';
    }

    String? deviceName;
    try {
      deviceName = await _deviceNameProvider();
    } catch (_) {
      deviceName = null;
    }

    final result = await _activator.activate(
      licenseKey: rawKey,
      product: _product,
      deviceName: deviceName == null || deviceName.trim().isEmpty
          ? 'Ariami Mobile'
          : deviceName.trim(),
    );
    if (result is LicenseKeyActivationFailure) {
      return result.message(_productLabel);
    }
    final licenseFile = (result as LicenseKeyActivationSuccess).licenseFile;

    try {
      await apiClient.putLicenseFile(licenseFile);
    } on ApiException catch (e) {
      if (e.code == 'FORBIDDEN_ADMIN') {
        return 'The key was accepted, but only the server owner\'s account '
            'can store the license. Sign in as the owner and try again.';
      }
      return 'The key was accepted, but the license couldn\'t be stored on '
          'your server. Check the connection and try again.';
    }
    return null;
  }
}
