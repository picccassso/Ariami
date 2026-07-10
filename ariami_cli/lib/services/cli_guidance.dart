/// Plain-language guidance shared by Ariami CLI's terminal flows.
///
/// Keep this separate from command plumbing: these are the words a first-time
/// server owner needs, not implementation details.
class CliGuidance {
  CliGuidance._();

  static const firstRunIntro = <String>[
    'Ariami turns the music files you already own into your own private music service.',
    'This command runs the server; setup continues in a browser on this machine or another trusted device.',
  ];

  static const setupNextSteps = <String>[
    'What happens next in the dashboard:',
    '  1. Tailscale is optional. It lets your own signed-in devices reach Ariami away from home.',
    '  2. Choose the folder containing your music. Ariami reads its tags and artwork; it never moves, changes, or uploads your files.',
    '  3. Create the owner account. It signs you in on every device and manages this server.',
    '  4. Connect phones and TVs with the QR code, or do it later from the dashboard.',
  ];

  static const _topics = <String, List<String>>{
    'overview': [
      'Ariami CLI hosts your personal music library on this computer, Raspberry Pi, NAS, or server.',
      'Use the browser dashboard to complete setup and manage the server. Then connect Ariami on your phone, TV, or another desktop.',
      'Your music and accounts stay on your server. Keep the dashboard on your LAN, Tailscale, or another VPN; do not expose its port to the public internet.',
    ],
    'tailscale': [
      'Tailscale is optional. It creates a private connection between devices signed in to your Tailscale account, so Ariami can work away from home without public port-forwarding.',
      'If you only listen on your home network, skip it. You can install or connect Tailscale later; Ariami will detect it automatically.',
    ],
    'music-folder': [
      'Choose the folder where your albums live, for example /home/you/Music.',
      'Ariami scans audio metadata (title, artist, album, track details) and cover art. It never moves, edits, deletes, or uploads the original music files.',
      'You can change the folder later in the dashboard; Ariami will rescan the new location.',
    ],
    'scan': [
      'A scan finds audio files in the selected folder and its subfolders, then builds your library from their tags and artwork.',
      'A skipped-file notice is usually informational: that file may be unreadable, damaged, or not an audio file. The rest of the library is unaffected.',
      'Later scans are faster because Ariami remembers files it has already processed.',
    ],
    'owner': [
      'The first account is the owner. Use it to listen on your devices and to manage users and server settings.',
      'Accounts are stored on this Ariami server with securely hashed passwords; Ariami does not send them to a third party.',
      'When you open setup from another device, enter the one-time setup code printed in this terminal to prove you can access the server.',
    ],
    'connect': [
      'Use the dashboard QR code to connect Ariami Mobile, or enter the server address manually on another Ariami device.',
      'A LAN address works on the same network. A Tailscale address also works away from home for devices signed in to the same Tailscale account.',
      'You can skip connecting devices for now and return to it later from the dashboard.',
    ],
  };

  static Iterable<String> help(String? requestedTopic) {
    if (requestedTopic == null || requestedTopic.trim().isEmpty) {
      return [
        'Ariami CLI help',
        '',
        ..._topics['overview']!,
        '',
        'Learn about a setup step:',
        '  ariami_cli help tailscale',
        '  ariami_cli help music-folder',
        '  ariami_cli help scan',
        '  ariami_cli help owner',
        '  ariami_cli help connect',
      ];
    }

    final topic = requestedTopic.trim().toLowerCase();
    final lines = _topics[topic];
    if (lines == null) {
      return ['Unknown help topic "$requestedTopic".'];
    }

    return ['Ariami CLI — $topic', '', ...lines];
  }

  static bool isKnownTopic(String topic) =>
      _topics.containsKey(topic.trim().toLowerCase());

  static String nextStep({
    required bool isRunning,
    required bool setupComplete,
    required bool hasOwnerAccount,
  }) {
    if (!isRunning) {
      return 'Run "ariami_cli start" to start Ariami.';
    }
    if (!setupComplete) {
      return 'Open the Dashboard URL above to continue setup. The terminal must stay open until setup finishes.';
    }
    if (!hasOwnerAccount) {
      return 'Open the Dashboard URL above and create the owner account before using Ariami.';
    }
    return 'Open the Dashboard URL above to manage Ariami or connect another device.';
  }
}
