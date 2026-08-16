import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/services/server/server_port_policy.dart';
import 'package:flutter/material.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../onboarding/setup_help.dart';
import '../utils/constants.dart';
import '../utils/layout.dart';
import '../utils/web_navigation.dart';
import '../widgets/ui/page_shell.dart';

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

      final attemptedPort =
          data['attemptedPort'] as int? ?? ServerPortPolicy.defaultPort;
      final actualPort = data['port'] as int? ?? ServerPortPolicy.defaultPort;
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [
          if (_portFallbackMessage != null)
            MaterialBanner(
              content: Text(_portFallbackMessage!),
              leading: const Icon(Icons.info_outline_rounded),
              backgroundColor: AppTheme.surfaceRaised,
              dividerColor: AppTheme.borderGrey,
              contentTextStyle: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13.5,
              ),
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
            child: PageShell(
              maxWidth: AppLayout.proseMaxWidth,
              centerVertically: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _WelcomeMark(),
                      const Spacer(),
                      SetupHelpButton(topic: CliOnboardingCopy.welcome),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'Your own music service',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Host the music you already own on this server, then '
                    'listen and manage it from your own devices. Setup '
                    'explains each choice as you go.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacementNamed(
                            context, '/tailscale-check');
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                      iconAlignment: IconAlignment.end,
                      label: const Text('Get started'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Takes about a minute. Your files are never moved, '
                    'changed or uploaded.',
                    style: AppTheme.meta,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ariami wordmark used as the setup flow's masthead.
class _WelcomeMark extends StatelessWidget {
  const _WelcomeMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            size: 18,
            color: AppTheme.pureBlack,
          ),
        ),
        const SizedBox(width: 11),
        const Text(
          'Ariami',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
