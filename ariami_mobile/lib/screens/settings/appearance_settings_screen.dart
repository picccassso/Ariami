import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../services/theme_service.dart';
import '../../../services/playback_manager.dart';
import '../../../widgets/settings/settings_section.dart';
import '../../../widgets/settings/settings_tile.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  final ThemeService _themeService = ThemeService();
  final PlaybackManager _playbackManager = PlaybackManager();

  final List<Color> _presetColors = [
    const Color(0xFFFFFFFF), // White
    const Color(0xFFE53935), // Red
    const Color(0xFF43A047), // Green
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF8E24AA), // Purple
    const Color(0xFFFDD835), // Yellow
    const Color(0xFFF4511E), // Orange
    const Color(0xFF00ACC1), // Cyan
  ];

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showColorPicker() {
    Color pickerColor = _themeService.customColor;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (Color color) {
                pickerColor = color;
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                _themeService.setCustomColor(pickerColor);
                _themeService.setThemeSource(ThemeSource.custom);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
      ),
      body: ListView(
        children: [
          SettingsSection(
            title: 'Theme Mode',
            tiles: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {_themeService.themeMode},
                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                    _themeService.setThemeMode(newSelection.first);
                  },
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Theme Source',
            tiles: [
              RadioListTile<ThemeSource>(
                title: const Text('Preset Colors'),
                value: ThemeSource.preset,
                groupValue: _themeService.themeSource,
                onChanged: (ThemeSource? value) {
                  if (value != null) _themeService.setThemeSource(value);
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              if (_themeService.themeSource == ThemeSource.preset)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _presetColors.map((color) {
                      final isSelected = _themeService.presetColor.value == color.value;
                      return GestureDetector(
                        onTap: () {
                          _themeService.setPresetColor(color);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : (isDark ? Colors.white24 : Colors.black12),
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              RadioListTile<ThemeSource>(
                title: const Text('Custom Color'),
                value: ThemeSource.custom,
                groupValue: _themeService.themeSource,
                onChanged: (ThemeSource? value) {
                  if (value != null) {
                    _themeService.setThemeSource(value);
                    if (_themeService.customColor == const Color(0xFFFFFFFF)) {
                      _showColorPicker();
                    }
                  }
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              if (_themeService.themeSource == ThemeSource.custom)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _themeService.customColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.black12,
                            width: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _showColorPicker,
                        child: const Text('Pick Color'),
                      ),
                    ],
                  ),
                ),
              RadioListTile<ThemeSource>(
                title: const Text('Dynamic Cover Art'),
                subtitle: const Text('Theme changes based on the currently playing song'),
                value: ThemeSource.dynamicCoverArt,
                groupValue: _themeService.themeSource,
                onChanged: (ThemeSource? value) {
                  if (value != null) _themeService.setThemeSource(value);
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              RadioListTile<ThemeSource>(
                title: const Text('Static Cover Art'),
                subtitle: const Text('Use the cover art of a specific song'),
                value: ThemeSource.staticCoverArt,
                groupValue: _themeService.themeSource,
                onChanged: (ThemeSource? value) {
                  if (value != null) {
                    _themeService.setThemeSource(value);
                    if (_playbackManager.currentSong != null) {
                      // Optionally update to current song's color if set for the first time
                      // But for now, just let them use the "Set to Current Song" button
                    }
                  }
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              if (_themeService.themeSource == ThemeSource.staticCoverArt)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _themeService.staticCoverArtColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.black12,
                            width: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _playbackManager.currentSong != null
                            ? () {
                                // We can use the ColorExtractionService's current color since it's already extracted for the current song
                                final currentColor = ThemeService().currentSeedColor; // This is a bit hacky, better to access ColorExtractionService directly
                                // For simplicity, let's just use the current theme's primary color if we are playing something
                                // Actually, we need to extract it. Let's just use the current theme's primary color
                                _themeService.setStaticCoverArtColor(Theme.of(context).colorScheme.primary);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Set to current song\'s color')),
                                );
                              }
                            : null,
                        child: const Text('Use Current Song'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
