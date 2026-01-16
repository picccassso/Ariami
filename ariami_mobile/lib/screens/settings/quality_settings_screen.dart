import 'package:flutter/material.dart';
import '../../models/quality_settings.dart';
import '../../services/quality/quality_settings_service.dart';
import '../../services/quality/network_monitor_service.dart';

/// Screen for configuring streaming and download quality settings
class QualitySettingsScreen extends StatefulWidget {
  const QualitySettingsScreen({super.key});

  @override
  State<QualitySettingsScreen> createState() => _QualitySettingsScreenState();
}

class _QualitySettingsScreenState extends State<QualitySettingsScreen> {
  final QualitySettingsService _qualityService = QualitySettingsService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();

  late QualitySettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _qualityService.initialize();
    await _networkMonitor.initialize();

    if (mounted) {
      setState(() {
        _settings = _qualityService.settings;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateWifiQuality(StreamingQuality quality) async {
    await _qualityService.setWifiQuality(quality);
    setState(() {
      _settings = _qualityService.settings;
    });
  }

  Future<void> _updateMobileDataQuality(StreamingQuality quality) async {
    await _qualityService.setMobileDataQuality(quality);
    setState(() {
      _settings = _qualityService.settings;
    });
  }

  Future<void> _updateDownloadQuality(StreamingQuality quality) async {
    await _qualityService.setDownloadQuality(quality);
    setState(() {
      _settings = _qualityService.settings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Quality'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: isDark ? Colors.black : Colors.grey[50],
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: 64 + kBottomNavigationBarHeight,
                ),
                children: [
                  // Current network indicator
                  _buildCurrentNetworkCard(isDark),

                  // Streaming quality section
                  _buildSectionHeader('Streaming Quality', isDark),
                  _buildQualityCard(
                    context,
                    isDark: isDark,
                    icon: Icons.wifi,
                    title: 'WiFi',
                    subtitle: 'Quality when connected to WiFi',
                    currentQuality: _settings.wifiQuality,
                    onChanged: _updateWifiQuality,
                  ),
                  _buildQualityCard(
                    context,
                    isDark: isDark,
                    icon: Icons.signal_cellular_alt,
                    title: 'Mobile Data',
                    subtitle: 'Quality when using cellular data',
                    currentQuality: _settings.mobileDataQuality,
                    onChanged: _updateMobileDataQuality,
                  ),

                  // Download quality section
                  _buildSectionHeader('Download Quality', isDark),
                  _buildQualityCard(
                    context,
                    isDark: isDark,
                    icon: Icons.download,
                    title: 'Downloads',
                    subtitle: 'Quality for downloaded songs',
                    currentQuality: _settings.downloadQuality,
                    onChanged: _updateDownloadQuality,
                  ),

                  // Info section
                  _buildInfoSection(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentNetworkCard(bool isDark) {
    final networkType = _networkMonitor.currentNetworkType;
    final currentQuality = _qualityService.getCurrentStreamingQuality();

    IconData networkIcon;
    String networkLabel;
    Color networkColor;

    switch (networkType) {
      case NetworkType.wifi:
        networkIcon = Icons.wifi;
        networkLabel = 'WiFi';
        networkColor = Colors.green;
      case NetworkType.mobile:
        networkIcon = Icons.signal_cellular_alt;
        networkLabel = 'Mobile Data';
        networkColor = Colors.orange;
      case NetworkType.none:
        networkIcon = Icons.signal_wifi_off;
        networkLabel = 'No Connection';
        networkColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: networkColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                networkIcon,
                color: networkColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Network: $networkLabel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Streaming at ${currentQuality.displayName}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.blue[700],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildQualityCard(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required StreamingQuality currentQuality,
    required Function(StreamingQuality) onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: InkWell(
        onTap: () => _showQualityPicker(
          context,
          title: title,
          currentQuality: currentQuality,
          onChanged: onChanged,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getQualityColor(currentQuality).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  currentQuality.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _getQualityColor(currentQuality),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getQualityColor(StreamingQuality quality) {
    switch (quality) {
      case StreamingQuality.high:
        return Colors.green;
      case StreamingQuality.medium:
        return Colors.orange;
      case StreamingQuality.low:
        return Colors.blue;
    }
  }

  void _showQualityPicker(
    BuildContext context, {
    required String title,
    required StreamingQuality currentQuality,
    required Function(StreamingQuality) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$title Quality',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...StreamingQuality.values.map((quality) {
                  final isSelected = quality == currentQuality;
                  return ListTile(
                    leading: Icon(
                      _getQualityIcon(quality),
                      color: isSelected
                          ? _getQualityColor(quality)
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    ),
                    title: Text(
                      quality.displayName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? _getQualityColor(quality)
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    subtitle: Text(
                      quality.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: _getQualityColor(quality))
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onChanged(quality);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getQualityIcon(StreamingQuality quality) {
    switch (quality) {
      case StreamingQuality.high:
        return Icons.high_quality;
      case StreamingQuality.medium:
        return Icons.sd;
      case StreamingQuality.low:
        return Icons.data_saver_on;
    }
  }

  Widget _buildInfoSection(bool isDark) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? Colors.grey[850] : Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: isDark ? Colors.blue[300] : Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'About Quality Settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.blue[300] : Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              isDark,
              'High (Original)',
              'Full quality, largest file size. Best for WiFi.',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              isDark,
              'Medium (128 kbps)',
              'Good quality, ~40% smaller files.',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              isDark,
              'Low (64 kbps)',
              'Acceptable quality, ~80% smaller files. Best for slow connections.',
            ),
            const SizedBox(height: 12),
            Text(
              'Lower quality settings reduce data usage and improve playback on slow connections.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(bool isDark, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u2022 ',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[700],
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
                TextSpan(
                  text: description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
