import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/theme_controller.dart';
import '../../theme/player_theme.dart';
import 'custom_color_control.dart';
import 'settings_widgets.dart';

enum _AccentChoice {
  neutral,
  preset,
  custom,
  coverArt,
}

class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  AppearanceSource _lastNeutral = AppearanceSource.darkNeutral;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = context.read<ThemeController>().source;
    if (source == AppearanceSource.darkNeutral ||
        source == AppearanceSource.lightNeutral ||
        source == AppearanceSource.systemNeutral) {
      _lastNeutral = source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();

    if (theme.source == AppearanceSource.darkNeutral ||
        theme.source == AppearanceSource.lightNeutral ||
        theme.source == AppearanceSource.systemNeutral) {
      _lastNeutral = theme.source;
    }

    final currentThemeMode = switch (theme.source) {
      AppearanceSource.lightNeutral => AppearanceSource.lightNeutral,
      AppearanceSource.systemNeutral => AppearanceSource.systemNeutral,
      AppearanceSource.darkNeutral => AppearanceSource.darkNeutral,
      _ => _lastNeutral,
    };

    final currentAccent = switch (theme.source) {
      AppearanceSource.preset => _AccentChoice.preset,
      AppearanceSource.custom => _AccentChoice.custom,
      AppearanceSource.dynamicCoverArt => _AccentChoice.coverArt,
      _ => _AccentChoice.neutral,
    };

    return SettingsSectionCard(
      title: 'Appearance',
      subtitle: 'Choose how the player looks. Cover-art mode tints the app '
          'using the colours of the track that is playing.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme mode',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DesktopSegmentedControl<AppearanceSource>(
            options: const [
              DesktopSegmentedOption(
                value: AppearanceSource.darkNeutral,
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
              ),
              DesktopSegmentedOption(
                value: AppearanceSource.lightNeutral,
                label: 'Light',
                icon: Icons.light_mode_outlined,
              ),
              DesktopSegmentedOption(
                value: AppearanceSource.systemNeutral,
                label: 'System',
                icon: Icons.brightness_auto_outlined,
              ),
            ],
            selectedValue: currentThemeMode,
            onChanged: (source) => theme.setSource(source),
            minSegmentWidth: 80,
          ),
          const SizedBox(height: 20),
          Text(
            'Colour',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DesktopSegmentedControl<_AccentChoice>(
            options: const [
              DesktopSegmentedOption(
                value: _AccentChoice.neutral,
                label: 'Neutral',
              ),
              DesktopSegmentedOption(
                value: _AccentChoice.preset,
                label: 'Preset',
              ),
              DesktopSegmentedOption(
                value: _AccentChoice.custom,
                label: 'Custom',
              ),
              DesktopSegmentedOption(
                value: _AccentChoice.coverArt,
                label: 'Cover art',
              ),
            ],
            selectedValue: currentAccent,
            onChanged: (accent) {
              switch (accent) {
                case _AccentChoice.neutral:
                  theme.setSource(_lastNeutral);
                case _AccentChoice.preset:
                  theme.setSource(AppearanceSource.preset);
                case _AccentChoice.custom:
                  theme.setSource(AppearanceSource.custom);
                case _AccentChoice.coverArt:
                  theme.setSource(AppearanceSource.dynamicCoverArt);
              }
            },
            minSegmentWidth: 72,
          ),
          if (currentAccent == _AccentChoice.preset) ...[
            const SizedBox(height: 16),
            Text(
              'Preset colour',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in ThemeController.presetSwatches)
                  ColorSwatchButton(
                    color: color,
                    selected: theme.presetColor.toARGB32() == color.toARGB32(),
                    onTap: () => theme.setPresetColor(color),
                  ),
              ],
            ),
          ],
          if (currentAccent == _AccentChoice.custom) ...[
            const SizedBox(height: 16),
            Text(
              'Custom colour',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            CustomColorControl(
              color: theme.customColor,
              onChanged: (c) => theme.setCustomColor(c),
            ),
          ],
          const SizedBox(height: 20),
          _SwitchRow(
            title: 'Moving background',
            description:
                'The full-screen player\'s background drifts and pulses '
                'with the kick drum while music plays on this device.',
            value: theme.movingBackdrop,
            onChanged: theme.setMovingBackdrop,
          ),
          const SizedBox(height: 16),
          _SwitchRow(
            title: 'Music visualizer',
            description:
                'The full-screen player\'s background splits the music into '
                'drums, bass, vocals and instruments and moves with each while '
                'music plays on this device. Flashes on the beat and uses more '
                'power.',
            value: theme.musicVisualizer,
            onChanged: (on) async {
              if (on && !await _confirmVisualizer(context)) return;
              theme.setMusicVisualizer(on);
            },
          ),
        ],
      ),
    );
  }
}

/// Asks before turning the visualizer on, as it can harm people sensitive
/// to flashing light and runs the GPU for as long as music plays.
Future<bool> _confirmVisualizer(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Turn on the music visualizer?'),
      content: const Text(
        'The background flashes and moves quickly with the beat. If you or '
        'anyone watching is sensitive to flashing lights, leave this off.\n\n'
        'It also keeps your graphics card busy for as long as music plays, '
        'which uses more power and battery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
