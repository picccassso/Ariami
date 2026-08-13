import 'package:flutter/material.dart';

/// An artist name rendered as a tappable link to the artist's page.
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
      onTap: () => Navigator.of(context).pushNamed('/artist', arguments: name),
      child: text,
    );
  }
}
