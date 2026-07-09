import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api/connection_service.dart';
import '../../utils/qr_payload_parser.dart';
import '../../utils/setup_error_messages.dart';
import 'server_connection_router.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final ConnectionService _connectionService = ConnectionService();
  MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;
  bool _torchEnabled = false;
  String? _errorMessage;

  // After a failed scan the camera restarts while the same QR code is still in
  // frame, which would re-trigger the identical failure in a tight loop. Skip
  // re-processing the same payload for a short cooldown.
  String? _lastFailedCode;
  DateTime? _lastFailureAt;
  static const Duration _failedScanCooldown = Duration(seconds: 4);

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  bool _isInFailureCooldown(String code) {
    final failedAt = _lastFailureAt;
    return _lastFailedCode == code &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _failedScanCooldown;
  }

  Future<void> _processQRCode(String code) async {
    if (_isProcessing || _isInFailureCooldown(code)) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Stop the camera to prevent multiple scans while connecting.
      await _stopCameraSafely();

      final result = QrPayloadParser.parse(code);
      if (!result.isValid) {
        _recordScanFailure(code, result.error!);
        await _startCameraSafely();
        return;
      }

      try {
        if (!mounted) return;
        await routeForServerInfo(context, result.serverInfo!,
            _connectionService);
      } catch (e) {
        // Connection to a validly-encoded server failed (offline, timeout,
        // wrong network...). Surface why instead of silently rescanning.
        _recordScanFailure(
          code,
          describeSetupConnectError(
            e,
            address: result.serverInfo!.server,
          ),
        );
        await _startCameraSafely();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _recordScanFailure(String code, String message) {
    _lastFailedCode = code;
    _lastFailureAt = DateTime.now();
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  Future<void> _stopCameraSafely() async {
    try {
      await _cameraController.stop();
    } catch (_) {
      // Already stopped/disposed - nothing to do.
    }
  }

  Future<void> _startCameraSafely() async {
    if (!mounted) return;
    try {
      await _cameraController.start();
    } catch (_) {
      // Start can fail if the screen is being torn down or permission was
      // revoked mid-session; the errorBuilder handles the persistent case.
    }
  }

  /// Recreate the controller so MobileScanner re-runs its permission check
  /// (e.g. after the user grants camera access in system settings).
  void _retryCamera() {
    final oldController = _cameraController;
    setState(() {
      _cameraController = MobileScannerController();
      _errorMessage = null;
    });
    oldController.dispose();
  }

  Future<void> _openManualEntry() async {
    // Pause scanning while manual entry is on top; otherwise the camera keeps
    // detecting codes behind the pushed screen.
    await _stopCameraSafely();
    if (!mounted) return;
    await Navigator.pushNamed(context, '/setup/manual');
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
    });
    await _startCameraSafely();
  }

  void _toggleTorch() {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    try {
      _cameraController.toggleTorch();
    } catch (_) {
      // No torch on this device - keep the UI state harmless.
    }
  }

  Widget _buildCameraError(
      BuildContext context, MobileScannerException error) {
    final isPermissionError =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = isPermissionError
        ? 'Camera access needed'
        : 'Camera unavailable';
    final message = isPermissionError
        ? 'Ariami needs the camera to scan the pairing QR code shown by your '
            'desktop server. Allow camera access, or type the server address '
            'instead.'
        : 'The camera couldn\'t be started on this device. You can type the '
            'server address instead.';

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermissionError
                  ? Icons.no_photography_outlined
                  : Icons.videocam_off_outlined,
              size: 72,
              color: Colors.white70,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (isPermissionError)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
              ),
            if (isPermissionError) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Try camera again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
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
            controller: _cameraController,
            errorBuilder: _buildCameraError,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final value = barcode.rawValue;
                if (value != null && !_isProcessing) {
                  _processQRCode(value);
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

          // Status: connecting spinner, error, or instructions
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
                else if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                            ),
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

          // Manual entry fallback (for when a QR code isn't available)
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _openManualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Manual entry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
