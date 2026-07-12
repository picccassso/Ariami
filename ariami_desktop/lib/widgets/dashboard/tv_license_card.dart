import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

/// Dashboard card that activates an Ariami TV license key on the TVs'
/// behalf: the key is exchanged for a signed license file and stored on
/// this (embedded) server, and every TV in the household picks it up and
/// verifies it itself on the next connect — no typing with a TV remote.
///
/// Kept in feature parity with the CLI web dashboard's TvLicenseSection.
class TvLicenseCard extends StatefulWidget {
  const TvLicenseCard({
    super.key,
    this.activator,
    this.licenseFileStore,
  });

  /// Injectable for tests; default to the production activation service
  /// and the embedded server's relay store.
  final LicenseKeyActivator? activator;
  final LicenseFileStore? Function()? licenseFileStore;

  @override
  State<TvLicenseCard> createState() => _TvLicenseCardState();
}

class _TvLicenseCardState extends State<TvLicenseCard> {
  late final LicenseKeyActivator _activator =
      widget.activator ?? LicenseKeyActivator();
  late final LicenseFileStore? Function() _store =
      widget.licenseFileStore ?? (() => AriamiHttpServer().licenseFileStore);
  final TextEditingController _keyController = TextEditingController();

  bool _busy = false;
  bool _activated = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  bool get _hasStoredLicense {
    try {
      return _store()?.licenseFiles.isNotEmpty ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _activate() async {
    final store = _store();
    if (store == null) {
      setState(() {
        _error = 'The server isn\'t fully started yet. Try again in a '
            'moment.';
      });
      return;
    }

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
      await store
          .save((result as LicenseKeyActivationSuccess).licenseFile);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The key was accepted, but the license couldn\'t be '
            'stored on this server. Try again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _activated = true;
      _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tv_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Text(
                'Activate TV License',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _hasStoredLicense
                ? 'A license is stored on this server. TVs pick it up '
                    'automatically when they connect.'
                : 'Paste the TV license key from your purchase email. '
                    'It\'s stored on this server and every TV unlocks '
                    'automatically on its next connect.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'TV license key',
                    hintText: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
                    isDense: true,
                    border: OutlineInputBorder(),
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
              FilledButton(
                onPressed: _busy ? null : _activate,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Activate'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (_activated) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'TV license activated and stored on this server. Your '
                    'TV will unlock the next time it connects.',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
