import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../services/server_address_parser.dart';
import '../theme/player_theme.dart';
import '../widgets/auth_card.dart';

/// Connects the client player to a remote Ariami server via LAN auto-discovery
/// (when the host supports it) or manual address entry, with an optional
/// invite code for creating a new account.
class ConnectView extends StatefulWidget {
  const ConnectView({super.key});

  @override
  State<ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<ConnectView> {
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();
  final List<DiscoveredLanServer> _discovered = <DiscoveredLanServer>[];

  StreamSubscription<DiscoveredLanServer>? _discoverySub;
  bool _didPrefill = false;
  bool _discoveryStarted = false;
  bool _isScanning = false;
  bool _showInviteField = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_discoveryStarted) {
      _discoveryStarted = true;
      _startDiscovery();
    }
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startDiscovery() {
    final discover = maybeReadHost(context)?.discoverLanServers;
    if (discover == null) return;

    _discoverySub?.cancel();
    setState(() {
      _discovered.clear();
      _isScanning = true;
    });

    _discoverySub = discover().listen(
      (server) {
        if (!mounted) return;
        final exists = _discovered.any(
          (s) => s.host == server.host && s.port == server.port,
        );
        if (!exists) setState(() => _discovered.add(server));
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  String _formatPrefill(ConnectionController connection) {
    final host = connection.pendingHost!;
    final scheme = connection.pendingScheme;
    final port = connection.pendingPort;
    if (scheme == 'https') {
      return port == 443 ? 'https://$host' : 'https://$host:$port';
    }
    return port == ParsedServerAddress.defaultPort ? host : '$host:$port';
  }

  void _connectTo(
    ConnectionController connection, {
    required String host,
    required int port,
    String scheme = 'http',
  }) {
    final inviteCode = _showInviteField ? _codeController.text.trim() : '';
    if (inviteCode.isNotEmpty) {
      connection.pairWithServer(
        host,
        port,
        inviteCode,
        scheme: scheme,
        action: PairingAction.register,
      );
      return;
    }
    connection.connectRemote(host, port, scheme: scheme);
  }

  void _submitManual(ConnectionController connection) {
    final parsed = ParsedServerAddress.tryParse(_addressController.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid server address (e.g. 192.168.1.50).'),
        ),
      );
      return;
    }
    _connectTo(
      connection,
      host: parsed.host,
      port: parsed.port,
      scheme: parsed.scheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final hasDiscovery = maybeReadHost(context)?.discoverLanServers != null;
    if (!_didPrefill && connection.pendingHost != null) {
      _addressController.text = _formatPrefill(connection);
      _didPrefill = true;
    }
    final hasInviteCode =
        _showInviteField && _codeController.text.trim().isNotEmpty;

    return AuthCard(
      maxWidth: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthBadge(icon: Icons.library_music_rounded),
          const SizedBox(height: 20),
          Text(
            'Connect to your Ariami server',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            hasDiscovery
                ? 'Choose a server on your network, or enter an address '
                    '(LAN, Tailscale, or domain).'
                : 'Enter the address of your Ariami server (LAN, Tailscale, '
                    'or domain).',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (connection.errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: connection.errorMessage!),
          ],
          if (hasDiscovery) ...[
            const SizedBox(height: 20),
            _buildDiscoverySection(context, connection),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _addressController,
            autofocus: !hasDiscovery,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: '192.168.1.50 or 100.x.x.x (Tailscale)',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            onSubmitted: (_) => _submitManual(connection),
          ),
          const SizedBox(height: 8),
          if (!_showInviteField)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showInviteField = true),
                icon: const Icon(Icons.vpn_key_outlined, size: 17),
                label: const Text('New to this server? Enter an invite code'),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            TextField(
              controller: _codeController,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              maxLength: 9,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Invite code (for new accounts)',
                hintText: '4F9K-2QX7',
                helperText:
                    'From the server owner (Settings → Connect a device or CLI)',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Hide invite code',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    _showInviteField = false;
                    _codeController.clear();
                  }),
                ),
                counterText: '',
              ),
              onSubmitted: (_) => _submitManual(connection),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: () => _submitManual(connection),
              child: Text(
                hasInviteCode ? 'Continue to Create Account' : 'Connect',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySection(
    BuildContext context,
    ConnectionController connection,
  ) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_isScanning) ...[
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(Icons.wifi_rounded, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _isScanning
                      ? 'Looking for servers on your network…'
                      : _discovered.isEmpty
                          ? 'No servers found on this Wi-Fi'
                          : 'Servers on your network',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (!_isScanning)
                TextButton(
                  onPressed: _startDiscovery,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Rescan', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (_discovered.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final server in _discovered)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: colors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _connectTo(
                      connection,
                      host: server.host,
                      port: server.port,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.dns_rounded,
                            size: 18,
                            color: colors.textPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  server.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  server.address,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
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
