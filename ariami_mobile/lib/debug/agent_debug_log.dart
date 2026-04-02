import 'dart:convert';
import 'package:http/http.dart' as http;

/// Debug-mode NDJSON logging (session bb20ad). Do not log secrets/PII.
// #region agent log
void agentDebugLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, dynamic>? data,
  String runId = 'pre-fix',
}) {
  final payload = <String, Object?>{
    'sessionId': 'bb20ad',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'location': location,
    'message': message,
    'hypothesisId': hypothesisId,
    'runId': runId,
    if (data != null) 'data': data,
  };
  http
      .post(
        Uri.parse(
            'http://127.0.0.1:7910/ingest/88fd5e93-4e18-4a32-bf9d-55e90ee6af63'),
        headers: {
          'Content-Type': 'application/json',
          'X-Debug-Session-Id': 'bb20ad',
        },
        body: jsonEncode(payload),
      )
      .catchError((_) => http.Response('', 500));
}
// #endregion
