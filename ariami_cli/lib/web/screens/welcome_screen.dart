import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../utils/constants.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final WebAuthService _authService = WebAuthService();
  late final WebApiClient _apiClient = WebApiClient(
    tokenProvider: _authService.getSessionToken,
  );
  bool _isCheckingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  /// Check if setup is already complete and redirect to dashboard if so
  Future<void> _checkSetupStatus() async {
    try {
      final response = await _apiClient.get('/api/setup/status');

      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};
        final isComplete = data['isComplete'] as bool? ?? false;

        if (isComplete && mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking setup status: $e');
    }

    if (mounted) {
      setState(() {
        _isCheckingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingStatus) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Glass Logo Container
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.05),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Text(
                'Ariami',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your personal music server',
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 64),
              SizedBox(
                width: 240,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/tailscale-check');
                  },
                  child: const Text('Get Started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
