import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/server_address_parser.dart';
import '../widgets/auth_card.dart';

/// First-run mobile-style pairing: server address plus owner-issued code.
class ConnectView extends StatefulWidget {
  const ConnectView({super.key});

  @override
  State<ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<ConnectView> {
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();
  bool _didPrefill = false;

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    if (!_didPrefill && connection.pendingHost != null) {
      _addressController.text = connection.pendingPort == 8080
          ? connection.pendingHost!
          : '${connection.pendingHost}:${connection.pendingPort}';
      _didPrefill = true;
    }
    return AuthCard(
      maxWidth: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthBadge(icon: Icons.library_music_rounded),
          const SizedBox(height: 22),
          Text(
            'Connect to your Ariami server',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the server address and the one-time pairing code shown '
            'by the CLI or server dashboard.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (connection.errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: connection.errorMessage!),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _addressController,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Server IP address',
              hintText: '192.168.1.50 or 192.168.1.50:8080',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: '4F9K-2QX7',
              prefixIcon: Icon(Icons.vpn_key_outlined),
              counterText: '',
            ),
            onSubmitted: (_) => _pair(
              connection,
              PairingAction.login,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pair(connection, PairingAction.login),
                    child: const Text('Login'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _pair(connection, PairingAction.register),
                    child: const Text('Register'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pair(ConnectionController connection, PairingAction action) {
    final parsed = ParsedServerAddress.tryParse(_addressController.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid server IP address.')),
      );
      return;
    }
    connection.pairWithServer(
      parsed.host,
      parsed.port,
      _codeController.text,
      action: action,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFE57373), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Color(0xFFE57373), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
