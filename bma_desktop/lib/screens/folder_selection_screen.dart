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

      if (selectedDirectory != null) {
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Folder selected successfully! You can now scan your library.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting folder: $e')),
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
                Icons.folder_open,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Choose Your Music Folder',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select the folder containing your music files',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              if (_selectedFolderPath != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.folder, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          _selectedFolderPath!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _selectFolder,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(_selectedFolderPath == null
                    ? 'Select Folder'
                    : 'Change Folder'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedFolderPath != null)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/connection');
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
