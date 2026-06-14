import 'package:flutter/material.dart';

import '../services/autostart_service.dart';
import 'info_card.dart';

/// Self-contained card with a toggle that controls whether Ariami Desktop
/// launches automatically when the user logs in / the machine boots.
///
/// Manages its own state so it can be dropped into the Server tab without
/// threading state through the dashboard widget tree.
class AutostartCard extends StatefulWidget {
  const AutostartCard({super.key});

  @override
  State<AutostartCard> createState() => _AutostartCardState();
}

class _AutostartCardState extends State<AutostartCard> {
  final AutostartService _autostartService = AutostartService();

  bool _isEnabled = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await _autostartService.isEnabled();
    if (!mounted) return;
    setState(() {
      _isEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _handleToggle(bool value) async {
    setState(() => _isSaving = true);
    try {
      final result = await _autostartService.setEnabled(value);
      if (!mounted) return;
      setState(() {
        _isEnabled = result;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${value ? 'enable' : 'disable'} start at login. '
            'Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide entirely on unsupported platforms.
    if (!_autostartService.isSupported) {
      return const SizedBox.shrink();
    }

    return InfoCard(
      title: 'Start at Login',
      value: _isLoading
          ? 'Checking...'
          : (_isEnabled ? 'Enabled' : 'Disabled'),
      icon: Icons.power_settings_new_rounded,
      isActive: _isEnabled,
      subtitle: 'Launch Ariami Desktop automatically when you sign in',
      trailing: _isSaving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: _isEnabled,
              onChanged: _isLoading ? null : _handleToggle,
            ),
    );
  }
}
