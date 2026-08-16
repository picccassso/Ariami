import 'package:ariami_core/ariami_core.dart';

import 'cli_state_service.dart';

/// Build the set of Ariami-owned paths a reset of [scope] may remove.
///
/// Shared by the `reset` command and the dashboard's reset endpoint so both
/// clear exactly the same state. [musicFolderGuard] is the configured library
/// path, passed through as [ResetPlan.musicFolderPathGuard] so nothing inside
/// the user's music folder can ever be deleted.
ResetPlan buildCliResetPlan(ResetScope scope, String? musicFolderGuard) {
  // Always-cleared setup/config state.
  final files = <String>[
    CliStateService.getConfigFilePath(),
    CliStateService.getServerStateFilePath(),
    CliStateService.getLogFilePath(),
    CliStateService.getPidFilePath(),
  ];
  final directories = <String>[];
  final sqliteDatabases = <String>[];

  if (scope == ResetScope.factoryReset) {
    files.addAll([
      CliStateService.getUsersFilePath(),
      CliStateService.getSessionsFilePath(),
      CliStateService.getMusicDiscoveryConfigFilePath(),
      CliStateService.getMetadataCacheFilePath(),
      CliStateService.getAutostartLogFilePath(),
    ]);
    sqliteDatabases.add(CliStateService.getCatalogDbFilePath());
    directories.addAll([
      CliStateService.getArtworkCacheDirPath(),
      CliStateService.getTranscodedCacheDirPath(),
    ]);
  }

  return ResetPlan(
    files: files,
    directories: directories,
    sqliteDatabases: sqliteDatabases,
    musicFolderPathGuard: musicFolderGuard,
  );
}
