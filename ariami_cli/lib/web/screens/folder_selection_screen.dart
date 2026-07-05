import 'package:flutter/material.dart';

import '../../models/music_folder_validation_result.dart';
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
  bool _isLoadingSuggestions = true;
  bool _isPathValid = false;
  String? _errorMessage;
  List<MusicFolderValidationResult> _suggestions = const [];
  String? _selectedSuggestionPath;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() {
      _isLoadingSuggestions = true;
    });

    final suggestions = await _setupService.getMusicFolderSuggestions();

    if (!mounted) {
      return;
    }

    setState(() {
      _suggestions = suggestions;
      _isLoadingSuggestions = false;
    });
  }

  String _validationErrorMessage(MusicFolderValidationResult result) {
    if (result.message != null && result.message!.isNotEmpty) {
      return result.message!;
    }

    switch (result.error) {
      case 'missing':
        return 'Path does not exist on the server';
      case 'permissionDenied':
        return 'Permission denied: cannot read this folder';
      case 'notDirectory':
        return 'Path is not a directory';
      case 'empty':
        return 'Path is required';
      default:
        return 'Invalid path or path is not accessible on the server';
    }
  }

  void _applyValidationResult(MusicFolderValidationResult result) {
    setState(() {
      _isValidating = false;
      _isPathValid = result.isValid;
      _errorMessage = result.isValid ? null : _validationErrorMessage(result);
      if (result.isValid) {
        _selectedSuggestionPath = result.path;
        _pathController.text = result.path;
      }
    });
  }

  Future<void> _validatePath({bool saveOnSuccess = true}) async {
    final path = _pathController.text.trim();

    if (path.isEmpty) {
      setState(() {
        _isPathValid = false;
        _errorMessage = null;
        _selectedSuggestionPath = null;
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _selectedSuggestionPath = null;
    });

    try {
      final result = saveOnSuccess
          ? await _setupService.setMusicFolder(path)
          : await _setupService.validateMusicFolder(path);
      _applyValidationResult(result);
    } catch (e) {
      setState(() {
        _isValidating = false;
        _isPathValid = false;
        _errorMessage = 'Error validating path: $e';
      });
    }
  }

  Future<void> _selectSuggestion(MusicFolderValidationResult suggestion) async {
    _pathController.text = suggestion.path;
    setState(() {
      _selectedSuggestionPath = suggestion.path;
      _errorMessage = null;
    });

    if (suggestion.isValid) {
      setState(() {
        _isValidating = true;
      });

      final result = await _setupService.setMusicFolder(suggestion.path);
      _applyValidationResult(result);
      return;
    }

    await _validatePath(saveOnSuccess: false);
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

  Widget _buildSuggestionCard(MusicFolderValidationResult suggestion) {
    final isSelected = _selectedSuggestionPath == suggestion.path;
    final statusColor = suggestion.isValid
        ? Colors.white
        : suggestion.error == 'missing'
            ? Colors.white54
            : Colors.orangeAccent;

    return Material(
      color: isSelected
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isValidating ? null : () => _selectSuggestion(suggestion),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                suggestion.isValid
                    ? Icons.folder_rounded
                    : Icons.folder_off_outlined,
                color: statusColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.path,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      suggestion.isValid
                          ? 'Available on this server'
                          : _validationErrorMessage(suggestion),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected && _isPathValid)
                const Icon(Icons.check_circle_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                        width: double.infinity,
                        child: Text(
                          'Choose a common location on the server or enter an absolute path manually.',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'SUGGESTED PATHS',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    letterSpacing: 1.2,
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            if (_isLoadingSuggestions)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else if (_suggestions.isEmpty)
                              Text(
                                'No suggestions available. Enter a path manually below.',
                                style: TextStyle(
                                  color: AppTheme.textSecondary.withValues(alpha: 0.9),
                                ),
                              )
                            else
                              Column(
                                children: [
                                  for (final suggestion in _suggestions) ...[
                                    _buildSuggestionCard(suggestion),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                            const SizedBox(height: 32),
                            Text(
                              'MANUAL PATH',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    letterSpacing: 1.2,
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pathController,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'ABSOLUTE PATH',
                                hintText: '/path/to/your/music/library',
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
                                    _selectedSuggestionPath = null;
                                  });
                                }
                              },
                              onSubmitted: (_) => _validatePath(),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 60,
                              child: ElevatedButton.icon(
                                onPressed: _isValidating ? null : () => _validatePath(),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 32,
                        runSpacing: 12,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(context, '/tailscale-check');
                            },
                            child: const Text('BACK'),
                          ),
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
            ),
          ],
        ),
      ),
    );
  }
}
