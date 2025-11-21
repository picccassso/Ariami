import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/server/http_server.dart';
import '../services/desktop_tailscale_service.dart';
import 'scanning_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final BmaHttpServer _httpServer = BmaHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();

  String? _musicFolderPath;
  String? _tailscaleIP;
  bool _isLoading = true;
  int _connectedClients = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen for library scan completion
    _httpServer.libraryManager.addScanCompleteListener(_onLibraryScanComplete);
  }

  @override
  void dispose() {
    _httpServer.libraryManager.removeScanCompleteListener(_onLibraryScanComplete);
    super.dispose();
  }

  void _onLibraryScanComplete() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    // Load music folder path from shared preferences
    final prefs = await SharedPreferences.getInstance();
    _musicFolderPath = prefs.getString('music_folder_path');

    // Fix existing bad paths with /Volumes/Macintosh HD prefix
    if (_musicFolderPath != null && _musicFolderPath!.startsWith('/Volumes/Macintosh HD')) {
      _musicFolderPath = _musicFolderPath!.replaceFirst('/Volumes/Macintosh HD', '');
      await prefs.setString('music_folder_path', _musicFolderPath!);
      print('[Dashboard] Fixed bad music folder path: $_musicFolderPath');
    }

    // Get Tailscale IP and server status
    await _updateServerStatus();

    setState(() {
      _isLoading = false;
    });

    // Auto-start server if not already running
    if (!_httpServer.isRunning) {
      await _autoStartServer();
    }
  }

  /// Automatically start server on app launch
  Future<void> _autoStartServer() async {
    final ip = await _tailscaleService.getTailscaleIp();
    if (ip == null) {
      print('[Dashboard] Auto-start skipped: Tailscale not connected');
      return;
    }

    try {
      print('[Dashboard] Auto-starting server on $ip:8080');
      await _httpServer.start(tailscaleIp: ip, port: 8080);

      if (mounted) {
        setState(() {});
      }

      // Navigate to scanning screen if music folder is set and library is empty
      if (_musicFolderPath != null &&
          _musicFolderPath!.isNotEmpty &&
          _httpServer.libraryManager.library == null &&
          mounted) {
        print('[Dashboard] Auto-navigating to scanning screen: $_musicFolderPath');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanningScreen(musicFolderPath: _musicFolderPath!),
          ),
        );
      }
    } catch (e) {
      print('[Dashboard] Auto-start server failed: $e');
    }
  }

  Future<void> _updateServerStatus() async {
    // Get Tailscale IP
    final ip = await _tailscaleService.getTailscaleIp();

    // Get connected clients count
    final clientCount = _httpServer.connectionManager.clientCount;

    setState(() {
      _tailscaleIP = ip;
      _connectedClients = clientCount;
    });
  }

  Future<void> _rescanLibrary() async {
    if (_musicFolderPath == null || _musicFolderPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a music folder first'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    print('[Dashboard] Manual rescan triggered: $_musicFolderPath');

    // Navigate to scanning screen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanningScreen(musicFolderPath: _musicFolderPath!),
        ),
      );
    }
  }

  Future<void> _toggleServer() async {
    if (_httpServer.isRunning) {
      // Stop server
      await _httpServer.stop();
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
      final ip = await _tailscaleService.getTailscaleIp();
      if (ip == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot start server: Tailscale not connected'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      try {
        // Start the HTTP server
        await _httpServer.start(tailscaleIp: ip, port: 8080);

        // Debug: Check music folder path
        print('[Dashboard] Music folder path: "$_musicFolderPath"');
        print('[Dashboard] Is null: ${_musicFolderPath == null}');
        print('[Dashboard] Is empty: ${_musicFolderPath?.isEmpty ?? true}');

        // Trigger library scan if music folder is set
        if (_musicFolderPath != null && _musicFolderPath!.isNotEmpty) {
          print('[Dashboard] Triggering library scan: $_musicFolderPath');
          // Scan in background, don't await
          _httpServer.libraryManager.scanMusicFolder(_musicFolderPath!).then((_) {
            print('[Dashboard] Library scan completed');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Music library scan completed'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }).catchError((e) {
            print('[Dashboard] Library scan error: $e');
          });
        } else {
          print('[Dashboard] ERROR: Music folder path not set! Cannot scan library.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Warning: Music folder not set'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Server started'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start server: $e'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    await _updateServerStatus();
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
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
                    value: _httpServer.isRunning ? 'Running' : 'Stopped',
                    icon: _httpServer.isRunning ? Icons.check_circle : Icons.cancel,
                    valueColor: _httpServer.isRunning ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 16),
                  if (_httpServer.isRunning)
                    _buildInfoCard(
                      title: 'Connected Clients',
                      value: _connectedClients.toString(),
                      icon: Icons.devices,
                      valueColor: _connectedClients > 0 ? Colors.green : Colors.grey,
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _toggleServer,
                      icon: Icon(_httpServer.isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_httpServer.isRunning ? 'Stop Server' : 'Start Server'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: _httpServer.isRunning ? Colors.red : Colors.green,
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
                    value: _tailscaleIP ?? 'Not connected',
                    icon: Icons.cloud,
                  ),
                  const SizedBox(height: 32),

                  // Library Statistics
                  const Text(
                    'Library Statistics',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Albums',
                    value: _httpServer.libraryManager.library?.totalAlbums.toString() ?? '0',
                    icon: Icons.album,
                    valueColor: (_httpServer.libraryManager.library?.totalAlbums ?? 0) > 0
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Songs',
                    value: _httpServer.libraryManager.library?.totalSongs.toString() ?? '0',
                    icon: Icons.music_note,
                    valueColor: (_httpServer.libraryManager.library?.totalSongs ?? 0) > 0
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Last Scan',
                    value: _httpServer.libraryManager.lastScanTime != null
                        ? _formatDateTime(_httpServer.libraryManager.lastScanTime!)
                        : 'Never',
                    icon: Icons.access_time,
                  ),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _musicFolderPath != null && _musicFolderPath!.isNotEmpty
                          ? _rescanLibrary
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Rescan Music Library'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
