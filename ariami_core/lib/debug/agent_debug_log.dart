import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Debug-mode NDJSON logging (session bb20ad). Do not log secrets/PII.
const _kAgentLogPath =
    '/Users/alex/Documents/Ariami/Ariami/.cursor/debug-bb20ad.log';
const _kIngestUrl =
    'http://127.0.0.1:7910/ingest/88fd5e93-4e18-4a32-bf9d-55e90ee6af63';

// #region agent log
void agentDebugLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?>? data,
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
  final line = jsonEncode(payload);
  try {
    File(_kAgentLogPath).writeAsStringSync('$line\n',
        mode: FileMode.append, flush: true);
  } catch (_) {}
  unawaited(_agentPostLog(line));
}

Future<void> _agentPostLog(String line) async {
  try {
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse(_kIngestUrl));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Debug-Session-Id', 'bb20ad');
    req.write(line);
    await req.close();
    client.close();
  } catch (_) {}
}
// #endregion
