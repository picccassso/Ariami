import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderSelectionScreen extends StatefulWidget {
  const FolderSelectionScreen({super.key});

  @override
  State<FolderSelectionScreen> createState() => _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends State<FolderSelectionScreen> {
  String? _selectedFolderPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedFolder();
  }

  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('music_folder_path');
    if (savedPath != null) {
      setState(() {
        _selectedFolderPath = savedPath;
      });
    }
  }

  Future<void> _selectFolder() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Use confirmDialogText to force user interaction for macOS permissions
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Music Folder',
        lockParentWindow: true,
      );

      if (selectedDirectory == null || selectedDirectory.isEmpty) {
        return;
      }

      // Fix macOS path issue: Remove /Volumes/Macintosh HD prefix if present
      String fixedPath = selectedDirectory;
      if (fixedPath.startsWith('/Volumes/Macintosh HD')) {
        fixedPath = fixedPath.replaceFirst('/Volumes/Macintosh HD', '');
        print('[FolderSelection] Fixed path: $selectedDirectory -> $fixedPath');
      }

      setState(() {
        _selectedFolderPath = fixedPath;
      });

      // Save to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('music_folder_path', fixedPath);

      print('[FolderSelection] Saved music folder path: $fixedPath');
      
      // Removed Snackbar per request

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting folder: $e'),
            backgroundColor: const Color(0xFF141414), // Themed error
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Music Folder'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'Choose Your Music Folder',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select the folder containing your music files',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              if (_selectedFolderPath != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.folder_rounded, color: Colors.white54),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SelectableText(
                          _selectedFolderPath!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _selectFolder,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 20),
                label: Text(_selectedFolderPath == null
                    ? 'Select Folder'
                    : 'Change Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF333333)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedFolderPath != null)
                OutlinedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/connection');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF333333)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 20,
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
