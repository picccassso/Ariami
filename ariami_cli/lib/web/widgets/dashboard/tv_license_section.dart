import 'package:ariami_core/services/license/license_key_activator.dart';
import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ARIAMI TV',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderGrey),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tv_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACTIVATE TV LICENSE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // The stored blob is opaque here (only the TV can
                          // verify what it covers), so never promise it
                          // unlocks TVs.
                          _hasStoredLicense
                              ? 'A license file is already stored on this '
                                  'server. If it includes Ariami TV, your '
                                  'TVs unlock automatically when they '
                                  'connect.'
                              : 'Paste the TV license key from your '
                                  'purchase email. It\'s stored on this '
                                  'server and every TV unlocks '
                                  'automatically on its next connect.',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keyController,
                      enabled: !_busy,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
                        hintStyle: TextStyle(
                          color: AppTheme.textSecondary
                              .withValues(alpha: 0.5),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.borderGrey),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.borderGrey),
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
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _busy ? null : _activate,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Activate',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
              if (_activated) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Colors.greenAccent,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'TV license activated and stored on this server. '
                        'Your TV will unlock the next time it connects.',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
