import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../widgets/auth_card.dart';

class SignInView extends StatefulWidget {
  const SignInView({super.key});

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscure = true;
  bool _didPrefill = false;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _submit(ConnectionController connection, {bool takeOver = false}) {
    final user = _userController.text.trim();
    final pass = _passController.text;
    if (user.isEmpty || pass.isEmpty) return;
    connection.signIn(user, pass, takeOver: takeOver);
  }

  Future<void> _setUpNewServer() async {
    await maybeReadHost(context)?.onSignInResetServer?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    if (!_didPrefill && connection.lastUsername != null) {
      _userController.text = connection.lastUsername!;
      _didPrefill = true;
    }
    final busy = connection.stage == ConnectionStage.connecting;

    return AuthCard(
      maxWidth: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthBadge(icon: Icons.person_rounded),
          const SizedBox(height: 22),
          Text(
            'Sign in to ${connection.serverInfo?.name ?? 'Ariami'}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _userController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onSubmitted: (_) => _submit(connection),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passController,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(connection),
          ),
          if (connection.errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              connection.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE57373), fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: busy ? null : () => _submit(connection),
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
          if (connection.needsTakeoverConfirmation) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed:
                  busy ? null : () => _submit(connection, takeOver: true),
              child: const Text('Sign in here anyway (take over)'),
            ),
          ],
          if (connection.hasPendingPairingCode) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: connection.showRegistration,
              child: const Text('Register instead'),
            ),
          ],
          if (connection.isLocalServer &&
              maybeReadHost(context)?.onSignInResetServer != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _setUpNewServer,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Set up a new server'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (connection.canChooseDifferentServer) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => connection.disconnect(),
              child: const Text('Use a different server'),
            ),
          ],
        ],
      ),
    );
  }
}
