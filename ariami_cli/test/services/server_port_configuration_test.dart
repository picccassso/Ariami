import 'package:ariami_cli/services/container_environment.dart';
import 'package:ariami_cli/services/server_port_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ContainerEnvironment environment(Map<String, String> values) {
    return ContainerEnvironment(
      environment: values,
      dockerenvPath: '/path/that/does/not/exist',
    );
  }

  test('uses the default port without marking it explicit', () {
    final result = resolveServerPort(
      parsedPort: '8080',
      cliExplicit: false,
      environment: environment(const {}),
    );

    expect(result.port, 8080);
    expect(result.explicitlyConfigured, isFalse);
  });

  test('uses ARIAMI_PORT and marks it explicit', () {
    final result = resolveServerPort(
      parsedPort: '8080',
      cliExplicit: false,
      environment: environment(const {'ARIAMI_PORT': '2000'}),
    );

    expect(result.port, 2000);
    expect(result.explicitlyConfigured, isTrue);
  });

  test('an explicit CLI port wins over ARIAMI_PORT', () {
    final result = resolveServerPort(
      parsedPort: '3000',
      cliExplicit: true,
      environment: environment(const {'ARIAMI_PORT': '2000'}),
    );

    expect(result.port, 3000);
    expect(result.explicitlyConfigured, isTrue);
  });

  test('an explicit CLI port wins over an invalid ARIAMI_PORT', () {
    final result = resolveServerPort(
      parsedPort: '3000',
      cliExplicit: true,
      environment: environment(const {'ARIAMI_PORT': 'not-a-port'}),
    );

    expect(result.port, 3000);
  });

  test('rejects an invalid ARIAMI_PORT when no CLI port was supplied', () {
    expect(
      () => resolveServerPort(
        parsedPort: '8080',
        cliExplicit: false,
        environment: environment(const {'ARIAMI_PORT': '65536'}),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('ARIAMI_PORT'),
        ),
      ),
    );
  });

  test('rejects an invalid explicit CLI port', () {
    expect(
      () => resolveServerPort(
        parsedPort: '0',
        cliExplicit: true,
        environment: environment(const {}),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('--port'),
        ),
      ),
    );
  });
}
