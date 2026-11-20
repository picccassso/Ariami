import 'dart:js_interop';
import 'dart:typed_data';

import '../player/services/player_host.dart';

@JS('ariamiStore')
external _AriamiStore? get _store;

extension type _AriamiStore._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> read(String key);
  external JSPromise<JSAny?> write(String key, JSAny? value);
  external JSPromise<JSAny?> readArtwork(String key);
  external JSPromise<JSAny?> writeArtwork(String key, JSUint8Array bytes);
}

Future<String?> _read(String key) async {
  try {
    return (await _store?.read(key).toDart as JSString?)?.toDart;
  } catch (_) {
    return null;
  }
}

Future<void> _write(String key, String value) async {
  try {
    await _store?.write(key, value.toJS).toDart;
  } catch (_) {}
}

/// Keeps the library in IndexedDB so a reload replays only catalog changes
/// instead of downloading the whole catalog again.
class WebLibrarySnapshotStore implements LibrarySnapshotStore {
  @override
  Future<String?> read(String scope) => _read('library:$scope');

  @override
  Future<void> write(String scope, String contents) =>
      _write('library:$scope', contents);

  @override
  Future<String?> readLastScope() => _read('library:last');

  @override
  Future<void> writeLastScope(String scope) => _write('library:last', scope);
}

/// Keeps resized artwork thumbnails in IndexedDB so reloads and repeated
/// searches paint immediately without hitting Tailscale again.
class WebArtworkCacheStore implements ArtworkCacheStore {
  @override
  Future<Uint8List?> read(String identity) async {
    try {
      final raw = await _store?.readArtwork(identity).toDart;
      if (raw == null) return null;
      final bytes = (raw as JSUint8Array).toDart;
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String identity, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      await _store?.writeArtwork(identity, bytes.toJS).toDart;
    } catch (_) {}
  }
}

LibrarySnapshotStore? createWebLibrarySnapshotStore() =>
    WebLibrarySnapshotStore();

ArtworkCacheStore? createWebArtworkCacheStore() => WebArtworkCacheStore();
