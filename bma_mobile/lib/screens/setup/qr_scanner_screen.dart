import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../services/app_state_service.dart';
import '../../services/api/connection_service.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _processQRCode(String code) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Parse JSON data
      final data = jsonDecode(code);

      // Validate required fields
      if (!data.containsKey('server') || !data.containsKey('port')) {
        _showError('Invalid QR code format. Please scan a BMA QR code.');
        return;
      }

      // Extract connection details
      final server = data['server'] as String;
      final port = data['port'] as int;

      // Get services
      final connectionService = Provider.of<ConnectionService>(
        context,
        listen: false,
      );
      final appStateService = Provider.of<AppStateService>(
        context,
        listen: false,
      );

      // Get or create device ID and name from AppStateService
      final deviceId = await appStateService.getOrCreateDeviceId();
      final deviceName = await appStateService.getOrCreateDeviceName();

      // Attempt connection
      final connected = await connectionService.connect(
        ip: server,
        port: port,
        deviceId: deviceId,
        deviceName: deviceName,
      );

      if (connected) {
        // Save server info to AppStateService
        await appStateService.saveServerInfo(
          ip: server,
          port: port,
          sessionId: connectionService.serverInfo?.sessionId,
        );

        // Success! Navigate to permissions screen
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/setup/permissions');
        }
      } else {
        _showError(connectionService.errorMessage ??
            'Could not connect to server. Check your Tailscale connection.');
      }
    } catch (e) {
      if (e is FormatException) {
        _showError('Please scan a BMA QR code');
      } else {
        _showError('Network error. Check your Tailscale connection.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<String> _getDeviceId() async {
    // Generate or retrieve a persistent device ID
    // For simplicity, using a combination of platform info
    return '${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _getDeviceName() async {
    // Get device name - this could be enhanced to get actual device name
    if (Platform.isIOS) {
      return 'iPhone';
    } else if (Platform.isAndroid) {
      return 'Android Device';
    } else {
      return 'Mobile Device';
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 3),
      ),
    );

    setState(() {
      _isProcessing = false;
    });
  }

  void _toggleTorch() {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    cameraController.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
            tooltip: 'Toggle Flash',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null && !_isProcessing) {
                  _processQRCode(barcode.rawValue!);
                  break;
                }
              }
            },
          ),

          // Scanning frame overlay
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_isProcessing)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Connecting...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Position the QR code within the frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
