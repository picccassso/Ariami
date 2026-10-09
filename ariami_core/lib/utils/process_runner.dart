import 'dart:io';

/// Injectable stand-in for `Process.run`, so external-tool callers can be
/// faked in tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
