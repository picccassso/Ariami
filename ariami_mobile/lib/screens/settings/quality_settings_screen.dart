import 'package:flutter/material.dart';
import '../../models/quality_settings.dart';
import '../../services/quality/quality_settings_service.dart';
import '../../services/quality/network_monitor_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

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
    // Force dark theme colors for the premium look
    const backgroundColor = Color(0xFF050505);
    const textColor = Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('STREAMING QUALITY'),
        titleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                getMiniPlayerAwareBottomPadding() + 20,
              ),
              children: [
                // Current network indicator
                _buildCurrentNetworkCard(),

                const SizedBox(height: 12),

                // Streaming quality section
                _buildSectionHeader('STREAMING QUALITY'),
                _buildQualityCard(
                  context,
                  icon: Icons.wifi_rounded,
                  title: 'WiFi',
                  subtitle: 'Highest quality when on WiFi',
                  currentQuality: _settings.wifiQuality,
                  onChanged: _updateWifiQuality,
                ),
                const SizedBox(height: 8),
                _buildQualityCard(
                  context,
                  icon: Icons.signal_cellular_alt_rounded,
                  title: 'Mobile Data',
                  subtitle: 'Save bandwidth on cellular',
                  currentQuality: _settings.mobileDataQuality,
                  onChanged: _updateMobileDataQuality,
                ),

                const SizedBox(height: 12),

                // Download quality section
                _buildSectionHeader('DOWNLOAD QUALITY'),
                _buildQualityCard(
                  context,
                  icon: Icons.file_download_outlined,
                  title: 'Downloads',
                  subtitle: 'Quality for offline playback',
                  currentQuality: _settings.downloadQuality,
                  onChanged: _updateDownloadQuality,
                ),

                const SizedBox(height: 24),

                // Info section
                _buildInfoSection(),
              ],
            ),
    );
  }

  Widget _buildCurrentNetworkCard() {
    final networkType = _networkMonitor.currentNetworkType;
    final currentQuality = _qualityService.getCurrentStreamingQuality();

    IconData networkIcon;
    String networkLabel;
    
    switch (networkType) {
      case NetworkType.wifi:
        networkIcon = Icons.wifi_rounded;
        networkLabel = 'WiFi Connected';
      case NetworkType.mobile:
        networkIcon = Icons.signal_cellular_alt_rounded;
        networkLabel = 'Cellular Data';
      case NetworkType.none:
        networkIcon = Icons.signal_wifi_off_rounded;
        networkLabel = 'Offline';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF222222),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              networkIcon,
              color: Colors.black,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  networkLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Currently ${currentQuality.displayName.toLowerCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          if (networkType != NetworkType.none)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF00C853), // Maintain functional green for connection
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 16, 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.grey[400],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildQualityCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required StreamingQuality currentQuality,
    required Function(StreamingQuality) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF222222),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showQualityPicker(
          context,
          title: title,
          currentQuality: currentQuality,
          onChanged: onChanged,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF333333),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Use flexible for the trailing element to prevent squishing
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        currentQuality.displayName.toUpperCase(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey[700],
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualityPicker(
    BuildContext context, {
    required String title,
    required StreamingQuality currentQuality,
    required Function(StreamingQuality) onChanged,
  }) {
    showMiniPlayerAwareBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${title.toUpperCase()} QUALITY',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ...StreamingQuality.values.map((quality) {
                  final isSelected = quality == currentQuality;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: Icon(
                          _getQualityIcon(quality),
                          color: isSelected ? Colors.black : Colors.grey[500],
                          size: 20,
                        ),
                        title: Text(
                          quality.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.black : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          quality.description,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.black54 : Colors.grey[500],
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Colors.black,
                                size: 20,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onChanged(quality);
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
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
        return Icons.high_quality_rounded;
      case StreamingQuality.medium:
        return Icons.sd_rounded;
      case StreamingQuality.low:
        return Icons.data_saver_on_rounded;
    }
  }

  Widget _buildInfoSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF222222),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                'SYSTEM INFO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            'High (Original)',
            'Full quality, largest file size. Best for WiFi.',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Medium (128 kbps)',
            'Good quality, ~40% smaller files.',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Low (64 kbps)',
            'Acceptable quality, ~80% smaller files.',
          ),
          const SizedBox(height: 16),
          Text(
            'Lower quality settings reduce data usage and improve playback on slow connections.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}
