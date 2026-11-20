import 'dart:typed_data';
import 'dart:ui';

import '../player/services/player_host.dart';

class WebStatsShareHandler implements StatsShareHandler {
  @override
  bool get supportsCopy => false;

  @override
  bool get supportsSave => false;

  @override
  bool get supportsShare => false;

  @override
  Future<bool> copyPng(Uint8List bytes) async => false;

  @override
  Future<bool> savePng(Uint8List bytes, String filename) async => false;

  @override
  Future<void> sharePng(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  }) async {}
}

class WebSpotifyExportPicker extends SpotifyExportPicker {
  @override
  Future<List<Map<String, dynamic>>?> pickAndReadRecords() async => null;
}

void updateWebDocumentTitle(PlayerAudioState state) {}

String detectWebDeviceName() => 'Web Browser';

Uri? resolveWebSameOriginUri() => null;
