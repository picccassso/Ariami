import 'dart:async';

import 'package:flutter/material.dart';

import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../utils/constants.dart';
import 'qr_code_screen.dart';

/// First-run owner account creation before QR / dashboard handoff.
class OwnerSetupScreen extends StatefulWidget {
  const OwnerSetupScreen({super.key});

  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _setupCodeController = TextEditingController();

  final WebAuthService _authService = WebAuthService();
  final WebSetupService _setupService = WebSetupService();
  late final WebApiClient _apiClient = WebApiClient(
    tokenProvider: _authService.getSessionToken,
  );

  bool _isInitializing = true;
  bool _isSubmitting = false;
  bool _hasOwner = false;
  bool _hasSession = false;
  bool _isOwnerSession = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _loadOwnerState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _setupCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadOwnerState() async {
    setState(() {
      _isInitializing = true;
      _inlineError = null;
    });

    // Best-effort: figure out whether an owner already exists so we can show
    // either the create form or the "already configured" panel. This probe is
    // purely informational — on first-run setup there are no users yet — so a
    // transient failure here must not surface as a hard error. The user can
    // still create the owner below, and any real problem is reported by the
    // create/login call itself.
    final hasUsers = await _probeHasOwner();
    final (hasSession, isOwnerSession) = await _probeSessionState();

    if (!mounted) return;
    setState(() {
      _hasOwner = hasUsers;
      _hasSession = hasSession;
      _isOwnerSession = isOwnerSession;
      _isInitializing = false;
    });
  }

  /// Whether the server already has an owner account. Retries a few times to
  /// ride out the first-load race where the page renders just before the local
  /// server is ready to answer. Defaults to `false` (show the create form) if
  /// it can't be determined.
  Future<bool> _probeHasOwner() async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _apiClient.get(
          '/api/server-info',
          includeAuth: false,
        );
        if (response.isSuccess) {
          final info = response.jsonBody ?? <String, dynamic>{};
          return info['hasUsers'] as bool? ??
              ((info['registeredUsers'] as int? ?? 0) > 0);
        }
      } catch (_) {
        // Best-effort probe; fall through to retry / default.
      }
      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  /// Best-effort check of the current session. Returns
  /// `(hasSession, isOwnerSession)`, defaulting to signed-out on any failure.
  Future<(bool, bool)> _probeSessionState() async {
    try {
      if (!await _authService.hasSessionToken()) {
        return (false, false);
      }
      final meResponse = await _authService.me();
      if (meResponse.isAuthError) {
        await _authService.clearSessionToken();
        return (false, false);
      }
      if (!meResponse.isSuccess) {
        return (false, false);
      }
      final isOwner = meResponse.jsonBody?['isAdmin'] as bool? ?? false;
      return (true, isOwner);
    } catch (_) {
      return (false, false);
    }
  }

  String? _extractError(WebApiResponse response) {
    final message = response.errorMessage;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return null;
  }

  Future<void> _finishSetupAndContinue() async {
    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    try {
      if (!await _authService.isCurrentUserAdmin()) {
        final hasToken = await _authService.hasSessionToken();
        if (!mounted) return;
        setState(() {
          _inlineError =
              'Owner privileges are required. Sign in as the owner account to continue.';
          _hasSession = hasToken;
          _isOwnerSession = false;
        });
        return;
      }

      await _setupService.markSetupComplete();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/qr-code',
        arguments: const QRCodeScreenArgs(autoNavigateOnConnection: true),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = 'Failed to complete setup: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _createOwner() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final setupCode = _setupCodeController.text.trim();

    try {
      final registerResponse = await _authService.register(
        username: username,
        password: password,
        bootstrapCode: setupCode.isEmpty ? null : setupCode,
      );
      if (!registerResponse.isSuccess) {
        setState(() {
          _inlineError =
              _extractError(registerResponse) ?? 'Registration failed.';
        });
        return;
      }

      final loginResponse = await _authService.login(
        username: username,
        password: password,
      );
      if (!loginResponse.isSuccess) {
        setState(() {
          _inlineError = _extractError(loginResponse) ??
              'Owner created but login failed. Sign in to continue.';
          _hasOwner = true;
        });
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Owner account created for $username'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _finishSetupAndContinue();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = 'Failed to create owner account: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _goToLogin({bool switchAccount = false}) {
    if (switchAccount) {
      unawaited(_authService.clearSessionToken());
    }
    Navigator.pushReplacementNamed(
      context,
      '/login',
      arguments: const OwnerSetupLoginArgs(successRoute: '/qr-code'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _isInitializing
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'CREATE OWNER ACCOUNT',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Create the owner account for this server. '
                          'The first account is the admin/owner. '
                          'Owner sign-in is required for connected-device management '
                          'and password changes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceBlack,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.borderGrey),
                          ),
                          child: _hasOwner
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.greenAccent,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'OWNER ACCOUNT ALREADY CONFIGURED',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _hasSession && _isOwnerSession
                                          ? 'You are signed in as the owner. Continue to connect your mobile app.'
                                          : _hasSession
                                              ? 'Signed in, but this account is not the owner. Sign in as the owner to continue.'
                                              : 'Sign in as the owner to continue setup.',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                )
                              : Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _usernameController,
                                        enabled: !_isSubmitting,
                                        decoration: const InputDecoration(
                                          labelText: 'OWNER USERNAME',
                                        ),
                                        validator: (value) {
                                          final v = (value ?? '').trim();
                                          if (v.isEmpty) {
                                            return 'Username is required.';
                                          }
                                          if (v.length < 3) {
                                            return 'Username must be at least 3 characters.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: _passwordController,
                                        enabled: !_isSubmitting,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                          labelText: 'OWNER PASSWORD',
                                        ),
                                        validator: (value) {
                                          final v = value ?? '';
                                          if (v.isEmpty) {
                                            return 'Password is required.';
                                          }
                                          if (v.length < 10) {
                                            return 'Password must be at least 10 characters.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: _confirmPasswordController,
                                        enabled: !_isSubmitting,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                          labelText: 'CONFIRM PASSWORD',
                                        ),
                                        validator: (value) {
                                          if ((value ?? '') !=
                                              _passwordController.text) {
                                            return 'Passwords do not match.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: _setupCodeController,
                                        enabled: !_isSubmitting,
                                        decoration: const InputDecoration(
                                          labelText: 'SETUP CODE (IF REMOTE)',
                                          helperText:
                                              'Shown in the server terminal at '
                                              'startup. Only needed when this '
                                              'page is opened from another '
                                              'device.',
                                          helperMaxLines: 3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        if (_inlineError != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _inlineError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (_hasOwner) ...[
                          if (_hasSession && _isOwnerSession)
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : _finishSetupAndContinue,
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : const Text('CONTINUE TO QR CODE'),
                              ),
                            ),
                          if (!_hasSession || !_isOwnerSession) ...[
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    _isSubmitting ? null : () => _goToLogin(),
                                child: const Text('SIGN IN AS OWNER'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _goToLogin(switchAccount: true),
                            child: Text(
                              _hasSession
                                  ? 'SWITCH ACCOUNT'
                                  : 'USE A DIFFERENT ACCOUNT',
                            ),
                          ),
                        ] else
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _createOwner,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text('CREATE OWNER ACCOUNT'),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Route arguments for [LoginScreen] when opened from owner setup.
class OwnerSetupLoginArgs {
  const OwnerSetupLoginArgs({required this.successRoute});

  final String successRoute;
}
