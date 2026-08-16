import 'package:flutter/material.dart';

import '../../models/music_folder_validation_result.dart';
import '../services/web_setup_service.dart';
import '../onboarding/setup_help.dart';
import '../utils/constants.dart';
import '../widgets/ui/setup_scaffold.dart';

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
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(context, '/scanning');
  }

  Widget _buildSuggestionCard(MusicFolderValidationResult suggestion) {
    final isSelected = _selectedSuggestionPath == suggestion.path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? AppTheme.surfaceHover : AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: _isValidating ? null : () => _selectSuggestion(suggestion),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: isSelected ? Colors.white : AppTheme.borderGrey,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  suggestion.isValid
                      ? Icons.folder_rounded
                      : Icons.folder_off_outlined,
                  color: suggestion.isValid
                      ? AppTheme.textPrimary
                      : AppTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.path,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: suggestion.isValid
                              ? AppTheme.textPrimary
                              : AppTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestion.isValid
                            ? 'Available on this server'
                            : _validationErrorMessage(suggestion),
                        style: AppTheme.meta.copyWith(
                          color: suggestion.isValid || suggestion.error == 'missing'
                              ? AppTheme.textTertiary
                              : AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected && _isPathValid)
                  const Icon(Icons.check_circle_rounded,
                      size: 20, color: AppTheme.success),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: 2,
      icon: Icons.folder_open_rounded,
      title: 'Choose your music folder',
      description: 'Point Ariami at the folder on this server where your '
          'music lives. It reads tags and artwork; your files are never '
          'moved, changed or uploaded.',
      helpTopic: CliOnboardingCopy.musicFolder,
      secondaryAction: TextButton(
        onPressed: () {
          Navigator.pushReplacementNamed(context, '/tailscale-check');
        },
        child: const Text('Back'),
      ),
      primaryAction: ElevatedButton.icon(
        onPressed: !_isPathValid ? null : _startScanning,
        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
        iconAlignment: IconAlignment.end,
        label: const Text('Scan this folder'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoadingSuggestions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_suggestions.isNotEmpty) ...[
            Text('Found on this server', style: AppTheme.fieldLabel),
            const SizedBox(height: 10),
            for (final suggestion in _suggestions)
              _buildSuggestionCard(suggestion),
            const SizedBox(height: 22),
          ],
          Text('Or enter a path', style: AppTheme.fieldLabel),
          const SizedBox(height: 10),
          TextField(
            controller: _pathController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: '/path/to/your/music',
              prefixIcon: const Icon(Icons.dns_rounded, size: 19),
              errorText: _errorMessage,
              suffixIcon: _isValidating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _isPathValid
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppTheme.success)
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _isValidating ? null : () => _validatePath(),
              child: Text(_isValidating ? 'Checking…' : 'Check this path'),
            ),
          ),
        ],
      ),
    );
  }
}
