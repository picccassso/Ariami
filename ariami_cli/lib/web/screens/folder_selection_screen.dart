import 'package:flutter/material.dart';
import '../services/web_setup_service.dart';
import '../utils/constants.dart';

class FolderSelectionScreen extends StatefulWidget {
  const FolderSelectionScreen({super.key});

  @override
  State<FolderSelectionScreen> createState() => _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends State<FolderSelectionScreen> {
  final WebSetupService _setupService = WebSetupService();
  final TextEditingController _pathController = TextEditingController();

  bool _isValidating = false;
  bool _isPathValid = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _validatePath() async {
    final path = _pathController.text.trim();

    if (path.isEmpty) {
      setState(() {
        _isPathValid = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    try {
      final isValid = await _setupService.setMusicFolder(path);

      setState(() {
        _isValidating = false;
        _isPathValid = isValid;
        if (!isValid) {
          _errorMessage = 'Invalid path or path does not exist on server';
        }
      });
    } catch (e) {
      setState(() {
        _isValidating = false;
        _isPathValid = false;
        _errorMessage = 'Error validating path: $e';
      });
    }
  }

  Future<void> _startScanning() async {
    if (!_isPathValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid folder path first'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(context, '/scanning');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('SETUP'),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'MUSIC FOLDER',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 500,
                        child: Text(
                          'Provide the absolute path to your music library on the host machine to begin indexing.',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 56),
                      SizedBox(
                        width: 600,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _pathController,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'ABSOLUTE PATH',
                                hintText: '/Users/music/library',
                                prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                                errorText: _errorMessage,
                                suffixIcon: _isValidating
                                    ? const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white),
                                        ),
                                      )
                                    : _isPathValid
                                        ? const Icon(Icons.check_circle_rounded,
                                            color: Colors.white)
                                        : null,
                              ),
                              onChanged: (_) {
                                if (_isPathValid || _errorMessage != null) {
                                  setState(() {
                                    _isPathValid = false;
                                    _errorMessage = null;
                                  });
                                }
                              },
                              onSubmitted: (_) => _validatePath(),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 60,
                              child: ElevatedButton.icon(
                                onPressed: _isValidating ? null : _validatePath,
                                icon: _isValidating
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.analytics_rounded),
                                label: Text(_isValidating ? 'VALIDATING...' : 'VALIDATE FOLDER'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 64),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(context, '/tailscale-check');
                            },
                            child: const Text('BACK'),
                          ),
                          const SizedBox(width: 32),
                          SizedBox(
                            height: 60,
                            width: 200,
                            child: ElevatedButton(
                              onPressed: !_isPathValid ? null : _startScanning,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isPathValid ? Colors.white : AppTheme.surfaceBlack,
                                foregroundColor: _isPathValid ? AppTheme.pureBlack : Colors.white24,
                                side: _isPathValid
                                    ? null
                                    : const BorderSide(color: AppTheme.borderGrey),
                              ),
                              child: const Text('NEXT STEP'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
