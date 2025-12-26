import 'package:flutter/material.dart';
import '../../models/server_info.dart';

enum ConnectionStatus { connected, connecting, offline, error }

class ConnectionStatusCard extends StatelessWidget {
  final ConnectionStatus status;
  final ServerInfo? serverInfo;
  final String? errorMessage;
  final DateTime? lastSyncTime;
  final VoidCallback? onRetry;

  const ConnectionStatusCard({
    super.key,
    required this.status,
    this.serverInfo,
    this.errorMessage,
    this.lastSyncTime,
    this.onRetry,
  });

  Color _getStatusColor() {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.amber;
      case ConnectionStatus.offline:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  String _getStatusText() {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.error:
        return 'Connection Error';
    }
  }

  String _getLastSyncText() {
    if (lastSyncTime == null) return 'Never synced';

    final now = DateTime.now();
    final diff = now.difference(lastSyncTime!);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status indicator row
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusColor(),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Server info
            if (serverInfo != null) ...[
              Text(
                'Connected to: ${serverInfo!.name}',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Server: ${serverInfo!.server}:${serverInfo!.port}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Last sync time
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Last synced: ${_getLastSyncText()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),

            // Error message if present
            if (status == ConnectionStatus.error && errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.red,
                  ),
                ),
              ),
            ],

            // Retry button if error or offline
            if ((status == ConnectionStatus.error ||
                    status == ConnectionStatus.offline) &&
                onRetry != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
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
