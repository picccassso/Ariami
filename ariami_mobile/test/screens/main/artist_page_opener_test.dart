import 'package:ariami_mobile/screens/main/artist_page_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards opens to the registered callback', () {
    final opener = ArtistPageOpener();
    final received = <String>[];

    opener.register(received.add);
    opener.open('Alice');

    expect(received, ['Alice']);
  });

  test('unregister stops the handoff', () {
    final opener = ArtistPageOpener();
    final received = <String>[];
    void open(String name) => received.add(name);

    opener.register(open);
    opener.unregister(open);
    opener.open('Alice');

    expect(received, isEmpty);
  });

  test('open without a registered callback is a no-op', () {
    expect(() => ArtistPageOpener().open('Alice'), returnsNormally);
  });
}
