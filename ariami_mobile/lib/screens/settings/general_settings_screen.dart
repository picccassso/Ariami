import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/settings/search_settings_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

/// Key for the recent searches limit sheet content (used by tests).
const recentSearchesLimitSheetKey = Key('recent_searches_limit_sheet');

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

  /// Shows a bottom sheet to choose the search keyboard focus mode.
  Future<void> _showSearchModeSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    return showAriamiSheet<void>(
      context: context,
      backgroundColor: colorScheme.surface,
      header: const AriamiSheetSectionTitle('Search Mode'),
      items: SearchMode.values.map((mode) {
        final isSelected = mode == _searchSettingsService.mode;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            child: ListTile(
              leading: Icon(
                mode == SearchMode.standard
                    ? Icons.search_rounded
                    : Icons.bolt_rounded,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              title: Text(
                mode.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                mode.description,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimary.withValues(alpha: 0.7)
                      : colorScheme.onSurfaceVariant,
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
                _searchSettingsService.setMode(mode);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Shows a bottom sheet to choose the recent searches limit.
  Future<void> _showRecentSearchesLimitSheet() async {
    final colorScheme = Theme.of(context).colorScheme;
    bool isCustom = _searchSettingsService.isCustomRecentLimit;
    final controller = TextEditingController(
      text: _searchSettingsService.customRecentLimit.toString(),
    );
    final focusNode = FocusNode();
    String? errorText;
    final rangeError =
        'Enter a number between ${SearchSettingsService.minRecentSearchesLimit} and ${SearchSettingsService.maxRecentSearchesLimit}';

    await showAriamiSheet<void>(
      context: context,
      backgroundColor: colorScheme.surface,
      header: const AriamiSheetSectionTitle('Recent Searches Limit'),
      child: Container(
        key: recentSearchesLimitSheetKey,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void submit() async {
              if (isCustom) {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null ||
                    parsed < SearchSettingsService.minRecentSearchesLimit ||
                    parsed > SearchSettingsService.maxRecentSearchesLimit) {
                  setSheetState(() => errorText = rangeError);
                  return;
                }
                Navigator.of(sheetContext).pop();
                await _searchSettingsService.setRecentSearchesLimit(
                  isCustom: true,
                  customLimit: parsed,
                );
              } else {
                Navigator.of(sheetContext).pop();
                await _searchSettingsService.setRecentSearchesLimit(
                  isCustom: false,
                );
              }
            }

            Widget optionTile({
              required bool value,
              required IconData icon,
              required String title,
              required String subtitle,
            }) {
              final selected = isCustom == value;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Material(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: ListTile(
                    leading: Icon(
                      icon,
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? colorScheme.onPrimary : colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? colorScheme.onPrimary.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: colorScheme.onPrimary,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      setSheetState(() {
                        isCustom = value;
                        if (isCustom) {
                          final parsed = int.tryParse(controller.text.trim());
                          if (parsed == null ||
                              parsed < SearchSettingsService.minRecentSearchesLimit ||
                              parsed > SearchSettingsService.maxRecentSearchesLimit) {
                            errorText = rangeError;
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                optionTile(
                  value: false,
                  icon: Icons.history_rounded,
                  title: 'Standard (30)',
                  subtitle: 'Default limit of 30 recent searches',
                ),
                optionTile(
                  value: true,
                  icon: Icons.tune_rounded,
                  title: 'Custom',
                  subtitle: 'Set a custom limit between 5 and 500',
                ),
                if (isCustom) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                        setSheetState(() {
                          final parsed = int.tryParse(value.trim());
                          errorText =
                              parsed == null ||
                                  parsed < SearchSettingsService.minRecentSearchesLimit ||
                                  parsed > SearchSettingsService.maxRecentSearchesLimit
                              ? rangeError
                              : null;
                        });
                      },
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: submit,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
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
                    onTap: _showSearchModeSheet,
                  ),
                  SettingsTile(
                    icon: Icons.history_rounded,
                    title: 'Recent Searches Limit',
                    subtitle: _searchSettingsService.recentSearchesLimitLabel,
                    onTap: _showRecentSearchesLimitSheet,
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
