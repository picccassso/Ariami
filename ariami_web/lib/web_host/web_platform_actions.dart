import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import '../player/services/player_host.dart';
import '../player/services/spotify_import_controller.dart';

const String _devApiOrigin = String.fromEnvironment('ARIAMI_DEV_API_ORIGIN');

String _lastDocumentTitle = 'Ariami';

void updateWebDocumentTitle(PlayerAudioState state) {
  final track = state.currentTrack;
  final String nextTitle;
  if (state.isPlayingHere && state.isPlaying && track != null) {
    final title = track.title.trim();
    final artist = track.artist.trim();
    if (title.isNotEmpty && artist.isNotEmpty) {
      nextTitle = '$title · $artist — Ariami';
    } else if (title.isNotEmpty) {
      nextTitle = '$title — Ariami';
    } else {
      nextTitle = 'Ariami';
    }
  } else {
    nextTitle = 'Ariami';
  }
  if (nextTitle == _lastDocumentTitle) return;
  _lastDocumentTitle = nextTitle;
  web.document.title = nextTitle;
}

class WebStatsShareHandler implements StatsShareHandler {
  @override
  bool get supportsCopy =>
      web.window.isSecureContext &&
      (web.window.navigator as JSObject).has('clipboard') &&
      globalContext.has('ClipboardItem');

  @override
  bool get supportsSave => true;

  @override
  bool get supportsShare => false;

  @override
  Future<bool> copyPng(Uint8List bytes) async {
    if (!supportsCopy || bytes.isEmpty) return false;
    try {
      final blob = web.Blob(
        <web.BlobPart>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'image/png'),
      );
      final items = JSObject()..setProperty('image/png'.toJS, blob);
      final item = web.ClipboardItem(items);
      await web.window.navigator.clipboard
          .write(<web.ClipboardItem>[item].toJS)
          .toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> savePng(Uint8List bytes, String filename) async {
    if (bytes.isEmpty) return false;
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    Timer(const Duration(seconds: 2), () {
      try {
        web.URL.revokeObjectURL(url);
      } catch (_) {}
    });
    return true;
  }

  @override
  Future<void> sharePng(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  }) async {}
}

class WebSpotifyExportPicker extends SpotifyExportPicker {
  @override
  Future<List<Map<String, dynamic>>?> pickAndReadRecords() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (picked == null || picked.files.isEmpty) return null;

    final audioFiles = picked.files.where((file) {
      return file.name.startsWith('Streaming_History_Audio_') &&
          file.name.endsWith('.json');
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (audioFiles.isEmpty) {
      throw const SpotifyImportException(
        'No Spotify audio-history files were selected. Choose the '
        'Streaming_History_Audio_*.json files from your unzipped export.',
      );
    }

    final records = <Map<String, dynamic>>[];
    for (final file in audioFiles) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw SpotifyImportException('Could not read ${file.name}.');
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw SpotifyImportException('${file.name} is not valid JSON.');
      }
      if (decoded is! List) {
        throw SpotifyImportException(
          '${file.name} does not contain a Spotify history list.',
        );
      }
      records.addAll(
        decoded.whereType<Map>().map(
              (record) => Map<String, dynamic>.from(record),
            ),
      );
    }

    if (records.isEmpty) {
      throw const SpotifyImportException(
        'The selected Spotify history files are empty.',
      );
    }
    return records;
  }
}

String detectWebDeviceName() {
  final ua = web.window.navigator.userAgent;
  final browser = _detectBrowser(ua);
  final os = _detectOs(ua);
  if (browser != null && os != null) return '$browser on $os';
  return browser ?? (os != null ? 'Browser on $os' : 'Web Browser');
}

String? _detectBrowser(String ua) {
  if (ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')) {
    return 'Edge';
  }
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('Firefox/') || ua.contains('FxiOS/')) return 'Firefox';
  if (ua.contains('CriOS/') ||
      ua.contains('Chrome/') ||
      ua.contains('Chromium/')) {
    return 'Chrome';
  }
  if (ua.contains('Safari/')) return 'Safari';
  return null;
}

String? _detectOs(String ua) {
  if (ua.contains('iPhone')) return 'iOS';
  if (ua.contains('iPad')) return 'iPadOS';
  if (ua.contains('Android')) return 'Android';
  if (ua.contains('Windows')) return 'Windows';
  if (ua.contains('Mac OS X') || ua.contains('Macintosh')) return 'macOS';
  if (ua.contains('CrOS')) return 'ChromeOS';
  if (ua.contains('Linux')) return 'Linux';
  return null;
}

Uri? resolveWebSameOriginUri() {
  final trimmed = _devApiOrigin.trim();
  if (trimmed.isNotEmpty) {
    return Uri.parse(trimmed);
  }
  final base = Uri.base;
  if (base.scheme != 'http' && base.scheme != 'https') return null;
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.port,
  );
}
