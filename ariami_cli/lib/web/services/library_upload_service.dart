import 'dart:async';
import 'dart:js_interop';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'web_api_client.dart';

/// A file to upload and its path within what was dropped, so a dropped
/// `Artist/Album` folder keeps its structure on the server.
class LibraryUploadFile {
  const LibraryUploadFile(this.relativePath, this.file);

  final String relativePath;
  final web.File file;

  int get size => file.size;
}

/// The music folder's subfolders an upload can target, and the file types
/// the server accepts.
class LibraryUploadTargets {
  const LibraryUploadTargets(this.folders, this.allowedExtensions);

  final List<String> folders;
  final Set<String> allowedExtensions;

  bool accepts(LibraryUploadFile file) =>
      allowedExtensions.contains(p.extension(file.relativePath).toLowerCase());
}

enum LibraryUploadResult { uploaded, alreadyExists, failed }

/// Uploads files from the browser into the server's music folder. The
/// server's folder watcher adds them to the library once written.
class LibraryUploadService {
  LibraryUploadService(this._apiClient);

  final WebApiClient _apiClient;

  Future<LibraryUploadTargets> fetchTargets() async {
    final response = await _apiClient.get('/api/admin/library/folders');
    if (!response.isSuccess) throw WebApiException(response);
    final json = response.jsonBody ?? const <String, dynamic>{};
    return LibraryUploadTargets(
      List<String>.from(json['folders'] as List? ?? const []),
      Set<String>.from(json['allowedExtensions'] as List? ?? const []),
    );
  }

  /// Sends [file] as the raw request body, so the browser streams it from
  /// disk rather than loading it into memory. [onProgress] gets bytes sent.
  Future<LibraryUploadResult> upload(
    LibraryUploadFile file, {
    required String folder,
    void Function(int sentBytes)? onProgress,
  }) async {
    final token = await _apiClient.tokenProvider?.call();
    final uri = Uri(
      path: '/api/admin/library/upload',
      queryParameters: {'folder': folder, 'path': file.relativePath},
    );
    final status = Completer<int>();
    final request = web.XMLHttpRequest()..open('POST', uri.toString());
    if (token != null && token.isNotEmpty) {
      request.setRequestHeader('Authorization', 'Bearer $token');
    }
    request.upload.onprogress =
        ((web.ProgressEvent event) => onProgress?.call(event.loaded)).toJS;
    request.onload = ((web.Event _) => status.complete(request.status)).toJS;
    request.onerror = ((web.Event _) => status.complete(0)).toJS;
    request.send(file.file);

    return switch (await status.future) {
      200 => LibraryUploadResult.uploaded,
      409 => LibraryUploadResult.alreadyExists,
      _ => LibraryUploadResult.failed,
    };
  }
}

/// Calls [onFiles] with whatever is dropped onto the page, walking dropped
/// folders, until the returned function is called. While listening the
/// browser no longer opens dropped files in place of the dashboard.
void Function() listenForDroppedFiles(
  void Function(List<LibraryUploadFile> files) onFiles,
) {
  final onDragOver = ((web.Event event) => event.preventDefault()).toJS;
  final onDrop = ((web.DragEvent event) {
    event.preventDefault();
    final items = event.dataTransfer?.items;
    if (items == null) return;
    // Entries must be read during the drop event; their files can follow.
    // Items with no entry (no folder support) fall back to the plain file.
    final reads = <Future<List<LibraryUploadFile>>>[];
    for (var i = 0; i < items.length; i++) {
      final entry = items[i].webkitGetAsEntry();
      final file = items[i].getAsFile();
      if (entry != null) {
        reads.add(_readEntry(entry, ''));
      } else if (file != null) {
        reads.add(Future.value([LibraryUploadFile(file.name, file)]));
      }
    }
    Future.wait(reads)
        .then((files) => onFiles(files.expand((f) => f).toList()));
  }).toJS;

  web.document.addEventListener('dragover', onDragOver);
  web.document.addEventListener('drop', onDrop);
  return () {
    web.document.removeEventListener('dragover', onDragOver);
    web.document.removeEventListener('drop', onDrop);
  };
}

/// Opens the browser's file chooser, or its folder chooser when [folder] is
/// set (files then keep their path inside that folder). Completes empty if
/// it is dismissed.
Future<List<LibraryUploadFile>> pickFilesForUpload({bool folder = false}) {
  final picked = Completer<List<LibraryUploadFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..webkitdirectory = folder;
  input.onchange = ((web.Event _) {
    final files = input.files;
    picked.complete([
      for (var i = 0; i < (files?.length ?? 0); i++)
        LibraryUploadFile(
          files!.item(i)!.webkitRelativePath.isEmpty
              ? files.item(i)!.name
              : files.item(i)!.webkitRelativePath,
          files.item(i)!,
        ),
    ]);
  }).toJS;
  input.oncancel = ((web.Event _) => picked.complete(const [])).toJS;
  input.click();
  return picked.future;
}

Future<List<LibraryUploadFile>> _readEntry(
  web.FileSystemEntry entry,
  String parentPath,
) async {
  final path = '$parentPath${entry.name}';
  if (entry.isFile) {
    final file = Completer<web.File?>();
    (entry as web.FileSystemFileEntry).file(
      ((web.File f) => file.complete(f)).toJS,
      ((JSAny _) => file.complete(null)).toJS,
    );
    final read = await file.future;
    return read == null ? const [] : [LibraryUploadFile(path, read)];
  }

  // readEntries returns a directory in batches until it answers empty.
  final reader = (entry as web.FileSystemDirectoryEntry).createReader();
  final children = <web.FileSystemEntry>[];
  while (true) {
    final batch = Completer<List<web.FileSystemEntry>>();
    reader.readEntries(
      ((JSArray<web.FileSystemEntry> entries) => batch.complete(entries.toDart))
          .toJS,
      ((JSAny _) => batch.complete(const [])).toJS,
    );
    final entries = await batch.future;
    if (entries.isEmpty) break;
    children.addAll(entries);
  }
  final nested =
      await Future.wait(children.map((child) => _readEntry(child, '$path/')));
  return nested.expand((files) => files).toList();
}
