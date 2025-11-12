import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/server/server_manager.dart';
import '../services/app_state_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ServerManager _serverManager = ServerManager();
  final AppStateService _appStateService = AppStateService();
  String? _musicFolderPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    // Initialize app state service
    await _appStateService.initialize();

    // Load music folder path from shared preferences
    final prefs = await SharedPreferences.getInstance();
    _musicFolderPath = prefs.getString('music_folder_path');

    // Auto-start server if configured
    await _autoStartServerIfNeeded();

    setState(() {
      _isLoading = false;
    });
  }

  /// Auto-start server if user preference is enabled
  Future<void> _autoStartServerIfNeeded() async {
    // Only auto-start if:
    // 1. Setup is complete
    // 2. Auto-start preference is enabled
    // 3. Server is not already running
    if (_appStateService.shouldAutoStartServer() && !_serverManager.isRunning) {
      debugPrint('[Dashboard] Auto-starting server');

      final success = await _serverManager.startServer();

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Server started automatically on ${_serverManager.tailscaleIp}:${_serverManager.port}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      } else if (!success && mounted) {
        debugPrint('[Dashboard] Auto-start failed');
        // Don't show error - user can manually start if needed
      }
    }
  }

  Future<void> _toggleServer() async {
    if (_serverManager.isRunning) {
      // Stop server
      await _serverManager.stopServer();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Start server
      final success = await _serverManager.startServer();

      if (success) {
        setState(() {});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Server started on ${_serverManager.tailscaleIp}:${_serverManager.port}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start server. Check Tailscale connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BMA Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server Status Section
                  const Text(
                    'Server Status',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Status',
                    value: _serverManager.isRunning ? 'Running' : 'Stopped',
                    icon: _serverManager.isRunning ? Icons.check_circle : Icons.cancel,
                    valueColor: _serverManager.isRunning ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _toggleServer,
                      icon: Icon(_serverManager.isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_serverManager.isRunning ? 'Stop Server' : 'Start Server'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: _serverManager.isRunning ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Configuration Section
                  const Text(
                    'Configuration',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Music Folder',
                    value: _musicFolderPath ?? 'Not configured',
                    icon: Icons.folder,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Tailscale IP',
                    value: _serverManager.tailscaleIp ?? 'Not connected',
                    icon: Icons.cloud,
                  ),
                  if (_serverManager.isRunning) ...[
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      title: 'Server Address',
                      value: 'http://${_serverManager.tailscaleIp}:${_serverManager.port}',
                      icon: Icons.link,
                      valueColor: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      title: 'Connected Clients',
                      value: '${_serverManager.server.connectionManager.clientCount}',
                      icon: Icons.devices,
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Quick Actions
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/folder-selection');
                          },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Change Folder'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/connection');
                          },
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Show QR Code'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
