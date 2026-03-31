/// HTTP response wrapper for dashboard admin API calls.
class DashboardHttpResponse {
  const DashboardHttpResponse({
    required this.statusCode,
    required this.body,
    this.jsonBody,
  });

  final int statusCode;
  final String body;
  final Map<String, dynamic>? jsonBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  String? get errorMessage {
    final error = jsonBody?['error'];
    if (error is Map<String, dynamic>) {
      return error['message'] as String?;
    }
    return null;
  }
}
