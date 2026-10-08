part of '../http_server.dart';

/// One-time, best-effort shrinking of images stored before uploads were
/// normalised on ingest.
///
/// Idempotent by construction: [ImageNormalizer.shrinkIfOversized] skips
/// anything already within bounds from its header alone, so once an image is
/// shrunk later startups only read dimensions. Without FFmpeg this is a no-op.
extension AriamiHttpServerImageNormalizationMethods on AriamiHttpServer {
  Future<void> _normalizeStoredImages() async {
    // Per-store so one failing (or closed mid-run by a reinitialize) store
    // never stops the others; nothing here may affect startup.
    Future<void> run(String name, Future<int> Function() shrink) async {
      try {
        final count = await shrink();
        if (count > 0) print('[HttpServer] Shrunk $count stored $name');
      } catch (e) {
        print('[HttpServer] Stored $name normalisation skipped: $e');
      }
    }

    await run(
      'playlist images',
      () async =>
          await _playlistImageStore?.shrinkImages(
            (bytes, contentType) => _imageNormalizer.shrinkIfOversized(
              bytes,
              contentType,
              maxDimension: ImageNormalizer.coverMaxDimension,
            ),
          ) ??
          0,
    );
    await run(
      'artist images',
      () async =>
          await _artistImageStore?.shrinkImages(
            (bytes, contentType) => _imageNormalizer.shrinkIfOversized(
              bytes,
              contentType,
              maxDimension: ImageNormalizer.coverMaxDimension,
            ),
          ) ??
          0,
    );
    await run('avatars', _shrinkStoredAvatars);
  }

  Future<int> _shrinkStoredAvatars() async {
    final directoryPath = _userAvatarsDirectoryPath;
    if (directoryPath == null || !Directory(directoryPath).existsSync()) {
      return 0;
    }

    final userIds = Directory(directoryPath)
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .where((name) => name.endsWith('.jpg') || name.endsWith('.png'))
        .map((name) => p.basenameWithoutExtension(name))
        .toSet();

    var shrunkCount = 0;
    for (final userId in userIds) {
      final avatar = _avatarRecordForUser(userId);
      if (avatar == null) continue;
      final shrunk = await _imageNormalizer.shrinkIfOversized(
        await avatar.file.readAsBytes(),
        avatar.contentType,
        maxDimension: ImageNormalizer.avatarMaxDimension,
      );
      // An avatar replaced by an upload while FFmpeg ran must not be
      // overwritten with the shrunken old one.
      if (shrunk == null ||
          _avatarRecordForUser(userId)?.updatedAt != avatar.updatedAt) {
        continue;
      }
      // Rewriting bumps the file mtime, which is the avatar's version
      // (avatarUpdatedAt / `?v=`), so client caches refresh.
      await _writeAvatarBytes(
        userId: userId,
        bytes: shrunk,
        contentType: avatar.contentType,
      );
      shrunkCount++;
    }
    return shrunkCount;
  }
}
