import 'package:ariami_core/services/setup/music_folder_path_helper.dart';

import '../services/cli_state_service.dart';

/// Command to configure CLI settings without starting the web setup UI.
class ConfigureCommand {
  final CliStateService _stateService = CliStateService();

  /// Execute the configure command.
  Future<void> execute({String? musicFolder}) async {
    if (musicFolder == null || musicFolder.trim().isEmpty) {
      print('Error: --music-folder requires a path.');
      print('');
      print('Example: ariami_cli configure --music-folder /home/user/Music');
      return;
    }

    final validation = await MusicFolderPathHelper.validate(musicFolder);
    if (!validation.isValid) {
      print('Error: ${validation.message}');
      if (validation.error == MusicFolderPathError.missing) {
        print('Check that the path exists on this machine.');
      } else if (validation.error == MusicFolderPathError.permissionDenied) {
        print('Ensure the server user can read this directory.');
      }
      return;
    }

    await _stateService.ensureConfigDir();
    await _stateService.setMusicFolderPath(validation.path);
    print('Music folder saved: ${validation.path}');
  }
}
