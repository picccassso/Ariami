import 'package:flutter/material.dart';
import '../services/web_setup_service.dart';

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
      // Send path to backend for validation
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
        const SnackBar(content: Text('Please enter a valid folder path first')),
      );
      return;
    }

    // Navigate to scanning screen
    // The scanning screen will trigger the actual scan
    Navigator.pushReplacementNamed(context, '/scanning');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Music Folder'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.folder_open,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'Enter Your Music Folder Path',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter the absolute path to the folder containing your music library on the server',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _pathController,
                      decoration: InputDecoration(
                        labelText: 'Music Folder Path',
                        hintText: '/Users/yourname/Music',
                        prefixIcon: const Icon(Icons.folder),
                        border: const OutlineInputBorder(),
                        errorText: _errorMessage,
                        suffixIcon: _isValidating
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _isPathValid
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                      ),
                      onChanged: (_) {
                        // Reset validation state when user types
                        if (_isPathValid || _errorMessage != null) {
                          setState(() {
                            _isPathValid = false;
                            _errorMessage = null;
                          });
                        }
                      },
                      onSubmitted: (_) => _validatePath(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isValidating ? null : _validatePath,
                      icon: _isValidating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isValidating ? 'Validating...' : 'Validate Path'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                          context, '/tailscale-check');
                    },
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: !_isPathValid ? null : _startScanning,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      'Scan Library',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
