import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Icon(
                      Icons.music_note,
                      size: orientation == Orientation.portrait ? 120 : 80,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 32),

                    // App Name
                    Text(
                      'Basic Music App',
                      style: TextStyle(
                        fontSize: orientation == Orientation.portrait ? 32 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Tagline
                    Text(
                      'Stream your music anywhere',
                      style: TextStyle(
                        fontSize: orientation == Orientation.portrait ? 20 : 18,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Description
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Connect to your desktop server and enjoy your music library on the go. '
                        'Stream seamlessly over Tailscale for secure, private access.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Connect Button
                    SizedBox(
                      width: double.infinity,
                      height: 56, // Touch-friendly height (>48dp)
                      child: ElevatedButton(
                        onPressed: () {
                          // TODO: Navigate to Tailscale check screen
                          Navigator.pushNamed(context, '/setup/tailscale');
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Connect to Desktop',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
