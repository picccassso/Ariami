import 'package:ariami_mobile/services/library/library_pin_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('pins are isolated per user key', () async {
    await LibraryPinStorage.saveForUser('user-a', {'album:1', 'playlist:2'});

    final userAPins = await LibraryPinStorage.loadForUser('user-a');
    final userBPins = await LibraryPinStorage.loadForUser('user-b');

    expect(userAPins, {'album:1', 'playlist:2'});
    expect(userBPins, isEmpty);
  });

  test('migrates legacy pins to scoped user key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LibraryPinStorage.legacyKey: '["album:old"]',
    });

    await LibraryPinStorage.migrateLegacyPinsToUser('legacy-user');

    final migrated = await LibraryPinStorage.loadForUser('legacy-user');
    final prefs = await SharedPreferences.getInstance();

    expect(migrated, {'album:old'});
    expect(prefs.getString(LibraryPinStorage.legacyKey), isNull);
  });
}
