import 'package:ariami_desktop/services/desktop_transcode_slots_service.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopTranscodeSlotsService', () {
    late DesktopTranscodeSlotsService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DesktopTranscodeSlotsService();
    });

    test('returns platform default when no override is stored', () async {
      final snapshot = await service.getSnapshot();

      expect(snapshot.override, isNull);
      expect(snapshot.effective, snapshot.defaultSlots);
      expect(snapshot.isCustom, isFalse);
    });

    test('persists and clears override', () async {
      final saved = await service.setOverride(6);
      expect(saved.effective, 6);
      expect(saved.override, 6);
      expect(saved.isCustom, isTrue);

      final loaded = await service.getSnapshot();
      expect(loaded.effective, 6);

      final reset = await service.setOverride(null);
      expect(reset.override, isNull);
      expect(reset.effective, reset.defaultSlots);
    });

    test('rejects invalid slot counts', () async {
      expect(
        () => service.setOverride(0),
        throwsArgumentError,
      );
    });
  });
}
