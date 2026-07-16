import 'setup_help.dart';

/// Every onboarding string in one place, so the words can be reviewed and
/// edited without touching layout code.
class OnboardingCopy {
  OnboardingCopy._();

  // ── Welcome screen ────────────────────────────────────────────────────────
  static const welcomeTitle = 'Welcome to Ariami';
  static const welcomeThanks = 'Thanks for trying Ariami.';
  static const welcomeBody =
      'Ariami turns your own music collection into your own streaming '
      'service: host it on this computer, then play it on your phone and '
      'other devices — no cloud required.';
  static const welcomeFootnote =
      'Setup only takes a couple of minutes, and every step explains itself '
      'along the way.';
  static const welcomeAction = 'Get started';

  // ── Contextual help topics ────────────────────────────────────────────────

  static const tailscale = SetupHelpTopic(
    title: 'About Tailscale',
    sections: [
      SetupHelpSection(
        heading: 'What is Tailscale?',
        body: 'Tailscale is a free app that creates a private, secure '
            'connection between your own devices, wherever they are — like '
            'an invisible cable between your phone and this computer.',
      ),
      SetupHelpSection(
        heading: 'Why Ariami uses it',
        body: 'With Tailscale, you can listen to your library away from '
            'home — on mobile data, at work, on holiday — without opening '
            'your server to the public internet. Only devices you have '
            'signed in to your Tailscale account can reach it.',
      ),
      SetupHelpSection(
        heading: 'Is it required?',
        body: 'No. It is entirely optional. If you only listen at home, '
            'skip it and continue with local setup — everything works on '
            'your Wi-Fi network. You can install Tailscale later and Ariami '
            'will pick it up automatically.',
      ),
    ],
  );

  static const musicFolder = SetupHelpTopic(
    title: 'About your music folder',
    sections: [
      SetupHelpSection(
        heading: 'Why Ariami needs a folder',
        body: 'Ariami builds your library from a folder of music files you '
            'already own. Point it at the folder where your albums live '
            '(for example Music/My Collection) and it takes care of the '
            'rest.',
      ),
      SetupHelpSection(
        heading: 'What happens to the files',
        body: 'Ariami scans the files to read their tags — title, artist, '
            'album, track number — and looks for cover artwork embedded in '
            'the files or saved alongside them. Your original files are '
            'never modified, moved, or uploaded to any Ariami cloud '
            'service; everything stays on this computer.',
      ),
      SetupHelpSection(
        heading: 'Changed your mind later?',
        body: 'You can pick a different folder at any time from the '
            'dashboard. Ariami simply rescans the new location.',
      ),
    ],
  );

  static const ownerAccount = SetupHelpTopic(
    title: 'About your account',
    sections: [
      SetupHelpSection(
        heading: 'Why create an account?',
        body: 'This account is how you sign in to listen on your Ariami '
            'devices. It keeps your playlists, downloads, and listening '
            'history separate from anyone else who uses your server.',
      ),
      SetupHelpSection(
        heading: 'The first account is the owner',
        body: 'As the first account on this server, it can also manage the '
            'server: invite family members, create more accounts, and '
            'change server settings from the dashboard.',
      ),
      SetupHelpSection(
        heading: 'Where is it stored?',
        body: 'The account lives only on this computer, protected with a '
            'securely hashed password. Nothing is sent to Ariami or any '
            'third party.',
      ),
    ],
  );

  static const connectDevices = SetupHelpTopic(
    title: 'Connecting your devices',
    sections: [
      SetupHelpSection(
        heading: 'What this step does',
        body: 'Your server is running. This screen helps you link your '
            'phone to it — scan the QR code with the Ariami mobile app, or '
            'type an address and one-time invite code by hand.',
      ),
      SetupHelpSection(
        heading: 'The addresses',
        body: '“Local network” works for devices on the same Wi-Fi as this '
            'computer. “Tailscale” also works away from home, on any device '
            'signed in to your Tailscale account.',
      ),
      SetupHelpSection(
        heading: 'You can skip this',
        body: 'No devices to connect right now? Choose “Continue to '
            'Dashboard” and finish setup. You can connect phones later from '
            'the dashboard at any time.',
      ),
    ],
  );

  static const scanning = SetupHelpTopic(
    title: 'What scanning does',
    sections: [
      SetupHelpSection(
        heading: 'Discovering files',
        body: 'Ariami walks through your music folder and finds every '
            'audio file inside it, including files in sub-folders.',
      ),
      SetupHelpSection(
        heading: 'Processing tracks',
        body: 'Each track is read once to extract its metadata — title, '
            'artist, album, track and disc numbers, year, and duration — '
            'which is how songs are grouped into albums and artists.',
      ),
      SetupHelpSection(
        heading: 'Artwork',
        body: 'Cover art is detected from images embedded in the audio '
            'files or from pictures like cover.jpg stored next to them.',
      ),
      SetupHelpSection(
        heading: 'Duplicates',
        body: 'If the same track appears more than once, Ariami keeps your '
            'library tidy by recognising the copies instead of listing the '
            'same song twice.',
      ),
      SetupHelpSection(
        heading: 'Warnings and skipped files',
        body: 'A note that some files were skipped is informational — it '
            'usually means a file was unreadable, damaged, or not really an '
            'audio file. The rest of your library is unaffected. Only a '
            'message that the whole scan failed needs action: try again or '
            'choose a different folder.',
      ),
      SetupHelpSection(
        heading: 'When it finishes',
        body: 'Your library is ready. Review the exact file count and any '
            'warnings, then select Continue to finish setup. Re-scans after '
            'adding new music are much faster, because already-known files '
            'are remembered.',
      ),
    ],
  );
}
