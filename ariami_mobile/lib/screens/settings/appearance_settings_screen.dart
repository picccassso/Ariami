import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../services/theme_service.dart';
import '../../../services/playback_manager.dart';
import '../../../services/color_extraction_service.dart';
import '../../../services/api/connection_service.dart';
import '../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../../widgets/common/cached_artwork.dart';
import '../../../widgets/settings/settings_section.dart';
import 'song_selection_screen.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
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

  Widget _buildStaticSongPreview() {
    final connectionService = ConnectionService();
    final albumId = _themeService.staticSongAlbumId;
    final songId = _themeService.staticSongId!;

    final String cacheId;
    final String? artworkUrl;
    if (albumId != null) {
      cacheId = albumId;
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/$albumId'
          : null;
    } else {
      cacheId = 'song_$songId';
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/$songId'
          : null;
    }

    return Row(
      children: [
        CachedArtwork(
          albumId: cacheId,
          artworkUrl: artworkUrl,
          width: 56,
          height: 56,
          borderRadius: BorderRadius.circular(6),
          fallbackIcon: Icons.music_note,
          fallbackIconSize: 28,
          sizeHint: ArtworkSizeHint.thumbnail,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _themeService.staticSongTitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _themeService.staticSongArtist!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
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
      body: ListenableBuilder(
        listenable: _playbackManager,
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerAwareBottomPadding(context) + 16,
            ),
            children: [
              SettingsSection(
                title: 'Theme Source',
                tiles: [
                  RadioListTile<ThemeSource>(
                    title: const Text('System'),
                    subtitle: const Text(
                        'Neutral black/white based on device appearance'),
                    value: ThemeSource.systemNeutral,
                    groupValue: _themeService.themeSource,
                    onChanged: (ThemeSource? value) {
                      if (value != null) _themeService.setThemeSource(value);
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  RadioListTile<ThemeSource>(
                    title: const Text('Light'),
                    subtitle: const Text('Neutral white theme'),
                    value: ThemeSource.lightNeutral,
                    groupValue: _themeService.themeSource,
                    onChanged: (ThemeSource? value) {
                      if (value != null) _themeService.setThemeSource(value);
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  RadioListTile<ThemeSource>(
                    title: const Text('Dark'),
                    subtitle: const Text('Neutral black theme'),
                    value: ThemeSource.darkNeutral,
                    groupValue: _themeService.themeSource,
                    onChanged: (ThemeSource? value) {
                      if (value != null) _themeService.setThemeSource(value);
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _presetColors.map((color) {
                          final isSelected =
                              _themeService.presetColor.toARGB32() ==
                                  color.toARGB32();
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
                                      : (isDark
                                          ? Colors.white24
                                          : Colors.black12),
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      color: color.computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white,
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
                        if (_themeService.customColor ==
                            const Color(0xFFFFFFFF)) {
                          _showColorPicker();
                        }
                      }
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  if (_themeService.themeSource == ThemeSource.custom)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
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
                    subtitle: const Text(
                        'Theme changes based on the currently playing song'),
                    value: ThemeSource.dynamicCoverArt,
                    groupValue: _themeService.themeSource,
                    onChanged: (ThemeSource? value) {
                      if (value != null) _themeService.setThemeSource(value);
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  RadioListTile<ThemeSource>(
                    title: const Text('Static Cover Art'),
                    subtitle:
                        const Text('Use the cover art of a specific song'),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ElevatedButton(
                              onPressed: _playbackManager.currentSong != null
                                  ? () async {
                                      final song =
                                          _playbackManager.currentSong!;
                                      final color =
                                          await ColorExtractionService()
                                              .getDominantColorForSong(
                                                  song.id, song.albumId);
                                      await _themeService.setStaticSong(
                                        song.id,
                                        song.title,
                                        song.artist,
                                        song.albumId,
                                        color,
                                      );
                                    }
                                  : null,
                              child: const Text('Use Current Song'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () async {
                                final selectedSong = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SongSelectionScreen(),
                                  ),
                                );

                                if (selectedSong != null && mounted) {
                                  final color = await ColorExtractionService()
                                      .getDominantColorForSong(selectedSong.id,
                                          selectedSong.albumId);
                                  await _themeService.setStaticSong(
                                    selectedSong.id,
                                    selectedSong.title,
                                    selectedSong.artist,
                                    selectedSong.albumId,
                                    color,
                                  );
                                }
                              },
                              child: const Text('Use Different Song'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_themeService.staticSongTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 16.0, right: 16.0, top: 12.0),
                      child: _buildStaticSongPreview(),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
