import 'container_environment.dart';

const int defaultServerPort = 8080;

class ServerPortConfiguration {
  const ServerPortConfiguration({
    required this.port,
    required this.explicitlyConfigured,
  });

  final int port;
  final bool explicitlyConfigured;
}

/// Resolves the bind port with `--port` taking precedence over `ARIAMI_PORT`.
///
/// An environment-selected port counts as explicit so the native `start`
/// path never falls away from an operator-selected port into 8080–8099.
ServerPortConfiguration resolveServerPort({
  required String parsedPort,
  required bool cliExplicit,
  required ContainerEnvironment environment,
}) {
  if (cliExplicit) {
    return ServerPortConfiguration(
      port: _parsePort(parsedPort, '--port'),
      explicitlyConfigured: true,
    );
  }

  final invalidEnvironmentValue = environment.invalidServerPortValue;
  if (invalidEnvironmentValue != null) {
    throw FormatException(
      'ARIAMI_PORT must be a port number between 1 and 65535 '
      '(received "$invalidEnvironmentValue").',
    );
  }

  final environmentPort = environment.serverPortOverride;
  if (environmentPort != null) {
    return ServerPortConfiguration(
      port: environmentPort,
      explicitlyConfigured: true,
    );
  }

  return ServerPortConfiguration(
    port: _parsePort(parsedPort, '--port'),
    explicitlyConfigured: false,
  );
}

int _parsePort(String value, String source) {
  final port = int.tryParse(value);
  if (port == null || port < 1 || port > 65535) {
    throw FormatException(
      '$source must be a port number between 1 and 65535 '
      '(received "$value").',
    );
  }
  return port;
}
