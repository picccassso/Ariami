import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

import '../services/desktop_state_service.dart';
import '../services/server_initialization_service.dart';

class OwnerSetupScreen extends StatefulWidget {
  const OwnerSetupScreen({
    super.key,
    this.isOnboarding = true,
  });

  final bool isOnboarding;

  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final DesktopStateService _stateService = DesktopStateService();
  final AriamiHttpServer _httpServer = AriamiHttpServer();

  bool _isInitializing = true;
  bool _isSubmitting = false;
  bool _hasOwner = false;
  String? _ownerUsername;
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
    super.dispose();
  }

  Future<void> _loadOwnerState() async {
    setState(() {
      _isInitializing = true;
      _inlineError = null;
    });

    try {
      await ServerInitializationService.initializeAuth(_httpServer, _stateService);
      final hasOwner = await _stateService.hasOwnerAccount();
      final ownerUsername = hasOwner ? await _stateService.getOwnerUsername() : null;

      if (!mounted) return;
      setState(() {
        _hasOwner = hasOwner;
        _ownerUsername = ownerUsername;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = 'Failed to load owner state: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _completeFlow() async {
    if (widget.isOnboarding) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/connection');
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _skipForNow() async {
    await _stateService.markOwnerSetupSkipped();
    await _completeFlow();
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

    try {
      await ServerInitializationService.initializeAuth(_httpServer, _stateService);
      final authService = AuthService();
      await authService.register(username, password);

      // Ensure in-memory auth mode reflects the newly created owner immediately.
      _httpServer.updateAuthMode();
      await _stateService.clearOwnerSetupSkipped();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Owner account created for $username'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _completeFlow();
    } on UserExistsException {
      if (!mounted) return;
      setState(() {
        _inlineError = 'That username is already taken.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.message;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Setup'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _isInitializing
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Set Up Owner Authentication',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Owner is the first account created on this server. '
                        'Owner sign-in is required for device management and password changes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2A2A2A)),
                        ),
                        child: _hasOwner
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          color: Colors.greenAccent),
                                      SizedBox(width: 10),
                                      Text(
                                        'Owner Account Already Configured',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _ownerUsername == null
                                        ? 'You can continue. Use Owner Sign-In when you run Owner-only actions.'
                                        : 'Current owner username: $_ownerUsername',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              )
                            : Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                      controller: _usernameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Owner Username',
                                      ),
                                      validator: (value) {
                                        final v = (value ?? '').trim();
                                        if (v.isEmpty) return 'Username is required.';
                                        if (v.length < 3) {
                                          return 'Username must be at least 3 characters.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Owner Password',
                                      ),
                                      validator: (value) {
                                        final v = value ?? '';
                                        if (v.isEmpty) return 'Password is required.';
                                        if (v.length < 4) {
                                          return 'Password must be at least 4 characters.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _confirmPasswordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Confirm Password',
                                      ),
                                      validator: (value) {
                                        if ((value ?? '') != _passwordController.text) {
                                          return 'Passwords do not match.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (_inlineError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _inlineError!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_hasOwner)
                        ElevatedButton(
                          onPressed: _completeFlow,
                          child: Text(widget.isOnboarding
                              ? 'Continue Setup'
                              : 'Back to Dashboard'),
                        )
                      else ...[
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _createOwner,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create Owner Account'),
                        ),
                        if (widget.isOnboarding) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _isSubmitting ? null : _skipForNow,
                            child: const Text('Skip For Now'),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'If skipped, Owner-only actions will stay locked until an owner is created.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
