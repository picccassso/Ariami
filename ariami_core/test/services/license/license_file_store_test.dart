import 'dart:io';

import 'package:ariami_core/services/license/license_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String storePath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ariami_client_license_');
    storePath = p.join(directory.path, 'client_license.txt');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('starts empty and stores a file verbatim', () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    expect(store.licenseFile, isNull);
    expect(store.licenseFiles, isEmpty);
    const contents = '  OPAQUE.blob.contents\n';
    await store.save(contents);
    expect(store.licenseFile, contents);
    expect(store.licenseFiles, [contents]);
  });

  test('persists across store instances', () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    await store.save('OPAQUE.blob.contents');

    final reopened = LicenseFileStore(filePath: storePath)..initialize();
    expect(reopened.licenseFile, 'OPAQUE.blob.contents');
    expect(reopened.licenseFiles, ['OPAQUE.blob.contents']);
  });

  test('keeps multiple distinct files, newest exposed as licenseFile',
      () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    await store.save('FIRST.blob.sig');
    await store.save('SECOND.blob.sig');
    expect(store.licenseFiles, ['FIRST.blob.sig', 'SECOND.blob.sig']);
    expect(store.licenseFile, 'SECOND.blob.sig');

    final reopened = LicenseFileStore(filePath: storePath)..initialize();
    expect(reopened.licenseFiles, ['FIRST.blob.sig', 'SECOND.blob.sig']);
  });

  test('re-storing an existing file refreshes it to newest without duplicating',
      () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    await store.save('FIRST.blob.sig');
    await store.save('SECOND.blob.sig');
    await store.save('FIRST.blob.sig');
    expect(store.licenseFiles, ['SECOND.blob.sig', 'FIRST.blob.sig']);
    expect(store.licenseFile, 'FIRST.blob.sig');
  });

  test('evicts the oldest file beyond maxLicenseFiles', () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    for (var i = 0; i <= LicenseFileStore.maxLicenseFiles; i++) {
      await store.save('BLOB$i.payload.sig');
    }
    expect(store.licenseFiles.length, LicenseFileStore.maxLicenseFiles);
    expect(store.licenseFiles.first, 'BLOB1.payload.sig');
    expect(store.licenseFile, 'BLOB${LicenseFileStore.maxLicenseFiles}.payload.sig');
  });

  test('loads a legacy single-file store from disk', () async {
    File(storePath).writeAsStringSync('LEGACY.blob.sig');
    final store = LicenseFileStore(filePath: storePath)..initialize();
    expect(store.licenseFile, 'LEGACY.blob.sig');
    expect(store.licenseFiles, ['LEGACY.blob.sig']);

    // The next save migrates it to the JSON layout alongside the new file.
    await store.save('NEW.blob.sig');
    final reopened = LicenseFileStore(filePath: storePath)..initialize();
    expect(reopened.licenseFiles, ['LEGACY.blob.sig', 'NEW.blob.sig']);
  });

  test('clear removes memory and disk state', () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    await store.save('OPAQUE.blob.contents');
    await store.clear();
    expect(store.licenseFile, isNull);
    expect(store.licenseFiles, isEmpty);
    expect(File(storePath).existsSync(), isFalse);

    final reopened = LicenseFileStore(filePath: storePath)..initialize();
    expect(reopened.licenseFile, isNull);
  });

  test('rejects empty and oversized uploads', () async {
    final store = LicenseFileStore(filePath: storePath)..initialize();
    expect(() => store.save('   '), throwsArgumentError);
    expect(
      () => store.save('A' * (LicenseFileStore.maxLicenseFileBytes + 1)),
      throwsArgumentError,
    );
    expect(
      () => store.save('é' * (LicenseFileStore.maxLicenseFileBytes ~/ 2 + 1)),
      throwsArgumentError,
    );
  });

  test('ignores an oversized file found on disk', () async {
    File(storePath).writeAsStringSync(
      'A' * (LicenseFileStore.maxLicenseFileBytes + 1),
    );
    final store = LicenseFileStore(filePath: storePath)..initialize();
    expect(store.licenseFile, isNull);
  });

  test('throws when used before initialize', () {
    final store = LicenseFileStore(filePath: storePath);
    expect(() => store.licenseFile, throwsStateError);
  });
}
