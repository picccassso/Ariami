import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

/// A newer GitHub release than the running app version.
class AvailableUpdate {
  const AvailableUpdate({
    required this.latestVersion,
    required this.releaseUrl,
  });

  /// Version of the latest release, without the leading `v` (e.g. `4.5.0`).
  final String latestVersion;

  /// Web page of the release, where downloads live.
  final String releaseUrl;
}

/// Checks GitHub for a newer Ariami release. Downloads stay manual; this
/// only tells the user a new version exists.
class UpdateCheckService {
  static const String _latestReleaseApiUrl =
      'https://api.github.com/repos/picccassso/Ariami/releases/latest';
  static const String releasesPageUrl =
      'https://github.com/picccassso/Ariami/releases';

  /// Returns the available update, or null when up to date or when the
  /// check fails (offline, rate-limited, unexpected payload).
  static Future<AvailableUpdate?> checkForUpdate({
    String currentVersion = kAriamiVersion,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.getUrl(Uri.parse(_latestReleaseApiUrl));
      request.headers.set(HttpHeaders.acceptHeader,
          'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Ariami-Desktop');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final tagName = json['tag_name'];
      if (tagName is! String || tagName.isEmpty) {
        return null;
      }
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!isNewerVersion(latestVersion, than: currentVersion)) {
        return null;
      }
      // Only trust release URLs that point at the Ariami repo, since the
      // URL gets handed to the OS to open in a browser.
      final htmlUrl = json['html_url'];
      final releaseUrl = htmlUrl is String &&
              htmlUrl.startsWith('https://github.com/picccassso/Ariami/')
          ? htmlUrl
          : releasesPageUrl;
      return AvailableUpdate(
        latestVersion: latestVersion,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// True when [candidate] is a strictly newer dotted version than [than].
  /// Unparseable segments are treated as 0, so malformed tags never win.
  static bool isNewerVersion(String candidate, {required String than}) {
    final candidateParts = _versionParts(candidate);
    final currentParts = _versionParts(than);
    final length = candidateParts.length > currentParts.length
        ? candidateParts.length
        : currentParts.length;
    for (var i = 0; i < length; i++) {
      final a = i < candidateParts.length ? candidateParts[i] : 0;
      final b = i < currentParts.length ? currentParts[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  static List<int> _versionParts(String version) {
    // Ignore build metadata / pre-release suffixes like `+8` or `-beta`.
    final core = version.split(RegExp(r'[+-]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }

  /// Opens [url] in the default browser. Only ever called with the GitHub
  /// release page URLs above.
  static Future<void> openReleasePage(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }
}
