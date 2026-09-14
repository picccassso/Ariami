import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/settings/search_settings_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

/// General settings gathered in one place (as on desktop) rather than
/// spread across the main settings list.
class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  final SearchSettingsService _searchSettingsService = SearchSettingsService();

  @override
  void initState() {
    super.initState();
    _searchSettingsService.initialize();
  }

  /// Displays a dialog to choose the search keyboard focus mode.
  Future<void> _showSearchModeDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Search Mode'),
        content: RadioGroup<SearchMode>(
          groupValue: _searchSettingsService.mode,
          onChanged: (newMode) {
            if (newMode == null) return;
            _searchSettingsService.setMode(newMode);
            Navigator.of(dialogContext).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: SearchMode.values.map((mode) {
              return RadioListTile<SearchMode>(
                title: Text(
                  mode.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  mode.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                value: mode,
                activeColor: colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Displays a dialog to choose the recent searches limit.
  Future<void> _showRecentSearchesLimitDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    bool isCustom = _searchSettingsService.isCustomRecentLimit;
    final controller = TextEditingController(
      text: _searchSettingsService.customRecentLimit.toString(),
    );
    final focusNode = FocusNode();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() async {
            if (isCustom) {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null ||
                  parsed < SearchSettingsService.minRecentSearchesLimit ||
                  parsed > SearchSettingsService.maxRecentSearchesLimit) {
                setDialogState(() {
                  errorText =
                      'Enter a number between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit}';
                });
                return;
              }
              Navigator.of(dialogContext).pop();
              await _searchSettingsService.setRecentSearchesLimit(
                isCustom: true,
                customLimit: parsed,
              );
            } else {
              Navigator.of(dialogContext).pop();
              await _searchSettingsService.setRecentSearchesLimit(
                isCustom: false,
              );
            }
          }

          return AlertDialog(
            title: const Text('Recent Searches Limit'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioGroup<bool>(
                    groupValue: isCustom,
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() {
                        isCustom = val;
                        if (isCustom) {
                          final parsed = int.tryParse(controller.text.trim());
                          if (parsed == null ||
                              parsed < SearchSettingsService.minRecentSearchesLimit ||
                              parsed > SearchSettingsService.maxRecentSearchesLimit) {
                            errorText =
                                'Enter a number between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit}';
                          } else {
                            errorText = null;
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (focusNode.canRequestFocus) {
                              focusNode.requestFocus();
                            }
                          });
                        } else {
                          errorText = null;
                        }
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<bool>(
                          title: const Text(
                            'Standard (30)',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Default limit of 30 recent searches',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          value: false,
                          activeColor: colorScheme.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<bool>(
                          title: const Text(
                            'Custom',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Set a custom limit between 5 and 500',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          value: true,
                          activeColor: colorScheme.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Limit (5 - 500)',
                          hintText: '30',
                          errorText: errorText,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            final parsed = int.tryParse(value.trim());
                            if (parsed == null ||
                                parsed < SearchSettingsService.minRecentSearchesLimit ||
                                parsed > SearchSettingsService.maxRecentSearchesLimit) {
                              errorText =
                                  'Enter a number between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit}';
                            } else {
                              errorText = null;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    focusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('General'),
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
        child: ListenableBuilder(
          listenable: _searchSettingsService,
          builder: (context, _) => ListView(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerScrollBottomPadding(context),
            ),
            children: [
              SettingsSection(
                title: 'GENERAL',
                tiles: [
                  SettingsTile(
                    icon: Icons.search_rounded,
                    title: 'Search Mode',
                    subtitle: _searchSettingsService.mode.label,
                    onTap: _showSearchModeDialog,
                  ),
                  SettingsTile(
                    icon: Icons.history_rounded,
                    title: 'Recent Searches Limit',
                    subtitle: _searchSettingsService.recentSearchesLimitLabel,
                    onTap: _showRecentSearchesLimitDialog,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
