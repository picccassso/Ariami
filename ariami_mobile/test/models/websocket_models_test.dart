import 'package:ariami_mobile/models/websocket_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsMessage parsing', () {
    test('parses library_updated message', () {
      final message = WsMessage.fromJson({
        'type': WsMessageType.libraryUpdated,
        'data': {
          'albumCount': 12,
          'songCount': 123,
        },
        'timestamp': '2026-02-07T15:00:00Z',
      });

      final parsed = LibraryUpdatedMessage.fromWsMessage(message);

      expect(parsed.type, WsMessageType.libraryUpdated);
      expect(parsed.albumCount, 12);
      expect(parsed.songCount, 123);
    });

    test('parses sync_token_advanced message', () {
      final message = WsMessage.fromJson({
        'type': WsMessageType.syncTokenAdvanced,
        'data': {
          'latestToken': 9876,
          'reason': 'scan_complete',
        },
        'timestamp': '2026-02-07T15:05:00Z',
      });

      final parsed = SyncTokenAdvancedMessage.fromWsMessage(message);

      expect(parsed.type, WsMessageType.syncTokenAdvanced);
      expect(parsed.latestToken, 9876);
      expect(parsed.reason, 'scan_complete');
    });
  });
}
