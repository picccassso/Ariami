import 'package:ariami_core/services/license/license_key_activator.dart';
import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import '../ui/section.dart';
import '../ui/status_pill.dart';

/// Admin card that activates an Ariami TV license key on the TVs' behalf.
///
/// The key is exchanged for a signed license file and stored on this
/// server; every TV in the household picks it up and verifies it itself on
/// the next connect — no typing with a TV remote. The dashboard never
/// parses or keeps the file.
class TvLicenseSection extends StatefulWidget {
  const TvLicenseSection({
    super.key,
    required this.apiClient,
    this.activator,
  });

  final WebApiClient apiClient;

  /// Injectable for tests; defaults to the production activation service.
  final LicenseKeyActivator? activator;

  @override
  State<TvLicenseSection> createState() => _TvLicenseSectionState();
}

class _TvLicenseSectionState extends State<TvLicenseSection> {
  late final LicenseKeyActivator _activator =
      widget.activator ?? LicenseKeyActivator();
  final TextEditingController _keyController = TextEditingController();

  bool _busy = false;
  bool _activated = false;
  String? _error;
  bool _hasStoredLicense = false;

  @override
  void initState() {
    super.initState();
    _loadStoredState();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredState() async {
    try {
      final files = await widget.apiClient.getLicenseFiles();
      if (!mounted) return;
      setState(() => _hasStoredLicense = files.isNotEmpty);
    } catch (_) {
      // Purely informational; leave the hint hidden.
    }
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
      _activated = false;
    });

    final result = await _activator.activate(
      licenseKey: _keyController.text,
      product: 'tv',
      deviceName: 'Ariami Server Dashboard',
    );
    if (!mounted) return;
    if (result is LicenseKeyActivationFailure) {
      setState(() {
        _busy = false;
        _error = result.message('Ariami TV');
      });
      return;
    }

    try {
      await widget.apiClient.putLicenseFile(
        (result as LicenseKeyActivationSuccess).licenseFile,
      );
    } on WebApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isForbidden
            ? 'The key was accepted, but only the server owner\'s account '
                'can store the license. Sign in as the owner and try again.'
            : 'The key was accepted, but the license couldn\'t be stored '
                'on this server. Try again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _activated = true;
      _hasStoredLicense = true;
      _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Ariami TV',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(color: AppTheme.borderGrey),
                  ),
                  child: const Icon(Icons.tv_rounded,
                      size: 19, color: AppTheme.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TV licence',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        // The stored blob is opaque here (only the TV can
                        // verify what it covers), so never promise it
                        // unlocks TVs.
                        _hasStoredLicense
                            ? 'A licence file is already stored on this '
                                'server. If it includes Ariami TV, your TVs '
                                'unlock automatically when they connect.'
                            : 'Paste the TV licence key from your purchase '
                                'email. It is stored on this server and every '
                                'TV unlocks automatically on its next '
                                'connect.',
                        style: AppTheme.meta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    enabled: !_busy,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    onChanged: (_) {
                      if (_error != null || _activated) {
                        setState(() {
                          _error = null;
                          _activated = false;
                        });
                      }
                    },
                    onSubmitted: (_) => _busy ? null : _activate(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _activate,
                  child: _busy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Activate'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              NoticeBanner(
                icon: Icons.error_outline_rounded,
                tone: StatusTone.negative,
                message: _error!,
              ),
            ],
            if (_activated) ...[
              const SizedBox(height: 14),
              const NoticeBanner(
                icon: Icons.check_circle_rounded,
                tone: StatusTone.positive,
                message: 'TV licence activated and stored on this server. '
                    'Your TV will unlock the next time it connects.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
