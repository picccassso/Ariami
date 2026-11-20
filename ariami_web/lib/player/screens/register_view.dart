import 'package:flutter/material.dart';
import 'package:ariami_core/models/credential_policy.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../widgets/auth_card.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit(ConnectionController connection) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    connection.register(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    return AuthCard(
      maxWidth: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthBadge(icon: Icons.person_add_alt_1_rounded),
            const SizedBox(height: 22),
            Text(
              'Create your account',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Pairing with ${connection.serverInfo?.name ?? 'your server'}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (connection.errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                connection.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFE57373),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextFormField(
              controller: _usernameController,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                final username = value?.trim() ?? '';
                if (username.length < CredentialPolicy.minUsernameLength) {
                  return 'Use at least ${CredentialPolicy.minUsernameLength} characters.';
                }
                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
                  return 'Use letters, numbers, and underscores only.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < CredentialPolicy.minPasswordLength
                  ? 'Use at least ${CredentialPolicy.minPasswordLength} characters.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              onFieldSubmitted: (_) => _submit(connection),
              validator: (value) => value != _passwordController.text
                  ? 'Passwords do not match.'
                  : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _submit(connection),
              child: const Text('Create account and connect'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: connection.showSignIn,
              child: const Text('Login instead'),
            ),
            TextButton(
              onPressed: () => connection.disconnect(),
              child: const Text('Back to pairing'),
            ),
          ],
        ),
      ),
    );
  }
}
