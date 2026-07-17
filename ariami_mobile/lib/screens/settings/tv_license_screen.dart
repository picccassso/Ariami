import '../../utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/license/tv_license_service.dart';

/// Activates an Ariami TV license key from the phone.
///
/// The key is exchanged for a signed license file and stored on the
/// connected server; every TV in the household unlocks automatically the
/// next time it connects — no typing with a TV remote.
class TvLicenseScreen extends StatefulWidget {
  const TvLicenseScreen({super.key, TvLicenseService? service})
      : _service = service;

  final TvLicenseService? _service;

  @override
  State<TvLicenseScreen> createState() => _TvLicenseScreenState();
}

class _TvLicenseScreenState extends State<TvLicenseScreen> {
  late final TvLicenseService _service = widget._service ?? TvLicenseService();
  final TextEditingController _keyController = TextEditingController();

  bool _busy = false;
  bool _activated = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _activated = false;
    });
    final error = await _service.activateKey(_keyController.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _activated = error == null;
      if (error == null) _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = _service.hasServerConnection;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Activate Ariami TV'),
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
          icon: Icon(
            LucideIcons.chevronLeft,
            size: 20,
            color: colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ContentWidthLimiter(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.tv, size: 20, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Paste the TV license key from your purchase email. '
                    'It\'s activated once and stored on your server; every '
                    'TV in the household unlocks automatically the next '
                    'time it connects — nothing to type on the TV.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _keyController,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'TV license key',
              hintText: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _activate,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.keyRound, size: 18),
            label: Text(_busy ? 'Activating…' : 'Activate TV license'),
          ),
          if (!isConnected) ...[
            const SizedBox(height: 12),
            Text(
              'You\'re not connected to your Ariami server right now — '
              'connect first so the license can be stored there.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          if (_activated) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.circleCheck,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TV license activated and stored on your server. '
                      'Your TV will unlock the next time it connects.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      )),
    );
  }
}
