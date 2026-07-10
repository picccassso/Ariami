import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A small, reusable explanation for one setup step.
class SetupHelpTopic {
  const SetupHelpTopic({required this.title, required this.sections});

  final String title;
  final List<SetupHelpSection> sections;
}

class SetupHelpSection {
  const SetupHelpSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// Setup language tailored to the server-first CLI experience.
class CliOnboardingCopy {
  CliOnboardingCopy._();

  static const welcome = SetupHelpTopic(
    title: 'Welcome to Ariami',
    sections: [
      SetupHelpSection(
        heading: 'Your own music service',
        body:
            'Ariami turns the music collection already stored on this server into a private streaming service. You manage it here, then listen from your phone, TV, desktop, or this browser.',
      ),
      SetupHelpSection(
        heading: 'Where everything lives',
        body:
            'Your music files, library data, and accounts stay on this server. Ariami does not move, modify, or upload your original music files.',
      ),
      SetupHelpSection(
        heading: 'What setup covers',
        body:
            'You can optionally enable private remote access with Tailscale, choose your music folder, let Ariami scan it, and create the owner account.',
      ),
    ],
  );

  static const tailscale = SetupHelpTopic(
    title: 'About Tailscale',
    sections: [
      SetupHelpSection(
        heading: 'What it is',
        body:
            'Tailscale creates a private, secure connection between your own devices — like an invisible cable between this server and your phone or TV.',
      ),
      SetupHelpSection(
        heading: 'Why use it',
        body:
            'It lets you listen away from home without exposing Ariami to the public internet. Only devices signed in to your Tailscale account can reach the Tailscale address.',
      ),
      SetupHelpSection(
        heading: 'It is optional',
        body:
            'If you only listen at home, continue without it. Ariami works on your local network and will detect Tailscale automatically if you add it later.',
      ),
    ],
  );

  static const musicFolder = SetupHelpTopic(
    title: 'About your music folder',
    sections: [
      SetupHelpSection(
        heading: 'Choose the server path',
        body:
            'Enter the folder on this server where your albums live. If you are using Ariami through a browser on another device, this is still a path on the server, not on the device in your hand.',
      ),
      SetupHelpSection(
        heading: 'What Ariami reads',
        body:
            'Ariami reads track tags such as artist, album, title, and track number, plus cover art embedded in files or saved alongside them. Your original files are never modified, moved, or uploaded.',
      ),
      SetupHelpSection(
        heading: 'You can change it later',
        body:
            'Choose a different folder any time from the server dashboard and Ariami will rescan the new location.',
      ),
    ],
  );

  static const scanning = SetupHelpTopic(
    title: 'What scanning does',
    sections: [
      SetupHelpSection(
        heading: 'Building your library',
        body:
            'Ariami finds audio files in the selected folder and its subfolders, then uses their metadata to group tracks into albums and artists.',
      ),
      SetupHelpSection(
        heading: 'Skipped files',
        body:
            'A skipped-file message is normally informational: a file may be unreadable, damaged, or not really audio. The rest of the library is unaffected.',
      ),
      SetupHelpSection(
        heading: 'After the first scan',
        body:
            'Future scans after you add music are faster because already-known files are remembered.',
      ),
    ],
  );

  static const owner = SetupHelpTopic(
    title: 'About the owner account',
    sections: [
      SetupHelpSection(
        heading: 'The first account is the owner',
        body:
            'Use it to listen across your Ariami devices and to manage this server: users, connected devices, and settings.',
      ),
      SetupHelpSection(
        heading: 'Remote setup code',
        body:
            'When this page is opened from another device, enter the one-time setup code shown in the server terminal. It proves that you can access the server. It is not needed when using the browser on the server itself.',
      ),
      SetupHelpSection(
        heading: 'Privacy',
        body:
            'The account is stored on this server with a securely hashed password. Nothing is sent to Ariami or a third party.',
      ),
    ],
  );

  static const connect = SetupHelpTopic(
    title: 'Connecting your devices',
    sections: [
      SetupHelpSection(
        heading: 'What this does',
        body:
            'Scan the QR code with Ariami Mobile, or use the displayed address and pairing details on another Ariami device.',
      ),
      SetupHelpSection(
        heading: 'Which address to use',
        body:
            'The local-network address works on the same Wi-Fi or LAN. The Tailscale address also works away from home for devices signed in to the same Tailscale account.',
      ),
      SetupHelpSection(
        heading: 'You can do this later',
        body:
            'Go to the dashboard if you have no device to connect right now. You can return to the connection screen whenever you need it.',
      ),
    ],
  );
}

class SetupHelpButton extends StatelessWidget {
  const SetupHelpButton({super.key, required this.topic});

  final SetupHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About this step',
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () => showSetupHelp(context, topic),
    );
  }
}

Future<void> showSetupHelp(BuildContext context, SetupHelpTopic topic) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: Row(
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 12),
          Expanded(child: Text(topic.title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in topic.sections) ...[
                Text(
                  section.heading,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  section.body,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (section != topic.sections.last) const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
