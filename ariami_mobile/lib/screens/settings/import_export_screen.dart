import 'package:flutter/material.dart';
import '../../services/import_export_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  final ImportExportService _importExportService = ImportExportService();
  bool _isLoading = false;
  DateTime? _lastExportTime;
  DateTime? _lastImportTime;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _importExportService.initialize();
    if (mounted) {
      setState(() {
        _lastExportTime = _importExportService.lastExportTime;
        _lastImportTime = _importExportService.lastImportTime;
      });
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}, $hour:$minute $period';
  }

  Future<void> _export() async {
    setState(() => _isLoading = true);

    final result = await _importExportService.exportData();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() {
        _lastExportTime = _importExportService.lastExportTime;
      });
    }
  }

  Future<void> _import() async {
    // Show mode selection dialog
    final mode = await showDialog<ImportMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Mode'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How would you like to handle existing data?'),
            SizedBox(height: 16),
            Text(
              'Merge: Add new playlists, update existing stats',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Replace: Delete existing data and replace with backup',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.merge),
            child: const Text('Merge'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.replace),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    if (mode == null) return;

    setState(() => _isLoading = true);

    final result = await _importExportService.importData(mode);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() {
        _lastImportTime = _importExportService.lastImportTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('BACKUP & RESTORE'),
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            32,
            0,
            32,
            getMiniPlayerAwareBottomPadding() + 24,
          ),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Icon with minimalist glow/halo effect if desired, but let's stick to clean
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 64,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'Data Portability',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Export your playlists and listening stats to a backup file, or restore from a previous session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Status Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildStatusRow(
                      'LAST EXPORT',
                      _formatDateTime(_lastExportTime),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildStatusRow(
                      'LAST IMPORT',
                      _formatDateTime(_lastImportTime),
                      isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Export Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _export,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)
                      )
                    : const Text(
                        'EXPORT DATA',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),

              // Import Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _import,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                      width: 1.5,
                    ),
                    shape: const StadiumBorder(),
                    foregroundColor: isDark ? Colors.white : Colors.black,
                  ),
                  child: const Text(
                    'IMPORT DATA',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Footer
              Text(
                'Includes playlists and streaming statistics',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[700] : Colors.grey[400],
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey[600] : Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        Text(
          value.toUpperCase(),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
