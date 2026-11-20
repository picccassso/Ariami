import 'dart:async';

import 'package:flutter/material.dart';

import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../utils/constants.dart';
import '../utils/layout.dart';
import '../utils/web_navigation.dart';
import '../widgets/ui/page_shell.dart';
import '../widgets/ui/status_pill.dart';
import 'owner_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final WebAuthService _authService = WebAuthService();
  final WebApiClient _apiClient = WebApiClient();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _webPlayerEnabled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadWebPlayerAvailability());
  }

  Future<void> _loadWebPlayerAvailability() async {
    try {
      final response =
          await _apiClient.get('/api/server-info', includeAuth: false);
      if (!mounted || !response.isSuccess || response.jsonBody == null) {
        return;
      }
      final enabled =
          response.jsonBody!['webPlayerEnabled'] as bool? ?? false;
      if (enabled != _webPlayerEnabled) {
        setState(() {
          _webPlayerEnabled = enabled;
        });
      }
    } catch (_) {
      // Server info is optional on login; keep link hidden on error.
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password are required.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loginResponse = await _authService.login(
        username: username,
        password: password,
      );
      if (!loginResponse.isSuccess) {
        setState(() {
          _isLoading = false;
          _errorMessage = _extractError(loginResponse) ?? 'Login failed.';
        });
        return;
      }

      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      final successRoute =
          args is OwnerSetupLoginArgs ? args.successRoute : '/dashboard';
      if (successRoute == '/qr-code') {
        final isOwner = await _authService.isCurrentUserAdmin();
        if (!isOwner) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'This account is not the server owner. Sign in with the owner account to continue setup.';
          });
          return;
        }
        await WebSetupService().markSetupComplete();
      }
      if (!mounted) return;
      if (successRoute == '/dashboard') {
        navigateToDashboard(context);
      } else {
        Navigator.pushReplacementNamed(context, successRoute);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _extractError(dynamic response) {
    final body = response.jsonBody;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'] as String?;
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageShell(
        maxWidth: AppLayout.formMaxWidth,
        centerVertically: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in to Ariami',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text(
              'Use the account you created on this server.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _usernameController,
              enabled: !_isLoading,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 18),
              NoticeBanner(
                icon: Icons.error_outline_rounded,
                tone: StatusTone.negative,
                message: _errorMessage!,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in'),
              ),
            ),
            if (_webPlayerEnabled) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  onPressed: () => openWebPlayer(newTab: false),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Open Web Player'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
