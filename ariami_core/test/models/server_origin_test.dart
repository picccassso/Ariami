import 'package:ariami_core/models/server_origin.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeSecurePublicOrigin', () {
    test('normalizes HTTPS origins and preserves non-default ports', () {
      expect(
        normalizeSecurePublicOrigin(' HTTPS://Review.Ariami.XYZ/ '),
        'https://review.ariami.xyz',
      );
      expect(
        normalizeSecurePublicOrigin('https://review.ariami.xyz:8443'),
        'https://review.ariami.xyz:8443',
      );
    });

    test('rejects downgrade and origin-injection shapes', () {
      expect(normalizeSecurePublicOrigin('http://review.ariami.xyz'), isNull);
      expect(
        normalizeSecurePublicOrigin('https://user:pass@review.ariami.xyz'),
        isNull,
      );
      expect(
        normalizeSecurePublicOrigin('https://review.ariami.xyz/api'),
        isNull,
      );
      expect(
        normalizeSecurePublicOrigin('https://review.ariami.xyz?next=evil'),
        isNull,
      );
      expect(
        normalizeSecurePublicOrigin('https://review.ariami.xyz#fragment'),
        isNull,
      );
    });
  });

  test('websocketOriginFor upgrades HTTPS to WSS', () {
    expect(
      websocketOriginFor('https://review.ariami.xyz'),
      'wss://review.ariami.xyz',
    );
    expect(websocketOriginFor('http://192.168.1.50:8080'),
        'ws://192.168.1.50:8080');
  });
}
