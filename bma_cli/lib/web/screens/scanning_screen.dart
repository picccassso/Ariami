import 'dart:async';
import 'package:flutter/material.dart';
import '../services/web_setup_service.dart';

class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> {
  final WebSetupService _setupService = WebSetupService();

  double _progress = 0.0;
  String _statusMessage = 'Initializing scan...';
  int _songsFound = 0;
  int _albumsFound = 0;
  bool _isScanning = true;
  bool _isComplete = false;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startScanning() async {
    try {
      // Trigger the scan on the backend
      final success = await _setupService.startScan();

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start scan')),
          );
          Navigator.pushReplacementNamed(context, '/folder-selection');
        }
        return;
      }

      // Start polling for scan status
      _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _updateScanStatus();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting scan: $e')),
        );
        Navigator.pushReplacementNamed(context, '/folder-selection');
      }
    }
  }

  Future<void> _updateScanStatus() async {
    try {
      final status = await _setupService.getScanStatus();

      if (!mounted) return;

      setState(() {
        _isScanning = status['isScanning'] as bool? ?? false;
        _progress = (status['progress'] as num?)?.toDouble() ?? 0.0;
        _songsFound = status['songsFound'] as int? ?? 0;
        _albumsFound = status['albumsFound'] as int? ?? 0;
        _statusMessage = status['currentStatus'] as String? ?? 'Scanning...';
        _isComplete = !_isScanning && _progress >= 1.0;
      });

      // If scan is complete, stop polling and navigate
      if (_isComplete) {
        _pollTimer?.cancel();

        // Mark setup as complete
        await _setupService.markSetupComplete();

        // Trigger transition to background mode
        // This spawns a background daemon and shuts down the foreground server
        // The browser will briefly disconnect then auto-reconnect
        print('Triggering transition to background mode...');
        final result = await _setupService.transitionToBackground();
        print('Transition result: $result');

        // Wait for background server to be ready
        // - 500ms for foreground shutdown delay
        // - time for port to be released
        // - background server startup and potential retry
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/qr-code');
        }
      }
    } catch (e) {
      print('Error updating scan status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning Library'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isComplete)
                const CircularProgressIndicator()
              else
                const Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Colors.green,
                ),
              const SizedBox(height: 32),
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 400,
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Icon(Icons.music_note, size: 40),
                              const SizedBox(height: 8),
                              Text(
                                '$_songsFound',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Songs',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Icon(Icons.album, size: 40),
                              const SizedBox(height: 8),
                              Text(
                                '$_albumsFound',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Albums',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_isComplete) ...{
                const SizedBox(height: 32),
                const Text(
                  'Redirecting to connection setup...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
