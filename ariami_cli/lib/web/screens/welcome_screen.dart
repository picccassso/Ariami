import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isCheckingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  /// Check if setup is already complete and redirect to dashboard if so
  Future<void> _checkSetupStatus() async {
    try {
      final response = await http.get(Uri.parse('/api/setup/status'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final isComplete = data['isComplete'] as bool? ?? false;

        if (isComplete && mounted) {
          // Setup is complete, redirect to dashboard
          Navigator.pushReplacementNamed(context, '/dashboard');
          return;
        }
      }
    } catch (e) {
      print('Error checking setup status: $e');
    }

    // Show welcome screen if setup not complete or error occurred
    if (mounted) {
      setState(() {
        _isCheckingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking status
    if (_isCheckingStatus) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_note,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'Ariami',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your personal music server',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/tailscale-check');
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 16,
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
