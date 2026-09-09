import 'package:flutter/material.dart';

import 'artist_picker_sheet.dart';

/// An artist name rendered as a tappable link to the artist's page.
///
/// If [name] credits multiple collaborating artists, tapping it presents a
/// picker bottom sheet so the user can choose which artist to view.
///
/// When [enabled] is false the name is a plain [Text], so screens without an
/// `/artist` route (settings tab, selection mode) can show it safely. Callers
/// can wrap this in `Flexible`/`Expanded`; the text stays single-line and
/// ellipsized. No hover styling — mobile only.
class ArtistLink extends StatelessWidget {
  const ArtistLink({
    super.key,
    required this.name,
    this.style,
    this.maxLines = 1,
    this.enabled = true,
  });

  final String name;
  final TextStyle? style;
  final int maxLines;
  final bool enabled;

  Future<void> _handleTap(BuildContext context) async {
    final selectedArtist = await openArtistOrPicker(
      context,
      artistName: name,
    );
    if (selectedArtist == null || !context.mounted) return;

    Navigator.of(context).pushNamed('/artist', arguments: selectedArtist);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );

    if (!enabled) return text;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: text,
    );
  }
}
