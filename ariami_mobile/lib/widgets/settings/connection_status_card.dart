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

  Color _getStatusColor(bool isDark) {
    switch (status) {
      case ConnectionStatus.connected:
        return isDark ? Colors.white : Colors.black;
      case ConnectionStatus.connecting:
        return Colors.white;
      case ConnectionStatus.offline:
        return isDark ? Colors.grey[800]! : Colors.grey[300]!;
      case ConnectionStatus.error:
        return const Color(0xFFFF4B4B);
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator row
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getStatusColor(isDark),
                  boxShadow: status == ConnectionStatus.connected 
                    ? [BoxShadow(color: (isDark ? Colors.white : Colors.black).withOpacity(0.5), blurRadius: 8)] 
                    : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _getStatusText().toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Server info
          if (serverInfo != null) ...[
            Text(
              serverInfo!.name.toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${serverInfo!.server}:${serverInfo!.port}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Last sync time
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: isDark ? Colors.grey[700] : Colors.grey[400],
              ),
              const SizedBox(width: 8),
              Text(
                'LAST SYNCED: ${_getLastSyncText().toUpperCase()}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.grey[700] : Colors.grey[400],
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          // Error message if present
          if (status == ConnectionStatus.error && errorMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B4B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF4B4B).withOpacity(0.2),
                ),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFF4B4B),
                ),
              ),
            ),
          ],

          // Retry button if error or offline
          if ((status == ConnectionStatus.error ||
                  status == ConnectionStatus.offline) &&
              onRetry != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'RETRY CONNECTION',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
