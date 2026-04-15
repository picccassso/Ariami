import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
  bool _preferLocalWhenOnline = false;

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
        _preferLocalWhenOnline = _settings.preferLocalWhenOnline;
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

  Future<void> _updatePreferLocalWhenOnline(bool preferLocal) async {
    await _qualityService.setPreferLocalWhenOnline(preferLocal);
    setState(() {
      _settings = _qualityService.settings;
      _preferLocalWhenOnline = preferLocal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Streaming Quality'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft, size: 20, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                getMiniPlayerAwareBottomPadding(context) + 20,
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
                const SizedBox(height: 8),
                _buildToggleCard(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Prefer Local When Online',
                  subtitle: 'Play downloaded or cached files even when connected',
                  value: _preferLocalWhenOnline,
                  onChanged: _updatePreferLocalWhenOnline,
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
    final colorScheme = Theme.of(context).colorScheme;

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              networkIcon,
              color: colorScheme.onSurface,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  networkLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Currently ${currentQuality.displayName.toLowerCase()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (networkType != NetworkType.none)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colorScheme.tertiary, // Use theme tertiary color for status indicator
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: colorScheme.onSurface,
          letterSpacing: 1.5,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showQualityPicker(
          context,
          title: title,
          currentQuality: currentQuality,
          onChanged: onChanged,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  icon,
                  color: colorScheme.onSurface,
                  size: 24,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
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
                        currentQuality.displayName,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
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

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  icon,
                  color: colorScheme.onSurface,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
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
    final colorScheme = Theme.of(context).colorScheme;
    showMiniPlayerAwareBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: colorScheme.onSurface,
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
                        color: isSelected ? colorScheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: Icon(
                          _getQualityIcon(quality),
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        title: Text(
                          quality.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          quality.description,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? colorScheme.onPrimary.withOpacity(0.7) : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle_rounded,
                                color: colorScheme.onPrimary,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 24,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 16),
              Text(
                'SYSTEM INFO',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'High (Original)',
                  'Full quality, largest file size. Best for WiFi.',
                  colorScheme,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Medium (128 kbps)',
                  'Good quality, ~40% smaller files.',
                  colorScheme,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Low (64 kbps)',
                  'Acceptable quality, ~80% smaller files.',
                  colorScheme,
                ),
                const SizedBox(height: 16),
                Text(
                  'Lower quality settings reduce data usage and improve playback on slow connections.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String description, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
