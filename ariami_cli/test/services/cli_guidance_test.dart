import 'package:ariami_cli/services/cli_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CliGuidance', () {
    test('lists focused setup help topics', () {
      final lines = CliGuidance.help('music-folder').toList();

      expect(lines.first, 'Ariami CLI — music-folder');
      expect(lines.join('\n'),
          contains('never moves, edits, deletes, or uploads'));
    });

    test('explains the next action for each server state', () {
      expect(
        CliGuidance.nextStep(
          isRunning: false,
          setupComplete: false,
          hasOwnerAccount: false,
        ),
        contains('ariami_cli start'),
      );
      expect(
        CliGuidance.nextStep(
          isRunning: true,
          setupComplete: false,
          hasOwnerAccount: false,
        ),
        contains('continue setup'),
      );
      expect(
        CliGuidance.nextStep(
          isRunning: true,
          setupComplete: true,
          hasOwnerAccount: false,
        ),
        contains('create the owner account'),
      );
    });
  });
}
