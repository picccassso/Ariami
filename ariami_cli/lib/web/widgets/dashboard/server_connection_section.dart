import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../ui/info_row.dart';
import '../ui/section.dart';

/// Where clients reach this server, and when those addresses were last read.
class ServerConnectionSection extends StatefulWidget {
  const ServerConnectionSection({
    super.key,
    this.lanServer,
    this.lanServerAlias,
    this.tailscaleServer,
    this.tailscaleServerAlias,
    this.lastUpdatedLabel,
    required this.isRefreshing,
    required this.onRefreshAddresses,
    this.isAdmin = false,
    this.onUpdateAliases,
  });

  final String? lanServer;
  final String? lanServerAlias;
  final String? tailscaleServer;
  final String? tailscaleServerAlias;
  final String? lastUpdatedLabel;
  final bool isRefreshing;
  final VoidCallback onRefreshAddresses;
  final bool isAdmin;
  final Future<void> Function({String? lanAlias, String? tailscaleAlias})?
      onUpdateAliases;

  @override
  State<ServerConnectionSection> createState() =>
      _ServerConnectionSectionState();
}

class _ServerConnectionSectionState extends State<ServerConnectionSection> {
  bool _revealLan = false;
  bool _revealTailscale = false;

  Future<void> _showRenameDialog({
    required BuildContext context,
    required String title,
    required String hint,
    required String? currentAlias,
    required Future<void> Function(String? newAlias) onSave,
  }) async {
    final controller = TextEditingController(text: currentAlias ?? '');
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceBlack,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                side: const BorderSide(color: AppTheme.borderGrey),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set a friendly display name to hide the raw IP address in dashboards and clients.',
                    style: AppTheme.meta,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLength: 40,
                    autofocus: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall),
                        borderSide:
                            const BorderSide(color: AppTheme.borderGrey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall),
                        borderSide:
                            const BorderSide(color: AppTheme.borderGrey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                    onChanged: (text) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                if (currentAlias != null && currentAlias.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await onSave(null);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final trimmed = controller.text.trim();
                    if (trimmed.length > 40) {
                      setDialogState(() => errorText = 'Max 40 characters');
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    await onSave(trimmed.isEmpty ? null : trimmed);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.pureBlack,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEndpointControls({
    required bool hasAlias,
    required bool isRevealed,
    required VoidCallback onToggleReveal,
    required VoidCallback? onRename,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasAlias)
          IconButton(
            icon: Icon(
              isRevealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: isRevealed ? 'Hide raw address' : 'Reveal raw address',
            onPressed: onToggleReveal,
          ),
        if (onRename != null) ...[
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: Text(hasAlias ? 'Rename' : 'Set alias'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lan = widget.lanServer;
    final tailscale = widget.tailscaleServer;
    final lanAlias = widget.lanServerAlias;
    final tailscaleAlias = widget.tailscaleServerAlias;

    final hasLan = lan != null && lan.isNotEmpty;
    final hasLanAlias = lanAlias != null && lanAlias.trim().isNotEmpty;
    final lanDisplayValue = !hasLan
        ? 'Not connected'
        : ((hasLanAlias && !_revealLan) ? lanAlias! : lan!);

    final hasTailscale = tailscale != null && tailscale.isNotEmpty;
    final hasTailscaleAlias =
        tailscaleAlias != null && tailscaleAlias.trim().isNotEmpty;
    final tailscaleDisplayValue = !hasTailscale
        ? 'Not connected'
        : ((hasTailscaleAlias && !_revealTailscale)
            ? tailscaleAlias!
            : tailscale!);

    final canEdit = widget.isAdmin && widget.onUpdateAliases != null;

    return Section(
      title: 'Connection',
      description: 'Keep Ariami on your LAN, Tailscale or VPN — never expose '
          'it directly to the internet.',
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            InfoRow(
              icon: Icons.router_rounded,
              label: 'Local network',
              value: lanDisplayValue,
              subtitle: 'For devices on the same Wi-Fi or wired network.',
              isActive: hasLan,
              valueIsPath: hasLan && (!hasLanAlias || _revealLan),
              trailing: hasLan
                  ? _buildEndpointControls(
                      hasAlias: hasLanAlias,
                      isRevealed: _revealLan,
                      onToggleReveal: () =>
                          setState(() => _revealLan = !_revealLan),
                      onRename: canEdit
                          ? () => _showRenameDialog(
                                context: context,
                                title: 'Rename Local Network Alias',
                                hint: 'e.g. Home LAN',
                                currentAlias: lanAlias,
                                onSave: (newAlias) => widget.onUpdateAliases!(
                                  lanAlias: newAlias,
                                  tailscaleAlias: tailscaleAlias,
                                ),
                              )
                          : null,
                    )
                  : null,
            ),
            const CardDivider(),
            InfoRow(
              icon: Icons.cloud_done_rounded,
              label: 'Tailscale',
              value: tailscaleDisplayValue,
              subtitle: hasTailscale
                  ? 'For your signed-in devices when away from home.'
                  : 'Optional. Install Tailscale to reach Ariami away from '
                      'home.',
              isActive: hasTailscale,
              valueIsPath:
                  hasTailscale && (!hasTailscaleAlias || _revealTailscale),
              trailing: hasTailscale
                  ? _buildEndpointControls(
                      hasAlias: hasTailscaleAlias,
                      isRevealed: _revealTailscale,
                      onToggleReveal: () => setState(
                          () => _revealTailscale = !_revealTailscale),
                      onRename: canEdit
                          ? () => _showRenameDialog(
                                context: context,
                                title: 'Rename Tailscale Alias',
                                hint: 'e.g. Away Tailscale',
                                currentAlias: tailscaleAlias,
                                onSave: (newAlias) => widget.onUpdateAliases!(
                                  lanAlias: lanAlias,
                                  tailscaleAlias: newAlias,
                                ),
                              )
                          : null,
                    )
                  : null,
            ),
            const CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.lastUpdatedLabel == null
                          ? 'Addresses are re-read automatically.'
                          : 'Addresses updated ${widget.lastUpdatedLabel}',
                      style: AppTheme.meta,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: widget.isRefreshing
                        ? null
                        : widget.onRefreshAddresses,
                    icon: widget.isRefreshing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 17),
                    label:
                        Text(widget.isRefreshing ? 'Refreshing…' : 'Refresh'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
