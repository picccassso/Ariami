part of '../http_server.dart';

/// Relay endpoints for opaque, client-verified license files.
///
/// Client apps upload household license files so every device on the
/// server can fetch them. The server stores and returns the blobs
/// verbatim — verification is entirely the clients' concern. Multiple
/// files can be stored (schema 2) so separately-purchased apps that each
/// upload their own file don't overwrite one another; `licenseFile`
/// (the newest) is kept for schema-1 clients.
extension AriamiHttpServerLicenseMethods on AriamiHttpServer {
  static const int _licenseSchemaVersion = 2;

  LicenseFileStore? get _licenseFileStoreIfReady {
    final store = _licenseFileStore;
    return store != null && store.isInitialized ? store : null;
  }

  /// The license-file relay store, for hosts that embed this server and
  /// surface admin UI in-process (desktop dashboard). Null until auth
  /// initialization has run.
  LicenseFileStore? get licenseFileStore => _licenseFileStoreIfReady;

  Response _licenseStoreUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'LICENSE_STORE_UNAVAILABLE',
          'message': 'License storage is not initialized',
        },
      });

  /// Any signed-in device may fetch the stored license files.
  ///
  /// Responds 200 with a null `licenseFile` / empty `licenseFiles` when
  /// nothing is stored — the server's Cascade treats handler 404s as
  /// unmatched routes, so absence must not be signalled with a 404 status.
  Future<Response> _handleLicenseGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _licenseFileStoreIfReady;
    if (store == null) return _licenseStoreUnavailable();

    return _jsonOk({
      'schemaVersion': _licenseSchemaVersion,
      'licenseFile': store.licenseFile,
      'licenseFiles': store.licenseFiles,
    });
  }

  /// Admin-only: store a license file alongside any already stored.
  Future<Response> _handleLicensePut(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _licenseFileStoreIfReady;
    if (store == null) return _licenseStoreUnavailable();

    Object? decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } catch (_) {
      decoded = null;
    }
    final licenseFile =
        decoded is Map<String, dynamic> ? decoded['licenseFile'] : null;
    if (licenseFile is! String ||
        licenseFile.trim().isEmpty ||
        utf8.encode(licenseFile).length >
            LicenseFileStore.maxLicenseFileBytes) {
      return _jsonResponse(HttpStatus.badRequest, {
        'error': {
          'code': 'INVALID_LICENSE_BODY',
          'message': 'Body must be a JSON object with a non-empty '
              '"licenseFile" string of at most '
              '${LicenseFileStore.maxLicenseFileBytes} bytes',
        },
      });
    }
    await store.save(licenseFile);
    return _jsonOk({'stored': true});
  }

  /// Admin-only: remove every stored license file.
  Future<Response> _handleLicenseDelete(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _licenseFileStoreIfReady;
    if (store == null) return _licenseStoreUnavailable();

    await store.clear();
    return _jsonOk({'removed': true});
  }
}
