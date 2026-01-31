import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ariami_core/ariami_core.dart';

class ScanningScreen extends StatefulWidget {
  final String musicFolderPath;
  final String? nextRoute; // If set, navigates forward to this route instead of popping

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

      setState(() {
        _isComplete = true;
        _albumCount = _httpServer.libraryManager.library?.totalAlbums ?? 0;
        _songCount = _httpServer.libraryManager.library?.totalSongs ?? 0;
        _status = 'Scan complete!';
      });

      // Wait a moment to show the completion, then navigate
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        if (widget.nextRoute != null) {
          // Navigate forward to next route (slides in from right)
          Navigator.pushReplacementNamed(context, widget.nextRoute!);
        } else {
          // Pop back to previous screen
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Text(
                    'Found $_albumCount albums, $_songCount songs',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
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
