import 'dart:ui';
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/services/server/server_port_policy.dart';
import 'package:flutter/material.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../utils/constants.dart';
import '../utils/web_navigation.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with RouteAware {
  final WebAuthService _authService = WebAuthService();
  late final WebApiClient _apiClient = WebApiClient(
    tokenProvider: _authService.getSessionToken,
  );
  bool _isCheckingStatus = true;
  String? _portFallbackMessage;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      webRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    webRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _checkSetupStatus();
  }

  /// Check if setup is already complete and redirect to dashboard if so
  Future<void> _checkSetupStatus() async {
    try {
      final response = await _apiClient.get('/api/setup/status');

      if (response.isAuthError) {
        if (response.errorCode == AuthErrorCodes.sessionExpired) {
          await _authService.clearSessionToken();
        }
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};
        final isComplete = data['isComplete'] as bool? ?? false;

        if (isComplete && mounted) {
          navigateToDashboard(context);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking setup status: $e');
    }

    await _loadPortFallbackMessage();

    if (mounted) {
      setState(() {
        _isCheckingStatus = false;
      });
    }
  }

  Future<void> _loadPortFallbackMessage() async {
    try {
      final response = await _apiClient.get('/api/server-info');
      if (response.statusCode != 200) {
        return;
      }

      final data = response.jsonBody ?? <String, dynamic>{};
      final portFallbackUsed = data['portFallbackUsed'] as bool? ?? false;
      if (!portFallbackUsed) {
        return;
      }

      final attemptedPort = data['attemptedPort'] as int? ??
          ServerPortPolicy.defaultPort;
      final actualPort =
          data['port'] as int? ?? ServerPortPolicy.defaultPort;
      _portFallbackMessage = ServerPortPolicy.formatFallbackMessage(
        attemptedPort: attemptedPort,
        actualPort: actualPort,
      );
    } catch (e) {
      debugPrint('Error loading server port info: $e');
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
      body: Column(
        children: [
          if (_portFallbackMessage != null)
            MaterialBanner(
              content: Text(_portFallbackMessage!),
              leading: const Icon(Icons.info_outline),
              backgroundColor: Colors.amber.shade100,
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _portFallbackMessage = null;
                    });
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: Container(
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
          ),
        ],
      ),
    );
  }
}
