import 'web_api_client.dart';
import 'web_auth_service.dart';

/// Web-compatible Tailscale service
///
/// Since web apps cannot execute shell commands, this service communicates
/// with the backend server to check Tailscale status and retrieve the IP address.
class WebTailscaleService {
  WebTailscaleService()
      : _apiClient = WebApiClient(
          tokenProvider: _authService.getSessionToken,
        );

  static final WebAuthService _authService = WebAuthService();
  final WebApiClient _apiClient;

  /// Check if Tailscale is installed and running on the server
  ///
  /// Returns a map with:
  /// - 'isInstalled': bool indicating if Tailscale is available
  /// - 'isRunning': bool indicating if Tailscale is currently running
  /// - 'ip': String? with the Tailscale IP address if available
  Future<Map<String, dynamic>> checkTailscaleStatus() async {
    try {
      final response = await _apiClient.get('/api/tailscale/status');

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
        return {
          'isInstalled': data['isInstalled'] ?? false,
          'isRunning': data['isRunning'] ?? false,
          'ip': data['ip'],
        };
      } else {
        // API error - assume not available
        return {
          'isInstalled': false,
          'isRunning': false,
          'ip': null,
        };
      }
    } catch (e) {
      // Network error or API unavailable
      return {
        'isInstalled': false,
        'isRunning': false,
        'ip': null,
      };
    }
  }

  /// Get the Tailscale IP address from the server
  ///
  /// Returns null if Tailscale is not available
  Future<String?> getTailscaleIp() async {
    final status = await checkTailscaleStatus();
    return status['ip'] as String?;
  }
}
