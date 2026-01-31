import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ariami_core/ariami_core.dart';
import '../services/desktop_tailscale_service.dart';
import 'scanning_screen.dart';

/// Global transcoding service instance for desktop app
TranscodingService? _transcodingService;

/// Global artwork service instance for desktop app (thumbnail generation)
ArtworkService? _artworkService;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();

  // Method channel for macOS-specific features (dock icon, App Nap)
  static const _dockChannel = MethodChannel('ariami_desktop/dock');

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
    // Listen for client connection changes
    _httpServer.connectionManager.addListener(_onClientConnectionChanged);
  }

  @override
  void dispose() {
    _httpServer.libraryManager
        .removeScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.removeListener(_onClientConnectionChanged);
    super.dispose();
  }

  void _onLibraryScanComplete() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onClientConnectionChanged() {
    if (mounted) {
      setState(() {
        _connectedClients = _httpServer.connectionManager.clientCount;
      });
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
    if (_musicFolderPath != null &&
        _musicFolderPath!.startsWith('/Volumes/Macintosh HD')) {
      _musicFolderPath =
          _musicFolderPath!.replaceFirst('/Volumes/Macintosh HD', '');
      await prefs.setString('music_folder_path', _musicFolderPath!);
      print('[Dashboard] Fixed bad music folder path: $_musicFolderPath');
    }

    // Configure metadata cache for fast re-scans
    final appDir = await getApplicationSupportDirectory();
    final cachePath = p.join(appDir.path, 'metadata_cache.json');
    _httpServer.libraryManager.setCachePath(cachePath);

    // Initialize transcoding service for quality-based streaming
    // Desktop settings - more resources available than Pi
    if (_transcodingService == null) {
      final transcodingCachePath = p.join(appDir.path, 'transcoded_cache');
      _transcodingService = TranscodingService(
        cacheDirectory: transcodingCachePath,
        maxCacheSizeMB: 4096, // 4GB cache limit for desktop
        maxConcurrency: 2, // Allow 2 concurrent transcodes
        maxDownloadConcurrency: 6, // Higher concurrency for downloads
      );
      _httpServer.setTranscodingService(_transcodingService!);
      print(
          '[Dashboard] Transcoding service initialized at: $transcodingCachePath');

      // Check FFmpeg availability
      _transcodingService!.isFFmpegAvailable().then((available) {
        if (!available) {
          print(
              '[Dashboard] Warning: FFmpeg not found - transcoding will be disabled');
        }
      });
    }

    // Initialize artwork service for thumbnail generation
    if (_artworkService == null) {
      final artworkCachePath = p.join(appDir.path, 'artwork_cache');
      _artworkService = ArtworkService(
        cacheDirectory: artworkCachePath,
        maxCacheSizeMB: 256, // 256MB cache limit for thumbnails
      );
      _httpServer.setArtworkService(_artworkService!);
      print('[Dashboard] Artwork service initialized at: $artworkCachePath');
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
      await _httpServer.start(advertisedIp: ip, port: 8080);

      // Prevent App Nap on macOS to keep server responsive when minimized
      if (Platform.isMacOS) {
        try {
          await _dockChannel.invokeMethod('preventAppNap');
          print('[Dashboard] App Nap prevention enabled');
        } catch (e) {
          print('[Dashboard] Failed to prevent App Nap: $e');
        }
      }

      if (mounted) {
        setState(() {});
      }

      // Navigate to scanning screen if music folder is set and library is empty
      if (_musicFolderPath != null &&
          _musicFolderPath!.isNotEmpty &&
          _httpServer.libraryManager.library == null &&
          mounted) {
        print(
            '[Dashboard] Auto-navigating to scanning screen: $_musicFolderPath');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ScanningScreen(musicFolderPath: _musicFolderPath!),
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
            // backgroundColor: Colors.transparent, // Let theme handle it
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
          builder: (context) =>
              ScanningScreen(musicFolderPath: _musicFolderPath!),
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
              // backgroundColor: Colors.red, // Let theme handle it
            ),
          );
        }
        return;
      }

      try {
        // Start the HTTP server
        await _httpServer.start(advertisedIp: ip, port: 8080);

        // Debug: Check music folder path
        print('[Dashboard] Music folder path: "$_musicFolderPath"');
        print('[Dashboard] Is null: ${_musicFolderPath == null}');
        print('[Dashboard] Is empty: ${_musicFolderPath?.isEmpty ?? true}');

        // Trigger library scan if music folder is set
        if (_musicFolderPath != null && _musicFolderPath!.isNotEmpty) {
          print('[Dashboard] Triggering library scan: $_musicFolderPath');
          // Scan in background, don't await
          _httpServer.libraryManager
              .scanMusicFolder(_musicFolderPath!)
              .then((_) {
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
          print(
              '[Dashboard] ERROR: Music folder path not set! Cannot scan library.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Warning: Music folder not set'),
                duration: Duration(seconds: 3),
                // backgroundColor: Colors.orange, // Let theme handle it
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
              // backgroundColor: Colors.red, // Let theme handle it
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
    bool isActive = true,
  }) {
    // Redesigned to match Premium Dark aesthetic
    // No colored icons unless active (and then white/monochrome)
    final theme = Theme.of(context);
    
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive 
                    ? theme.colorScheme.primary.withOpacity(0.1) 
                    : theme.colorScheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon, 
                size: 24, 
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600, // Semi-bold for high contrast
                      color: isActive ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.7),
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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
    // Use simple B&W logic for server status button
    final isRunning = _httpServer.isRunning;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server Status Section
                  const Text(
                    'Server Status',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Status Cards
                  _buildInfoCard(
                    title: 'Status',
                    value: isRunning ? 'Active' : 'Stopped',
                    icon: isRunning ? Icons.check_circle_rounded : Icons.stop_circle_rounded,
                    isActive: isRunning,
                  ),
                  const SizedBox(height: 12),
                  
                  if (isRunning) ...[
                    _buildInfoCard(
                      title: 'Connected Clients',
                      value: _connectedClients.toString(),
                      icon: Icons.devices_rounded,
                      isActive: _connectedClients > 0,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Main Toggle Button
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _toggleServer,
                      icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(isRunning ? 'Stop Server' : 'Start Server'),
                      style: ElevatedButton.styleFrom(
                        // Bigger button with status-specific styling
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        // Stop: Dark BG with Red Outline/Text. Start: White BG with Black Text.
                        backgroundColor: isRunning ? const Color(0xFF141414) : Colors.white,
                        foregroundColor: isRunning ? Colors.redAccent : Colors.black,
                        side: isRunning 
                            ? const BorderSide(color: Colors.redAccent, width: 2) 
                            : null,
                        elevation: isRunning ? 0 : 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Configuration Section
                  const Text(
                    'Configuration',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Music Folder',
                    value: _musicFolderPath ?? 'Not configured',
                    icon: Icons.folder_rounded,
                    isActive: _musicFolderPath != null,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Tailscale IP',
                    value: _tailscaleIP ?? 'Not connected',
                    icon: Icons.cloud_done_rounded,
                    isActive: _tailscaleIP != null,
                  ),
                  const SizedBox(height: 32),

                  // Library Statistics
                  const Text(
                    'Library Statistics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Albums',
                    value: _httpServer.libraryManager.library?.totalAlbums
                            .toString() ??
                        '0',
                    icon: Icons.album_rounded,
                    isActive: (_httpServer.libraryManager.library?.totalAlbums ?? 0) > 0,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Songs',
                    value: _httpServer.libraryManager.library?.totalSongs
                            .toString() ??
                        '0',
                    icon: Icons.music_note_rounded,
                    isActive: (_httpServer.libraryManager.library?.totalSongs ?? 0) > 0,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Last Scan',
                    value: _httpServer.libraryManager.lastScanTime != null
                        ? _formatDateTime(
                            _httpServer.libraryManager.lastScanTime!)
                        : 'Never',
                    icon: Icons.access_time_rounded,
                    isActive: _httpServer.libraryManager.lastScanTime != null,
                  ),
                  const SizedBox(height: 32),

                  // Quick Actions
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Action Grid
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/folder-selection');
                          },
                          icon: const Icon(Icons.drive_file_move_rounded, size: 20),
                          label: const Text('Change Folder'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF333333)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/connection');
                          },
                          icon: const Icon(Icons.qr_code_rounded, size: 20),
                          label: const Text('Show QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF333333)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _musicFolderPath != null &&
                              _musicFolderPath!.isNotEmpty
                          ? _rescanLibrary
                          : null,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Rescan Library'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF333333)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
