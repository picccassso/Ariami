import 'package:flutter/material.dart';

import '../../models/server_info.dart';
import '../../services/api/api_client.dart';
import '../../services/api/connection_service.dart';
import '../../utils/server_address_parser.dart';
import '../../utils/setup_error_messages.dart';
import 'server_connection_router.dart';

/// Manual server-address entry as a fallback for QR scanning.
///
/// Lets the user type the server address directly (e.g. `192.168.1.50:8080` or
/// `http://100.x.y.z:8080`) when a QR code isn't available. We discover the
/// server's auth/legacy state from the public `/api/server-info` endpoint, then
/// hand off to the same login / register / connect flow the QR scanner uses.
class ManualServerEntryScreen extends StatefulWidget {
  const ManualServerEntryScreen({super.key});

  @override
  State<ManualServerEntryScreen> createState() =>
      _ManualServerEntryScreenState();
}

class _ManualServerEntryScreenState extends State<ManualServerEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final ConnectionService _connectionService = ConnectionService();
  bool _isConnecting = false;
  bool _showInviteField = false;
  String? _errorMessage;

  @override
  void dispose() {
    _addressController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  /// Canonical form the server stores codes in: uppercase, alphanumerics only
  /// (so `4f9k-2qx7` and `4F9K2QX7` both work).
  String _normalizeInviteCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final parsed = ParsedServerAddress.tryParse(_addressController.text);
    if (parsed == null) {
      setState(() {
        _errorMessage = 'Enter a valid address like 192.168.1.50:8080';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // Connect via exactly the typed address: leave lanServer/tailscaleServer
      // null so endpoint resolution won't swap to an unreachable LAN IP. The
      // real endpoints are discovered during post-connection hydration.
      final bootstrap = ServerInfo(
        server: parsed.host,
        port: parsed.port,
        publicOrigin: parsed.publicOrigin,
        name: parsed.host,
        version: '',
      );

      // Discover auth/legacy state (and friendly name/version) from the public
      // server-info endpoint so we can route like the QR flow does.
      final apiClient = ApiClient(serverInfo: bootstrap);
      final discovered =
          await apiClient.getServerInfo().whenComplete(apiClient.close);

      // On a server that already has users, registration needs an owner-issued
      // invite code; attach it so the user lands on account creation.
      final serverHasUsers = discovered.authRequired && !discovered.legacyMode;
      final inviteCode = _normalizeInviteCode(_inviteCodeController.text);
      final hasInviteCode = serverHasUsers && inviteCode.isNotEmpty;

      final serverInfo = ServerInfo(
        server: parsed.host,
        port: parsed.port,
        publicOrigin: parsed.publicOrigin ?? discovered.publicOrigin,
        name: discovered.name,
        version: discovered.version,
        authRequired: discovered.authRequired,
        legacyMode: discovered.legacyMode,
        downloadLimits: discovered.downloadLimits,
        registrationToken: hasInviteCode ? inviteCode : null,
      );

      if (!mounted) return;

      if (hasInviteCode) {
        // Go straight to account creation with the invite code.
        Navigator.pushReplacementNamed(
          context,
          '/auth/register',
          arguments: serverInfo,
        );
        return;
      }

      await routeForServerInfo(context, serverInfo, _connectionService);
    } catch (e) {
      // Entered address and invite code stay in their controllers so the user
      // can correct and retry without retyping.
      if (mounted) {
        setState(() {
          _errorMessage = describeSetupConnectError(
            e,
            address: '${parsed.host}:${parsed.port}',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Manual entry'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dns_rounded,
                    size: 100,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Connect manually',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your server address. You can include or omit '
                    'http:// or https://. Secure public servers default to '
                    'port 443; private servers default to 8080.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 32),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Address field
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'Server address',
                      hintText: '192.168.1.50:8080',
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onFieldSubmitted: (_) => _handleConnect(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the server address';
                      }
                      return null;
                    },
                  ),

                  // Optional invite code (to create a new account on a server
                  // that already has users). Hidden behind a toggle to keep the
                  // common path clean.
                  if (!_showInviteField)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showInviteField = true),
                        icon: const Icon(Icons.vpn_key_outlined, size: 18),
                        label: const Text('Have an invite code?'),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _inviteCodeController,
                      decoration: InputDecoration(
                        labelText: 'Invite code (optional)',
                        hintText: '4F9K-2QX7',
                        helperText:
                            'From the server owner, to create a new account',
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => _handleConnect(),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Connect button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isConnecting ? null : _handleConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        elevation: 8,
                        shadowColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _isConnecting
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Text(
                              'Connect',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
