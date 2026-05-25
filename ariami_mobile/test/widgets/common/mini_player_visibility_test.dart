import 'package:ariami_mobile/widgets/common/mini_player_aware_bottom_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    while (MiniPlayerVisibility.instance.isFullPlayerOnTop) {
      MiniPlayerVisibility.popFullPlayer();
    }
  });

  test('pushFullPlayer marks full player as on top', () {
    expect(MiniPlayerVisibility.instance.isFullPlayerOnTop, isFalse);

    MiniPlayerVisibility.pushFullPlayer();

    expect(MiniPlayerVisibility.instance.isFullPlayerOnTop, isTrue);
  });

  test('popFullPlayer clears full player visibility', () {
    MiniPlayerVisibility.pushFullPlayer();
    expect(MiniPlayerVisibility.instance.isFullPlayerOnTop, isTrue);

    MiniPlayerVisibility.popFullPlayer();

    expect(MiniPlayerVisibility.instance.isFullPlayerOnTop, isFalse);
  });

  test('notifies listeners when full player opens and closes', () {
    var notificationCount = 0;
    void listener() => notificationCount++;

    MiniPlayerVisibility.instance.addListener(listener);
    addTearDown(() => MiniPlayerVisibility.instance.removeListener(listener));

    MiniPlayerVisibility.pushFullPlayer();
    MiniPlayerVisibility.popFullPlayer();

    expect(notificationCount, 2);
  });
}
