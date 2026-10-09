import 'dart:async';
import '../../utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/quality_settings.dart';
import '../../services/quality/quality_settings_service.dart';
import '../../services/quality/network_monitor_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/option_sheet.dart';
import '../../widgets/settings/settings_header.dart';

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

  StreamSubscription<QualitySettings>? _settingsSubscription;
  StreamSubscription<NetworkType>? _networkSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
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

      _settingsSubscription ??=
          _qualityService.settingsStream.listen((settings) {
        if (mounted) {
          setState(() {
            _settings = settings;
            _preferLocalWhenOnline = settings.preferLocalWhenOnline;
          });
        }
      });

      _networkSubscription ??= _qualityService.networkTypeStream.listen((_) {
        if (mounted) {
          setState(() {});
        }
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

  Future<void> _updateDownloadQualityOption(DownloadQuality quality) async {
    await _qualityService.setDownloadQualityOption(quality);
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
          icon: Icon(LucideIcons.chevronLeft,
              size: 20, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ContentWidthLimiter(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: colorScheme.primary))
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  getMiniPlayerScrollBottomPadding(context) + 20,
                ),
                children: [
                  _buildCurrentNetworkCard(),
                  const SizedBox(height: 12),
                  const SettingsHeader('STREAMING QUALITY'),
                  _buildQualityCard(
                    context,
                    icon: Icons.wifi_rounded,
                    title: 'WiFi',
                    subtitle: 'Highest quality when on WiFi',
                    valueLabel: _settings.wifiQuality.displayName,
                    onTap: () => showOptionSheet<StreamingQuality>(
                      context,
                      header: 'WiFi quality',
                      values: StreamingQuality.values,
                      current: _settings.wifiQuality,
                      iconOf: _getQualityIcon,
                      titleOf: (q) => q.displayName,
                      subtitleOf: (q) => q.description,
                      onSelected: _updateWifiQuality,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildQualityCard(
                    context,
                    icon: Icons.signal_cellular_alt_rounded,
                    title: 'Mobile Data',
                    subtitle: 'Save bandwidth on cellular',
                    valueLabel: _settings.mobileDataQuality.displayName,
                    onTap: () => showOptionSheet<StreamingQuality>(
                      context,
                      header: 'Mobile Data quality',
                      values: StreamingQuality.values,
                      current: _settings.mobileDataQuality,
                      iconOf: _getQualityIcon,
                      titleOf: (q) => q.displayName,
                      subtitleOf: (q) => q.description,
                      onSelected: _updateMobileDataQuality,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildToggleCard(
                    icon: Icons.download_for_offline_rounded,
                    title: 'Prefer Local When Online',
                    subtitle:
                        'Play downloaded or cached files even when connected',
                    value: _preferLocalWhenOnline,
                    onChanged: _updatePreferLocalWhenOnline,
                  ),
                  const SizedBox(height: 12),
                  const SettingsHeader('DOWNLOAD QUALITY'),
                  _buildQualityCard(
                    context,
                    icon: Icons.file_download_outlined,
                    title: 'Downloads',
                    subtitle: 'Quality for offline playback',
                    valueLabel: _settings.effectiveDownloadQuality.displayName,
                    onTap: () => showOptionSheet<DownloadQuality>(
                      context,
                      header: 'Download quality',
                      values: DownloadQuality.values,
                      current: _settings.effectiveDownloadQuality,
                      iconOf: downloadQualityIcon,
                      titleOf: (q) => q.displayName,
                      subtitleOf: (q) => q.description,
                      onSelected: _updateDownloadQualityOption,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildInfoSection(),
                ],
              ),
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
                color: colorScheme
                    .tertiary, // Use theme tertiary color for status indicator
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQualityCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String valueLabel,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        valueLabel,
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
                  'Original (Source File)',
                  'Source audio file without conversion. Used for Original downloads and High quality streaming.',
                  colorScheme,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'High (192 kbps)',
                  'High bitrate audio conversion. Used for high-fidelity offline downloads.',
                  colorScheme,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Medium (128 kbps)',
                  'Good quality, balanced storage and data usage (~40% smaller).',
                  colorScheme,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Low (64 kbps)',
                  'Acceptable quality, smallest file size and data usage (~80% smaller).',
                  colorScheme,
                ),
                const SizedBox(height: 16),
                Text(
                  'Lower quality settings reduce data usage and storage size. Offline downloads can be saved at Original or converted to High, Medium, or Low.',
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

  Widget _buildInfoRow(
      String title, String description, ColorScheme colorScheme) {
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
