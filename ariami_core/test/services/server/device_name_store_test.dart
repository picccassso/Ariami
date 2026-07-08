import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/device_name_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String filePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('device_name_store_test');
    filePath = '${tempDir.path}/device_names.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('names persist across store instances', () async {
    final store = DeviceNameStore();
    await store.initialize(filePath);
    expect(store.nameFor('tv-1'), isNull);

    await store.setName('tv-1', 'Living Room TV');
    await store.setName('phone-1', 'Alex Phone');

    final reloaded = DeviceNameStore();
    await reloaded.initialize(filePath);
    expect(reloaded.nameFor('tv-1'), 'Living Room TV');
    expect(reloaded.nameFor('phone-1'), 'Alex Phone');
    expect(reloaded.nameFor('unknown'), isNull);
  });

  test('renaming a device replaces its stored name', () async {
    final store = DeviceNameStore();
    await store.initialize(filePath);
    await store.setName('tv-1', 'Living Room TV');
    await store.setName('tv-1', 'Bedroom TV');

    final reloaded = DeviceNameStore();
    await reloaded.initialize(filePath);
    expect(reloaded.nameFor('tv-1'), 'Bedroom TV');
  });

  test('a corrupted file starts fresh instead of failing', () async {
    await File(filePath).writeAsString('{not json');

    final store = DeviceNameStore();
    await store.initialize(filePath);
    expect(store.nameFor('tv-1'), isNull);

    // The store stays writable after recovering.
    await store.setName('tv-1', 'Living Room TV');
    final onDisk =
        jsonDecode(await File(filePath).readAsString()) as Map<String, dynamic>;
    expect((onDisk['names'] as Map)['tv-1'], 'Living Room TV');
  });
}
