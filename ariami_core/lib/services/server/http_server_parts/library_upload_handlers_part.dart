part of '../http_server.dart';

extension AriamiHttpServerLibraryUploadMethods on AriamiHttpServer {
  /// Admin-only: the music folder's subfolders an upload can target, plus the
  /// file types it accepts.
  Future<Response> _handleAdminLibraryFolders(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final root = _libraryUploadRoot;
    if (root == null || !await Directory(root).exists()) {
      return _musicFolderUnavailableResponse();
    }

    return _jsonOk({
      'folders': await listLibraryFolders(root),
      'allowedExtensions': libraryUploadExtensions.toList(),
    });
  }

  /// Admin-only: streams the request body into the music folder at
  /// `?folder=<dir>&path=<relative file path>`, creating folders as needed.
  ///
  /// The file is written under a `.partial` name the folder watcher ignores
  /// and renamed once complete, so the watcher indexes it only when whole.
  /// An existing file is never overwritten.
  Future<Response> _handleAdminLibraryUpload(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final root = _libraryUploadRoot;
    if (root == null || !await Directory(root).exists()) {
      return _musicFolderUnavailableResponse();
    }

    final query = request.url.queryParameters;
    final target = resolveLibraryUploadTarget(
        root, query['folder'] ?? '', query['path'] ?? '');
    if (target == null) {
      return _jsonError(HttpStatus.badRequest, 'INVALID_UPLOAD_PATH',
          'Uploads must be music, lyrics or cover files inside the library');
    }
    final targetFile = File(target);
    if (await targetFile.exists()) return _uploadFileExistsResponse();

    final partial =
        File('$target.${DateTime.now().microsecondsSinceEpoch}.partial');
    try {
      await partial.parent.create(recursive: true);
      await request.read().pipe(partial.openWrite());
      if (await targetFile.exists()) return _uploadFileExistsResponse();
      await partial.rename(target);
    } on FileSystemException catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'UPLOAD_FAILED',
          e.osError?.message ?? e.message);
    } finally {
      if (await partial.exists()) await partial.delete();
    }

    return _jsonOk({'path': p.split(p.relative(target, from: root)).join('/')});
  }

  /// Hosts do not always call [setMusicFolderPath], so fall back to the
  /// folder the library scans.
  String? get _libraryUploadRoot =>
      _musicFolderPath ?? _libraryManager.musicFolderPath;

  Response _musicFolderUnavailableResponse() => _jsonError(
      HttpStatus.serviceUnavailable,
      'MUSIC_FOLDER_UNAVAILABLE',
      'The music folder is not set up or not reachable');

  Response _uploadFileExistsResponse() => _jsonError(HttpStatus.conflict,
      'FILE_EXISTS', 'A file with that name is already in the library');
}
