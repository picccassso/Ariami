import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/player_host.dart';
import '../../services/quick_jump_service.dart';
import '../../services/search_settings_service.dart';
import '../../services/sensitive_info_service.dart';
import '../../theme/player_theme.dart';
import 'settings_widgets.dart';

class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context) {
    final host = maybeReadHost(context);
    final topCard = host?.extraSettings?.buildGeneralTopCard(context);
    final hasLicense =
        host?.extraSettings?.buildLicenseSection(context) != null;
    final searchSettings =
        maybeWatchProvider<SearchSettingsService?>(context) ??
            maybeWatchProvider<SearchSettingsService>(context) ??
            SearchSettingsService();
    final quickJump =
        maybeWatchProvider<QuickJumpService?>(context) ??
            maybeWatchProvider<QuickJumpService>(context) ??
            QuickJumpService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topCard != null) ...[
          topCard,
          const SizedBox(height: 14),
        ],
        SettingsSectionCard(
          title: hasLicense ? 'Account & license privacy' : 'Account privacy',
          subtitle: 'Hidden by default so you can safely record or share '
              'your screen.',
          child: ListenableBuilder(
            listenable: SensitiveInfoService.instance,
            builder: (context, _) => Row(
              children: [
                const Expanded(
                  child: Text(
                    'Show account & license details',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Switch(
                  value: SensitiveInfoService.instance.visible,
                  onChanged: (value) => unawaited(
                    SensitiveInfoService.instance.setVisible(value),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'Recent searches limit',
          subtitle:
              'Choose how many recent searches to keep in your search history.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopSegmentedControl<bool>(
                options: [
                  const DesktopSegmentedOption(
                    value: false,
                    label: 'Standard (30)',
                  ),
                  DesktopSegmentedOption(
                    value: true,
                    label: searchSettings.isCustomRecentLimit
                        ? 'Custom (${searchSettings.customRecentLimit})'
                        : 'Custom',
                  ),
                ],
                selectedValue: searchSettings.isCustomRecentLimit,
                onChanged: (isCustom) {
                  if (isCustom) {
                    unawaited(_showCustomLimitDialog(context, searchSettings));
                  } else {
                    unawaited(
                      searchSettings.setRecentSearchesLimit(isCustom: false),
                    );
                  }
                },
              ),
              if (searchSettings.isCustomRecentLimit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Custom limit: ${searchSettings.customRecentLimit} tracks',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => unawaited(
                        _showCustomLimitDialog(context, searchSettings),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'Library quick jump',
          subtitle:
              'Hold a key to display numbers next to your library items and jump to them instantly with 1–9.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Enable quick jump shortcuts',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  Switch(
                    key: const Key('quick-jump-enabled-switch'),
                    value: quickJump.enabled,
                    onChanged: (value) => unawaited(
                      quickJump.setEnabled(value),
                    ),
                  ),
                ],
              ),
              if (quickJump.enabled) ...[
                const SizedBox(height: 14),
                Text(
                  'Trigger key',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                DesktopSegmentedControl<QuickJumpTriggerKey>(
                  options: [
                    for (final key in QuickJumpTriggerKey.values)
                      DesktopSegmentedOption(
                        value: key,
                        label: key.label,
                      ),
                  ],
                  selectedValue: quickJump.triggerKey,
                  onChanged: (key) => unawaited(
                    quickJump.setTriggerKey(key),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomLimitDialog(
    BuildContext context,
    SearchSettingsService searchSettings,
  ) async {
    final limit = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _CustomLimitDialog(
        initialLimit: searchSettings.customRecentLimit,
      ),
    );
    if (limit != null) {
      await searchSettings.setRecentSearchesLimit(
        isCustom: true,
        customLimit: limit,
      );
    }
  }
}

class _CustomLimitDialog extends StatefulWidget {
  const _CustomLimitDialog({required this.initialLimit});

  final int initialLimit;

  @override
  State<_CustomLimitDialog> createState() => _CustomLimitDialogState();
}

class _CustomLimitDialogState extends State<_CustomLimitDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLimit.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null ||
        parsed < SearchSettingsService.minRecentSearchesLimit ||
        parsed > SearchSettingsService.maxRecentSearchesLimit) {
      setState(() {
        _errorText =
            'Enter a number between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit}';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recent searches limit'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set a custom limit between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit} recent searches.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText:
                    'Limit (${SearchSettingsService.minRecentSearchesLimit} – ${SearchSettingsService.maxRecentSearchesLimit})',
                hintText: '30',
                errorText: _errorText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
              onChanged: (val) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
