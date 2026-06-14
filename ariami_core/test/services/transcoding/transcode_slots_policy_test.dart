import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:test/test.dart';

void main() {
  group('TranscodeSlotsPolicy', () {
    test('resolve uses override when provided', () {
      final snapshot = TranscodeSlotsPolicy.resolve(
        override: 6,
        defaultSlots: 4,
      );

      expect(snapshot.effective, 6);
      expect(snapshot.defaultSlots, 4);
      expect(snapshot.override, 6);
      expect(snapshot.isCustom, isTrue);
    });

    test('resolve falls back to default when override is null', () {
      final snapshot = TranscodeSlotsPolicy.resolve(
        defaultSlots: 3,
      );

      expect(snapshot.effective, 3);
      expect(snapshot.defaultSlots, 3);
      expect(snapshot.override, isNull);
      expect(snapshot.isCustom, isFalse);
    });

    test('validateSlots rejects values below minimum', () {
      expect(
        () => TranscodeSlotsPolicy.validateSlots(0),
        throwsArgumentError,
      );
    });

    test('resolveDefault returns Pi 5 default when model matches', () async {
      final defaultSlots = await TranscodeSlotsPolicy.resolveDefault(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isRaspberryPi: true,
        isRaspberryPi5: true,
      );

      expect(defaultSlots, 5);
    });

    test('resolveDefault returns Pi 4 default when model matches', () async {
      final defaultSlots = await TranscodeSlotsPolicy.resolveDefault(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isRaspberryPi: true,
        isRaspberryPi5: false,
        isRaspberryPi4: true,
      );

      expect(defaultSlots, 4);
    });

    test('resolveDefault returns Pi 3 default when model matches', () async {
      final defaultSlots = await TranscodeSlotsPolicy.resolveDefault(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isRaspberryPi: true,
        isRaspberryPi5: false,
        isRaspberryPi4: false,
        isRaspberryPi3: true,
      );

      expect(defaultSlots, 3);
    });

    test('resolveDefault returns desktop default on macOS', () async {
      final defaultSlots = await TranscodeSlotsPolicy.resolveDefault(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
      );

      expect(defaultSlots, 6);
    });

    test('resolveDefault returns desktop default on non-Pi Linux', () async {
      final defaultSlots = await TranscodeSlotsPolicy.resolveDefault(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isRaspberryPi: false,
      );

      expect(defaultSlots, 6);
    });

    test('toJson and fromJson round-trip', () {
      const snapshot = TranscodeSlotsSnapshot(
        effective: 6,
        defaultSlots: 4,
        override: 6,
      );

      final restored = TranscodeSlotsSnapshot.fromJson(snapshot.toJson());
      expect(restored.effective, 6);
      expect(restored.defaultSlots, 4);
      expect(restored.override, 6);
      expect(restored.restartRequired, isTrue);
    });
  });
}
