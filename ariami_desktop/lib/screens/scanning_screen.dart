import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ariami_core/ariami_core.dart';

import '../onboarding/onboarding_copy.dart';
import '../onboarding/setup_scaffold.dart';

class ScanningScreen extends StatefulWidget {
  final String musicFolderPath;
  final String?
  nextRoute; // If set, navigates forward to this route instead of popping

  const ScanningScreen({
    super.key,
    required this.musicFolderPath,
    this.nextRoute,
  });

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  String _status = 'Preparing scan...';
  bool _isComplete = false;
  int _albumCount = 0;
  int _songCount = 0;
  int _scannedFileCount = 0;
  int _skippedFileCount = 0;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _status = 'Scanning media library...';
    });

    try {
      // Configure metadata cache for fast re-scans
      final appDir = await getApplicationSupportDirectory();
      final cachePath = p.join(appDir.path, 'metadata_cache.json');
      _httpServer.libraryManager.setCachePath(cachePath);

      await _httpServer.libraryManager.scanMusicFolder(widget.musicFolderPath);

      final diagnostics = _httpServer.libraryManager.latestScanDiagnostics;
      if (!mounted) return;
      setState(() {
        _isComplete = true;
        _albumCount = _httpServer.libraryManager.library?.totalAlbums ?? 0;
        _songCount = _httpServer.libraryManager.library?.totalSongs ?? 0;
        _scannedFileCount = _httpServer.libraryManager.latestScannedFileCount;
        _skippedFileCount = diagnostics.skippedFileCount;
        _status = diagnostics.skippedFileCount > 0
            ? 'Scan complete with ${diagnostics.skippedFileCount} skipped file(s)'
            : 'Scan complete!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Scan failed: $e';
      });

      // Wait then navigate
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        if (widget.nextRoute != null) {
          Navigator.pushReplacementNamed(context, widget.nextRoute!);
        } else {
          Navigator.pop(context, false);
        }
      }
    }
  }

  void _continueAfterScan() {
    if (widget.nextRoute != null) {
      Navigator.pushReplacementNamed(context, widget.nextRoute!);
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No back affordance: abandoning an active scan would leave callers
    // waiting. Completion remains here until the user explicitly continues.
    return SetupScreenScaffold(
      helpTopic: OnboardingCopy.scanning,
      allowBack: false,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isComplete) ...[
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Colors.white,
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 80,
                  color: Colors.white,
                ),
              ],
              const SizedBox(height: 32),
              Text(
                _isComplete ? 'Scan Complete' : 'Scanning Library',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              if (!_isComplete) ...[
                const SizedBox(height: 16),
                Text(
                  _status,
                  style: const TextStyle(fontSize: 16, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const SizedBox(height: 24),
                Container(
                  width: 320,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_scannedFileCount',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'FILES SCANNED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Found $_albumCount albums, $_songCount songs',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (_skippedFileCount > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1F0A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade300,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            '$_skippedFileCount file(s) could not be read and were skipped',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.amber.shade100,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: 320,
                  child: ElevatedButton(
                    onPressed: _continueAfterScan,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
