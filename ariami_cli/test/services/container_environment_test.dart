import 'dart:io';

import 'package:ariami_cli/services/container_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContainerEnvironment', () {
    test('trims advertised host override and treats blank as unset', () {
      final env = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_HOST': '  100.64.10.20  '},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(env.advertisedHostOverride, '100.64.10.20');

      final blank = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_HOST': '   '},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(blank.advertisedHostOverride, isNull);
    });

    test('trims advertised LAN and Tailscale overrides', () {
      final env = ContainerEnvironment(
        environment: const {
          'ARIAMI_ADVERTISED_LAN_HOST': '  192.168.1.50  ',
          'ARIAMI_ADVERTISED_TAILSCALE_HOST': '  100.64.10.20  ',
        },
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(env.advertisedLanHostOverride, '192.168.1.50');
      expect(env.advertisedTailscaleHostOverride, '100.64.10.20');

      final blank = ContainerEnvironment(
        environment: const {
          'ARIAMI_ADVERTISED_LAN_HOST': '   ',
          'ARIAMI_ADVERTISED_TAILSCALE_HOST': '',
        },
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(blank.advertisedLanHostOverride, isNull);
      expect(blank.advertisedTailscaleHostOverride, isNull);
    });

    test('reads and trims the public origin override', () {
      final env = ContainerEnvironment(
        environment: const {
          'ARIAMI_PUBLIC_ORIGIN': '  https://review.ariami.xyz  ',
        },
        dockerenvPath: '/path/that/does/not/exist',
      );
      expect(env.publicOriginOverride, 'https://review.ariami.xyz');
    });

    test('parses the server bind port override', () {
      final env = ContainerEnvironment(
        environment: const {'ARIAMI_PORT': '  2000  '},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(env.serverPortOverride, 2000);
      expect(env.invalidServerPortValue, isNull);
    });

    test('reports unusable server bind ports', () {
      for (final value in const ['abc', '0', '-1', '65536', '80.5']) {
        final env = ContainerEnvironment(
          environment: {'ARIAMI_PORT': value},
          dockerenvPath: '/path/that/does/not/exist',
        );

        expect(env.serverPortOverride, isNull, reason: 'value: "$value"');
        expect(env.invalidServerPortValue, value, reason: 'value: "$value"');
      }
    });

    test('parses the advertised port override', () {
      final env = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_PORT': '  2000  '},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(env.advertisedPortOverride, 2000);
      expect(env.invalidAdvertisedPortValue, isNull);
    });

    test('ignores unset, blank, and out-of-range advertised ports', () {
      for (final value in const ['abc', '0', '-1', '65536', '80.5']) {
        final env = ContainerEnvironment(
          environment: {'ARIAMI_ADVERTISED_PORT': value},
          dockerenvPath: '/path/that/does/not/exist',
        );

        expect(env.advertisedPortOverride, isNull, reason: 'value: "$value"');
        // Set but unusable: reported so startup can warn about the typo.
        expect(env.invalidAdvertisedPortValue, value,
            reason: 'value: "$value"');
      }

      for (final env in [
        ContainerEnvironment(
          environment: const {},
          dockerenvPath: '/path/that/does/not/exist',
        ),
        ContainerEnvironment(
          environment: const {'ARIAMI_ADVERTISED_PORT': '   '},
          dockerenvPath: '/path/that/does/not/exist',
        ),
      ]) {
        expect(env.advertisedPortOverride, isNull);
        // Unset and blank are not typos, so there is nothing to warn about.
        expect(env.invalidAdvertisedPortValue, isNull);
      }
    });

    test('an advertised port alone is not an advertised host override', () {
      // A port remap says nothing about which addresses are reachable.
      final env = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_PORT': '2000'},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(env.hasAnyAdvertisedOverride, isFalse);
    });

    test('detects any advertised override', () {
      final none = ContainerEnvironment(
        environment: const {},
        dockerenvPath: '/path/that/does/not/exist',
      );
      final generic = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_HOST': '192.168.1.50'},
        dockerenvPath: '/path/that/does/not/exist',
      );
      final lan = ContainerEnvironment(
        environment: const {'ARIAMI_ADVERTISED_LAN_HOST': '192.168.1.50'},
        dockerenvPath: '/path/that/does/not/exist',
      );
      final tailscale = ContainerEnvironment(
        environment: const {
          'ARIAMI_ADVERTISED_TAILSCALE_HOST': '100.64.10.20',
        },
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(none.hasAnyAdvertisedOverride, isFalse);
      expect(generic.hasAnyAdvertisedOverride, isTrue);
      expect(lan.hasAnyAdvertisedOverride, isTrue);
      expect(tailscale.hasAnyAdvertisedOverride, isTrue);
    });

    test('detects container env flag values', () {
      final one = ContainerEnvironment(
        environment: const {'ARIAMI_CONTAINER': '1'},
        dockerenvPath: '/path/that/does/not/exist',
      );
      final trueValue = ContainerEnvironment(
        environment: const {'ARIAMI_CONTAINER': ' TRUE '},
        dockerenvPath: '/path/that/does/not/exist',
      );
      final falseValue = ContainerEnvironment(
        environment: const {'ARIAMI_CONTAINER': '0'},
        dockerenvPath: '/path/that/does/not/exist',
      );

      expect(one.isContainerized, isTrue);
      expect(trueValue.isContainerized, isTrue);
      expect(falseValue.isContainerized, isFalse);
    });

    test('detects dockerenv file', () async {
      final dir = await Directory.systemTemp.createTemp('ariami_dockerenv_');
      final dockerenv = File('${dir.path}/.dockerenv');
      await dockerenv.writeAsString('');

      try {
        final env = ContainerEnvironment(
          environment: const {},
          dockerenvPath: dockerenv.path,
        );

        expect(env.isContainerized, isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
