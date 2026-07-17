import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import '../widgets/common/setup_dark_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SetupDarkTheme(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        color: Colors.black,
        child: SafeArea(
          child: OrientationBuilder(
            builder: (context, orientation) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32.0, vertical: 24.0),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kSetupContentMaxWidth),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: orientation == Orientation.portrait ? 120 : 80,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 40),

                        // App Name
                        Text(
                          'Ariami',
                          style: Theme.of(context)
                              .textTheme
                              .displayLarge
                              ?.copyWith(
                                fontSize: 42,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),

                        // Tagline
                        Text(
                          'Stream your music anywhere',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.normal,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),

                        // Description
                        Text(
                          'Secure, private streaming from your desktop to your mobile device.',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                    height: 1.5,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 64),

                        // Connect Button
                        SizedBox(
                          width: double.infinity,
                          height: 64, // Taller button
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/setup/tailscale');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              elevation: 8,
                              shadowColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(32), // Pill shape
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Connect to Desktop',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Icon(Icons.arrow_forward_rounded),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
