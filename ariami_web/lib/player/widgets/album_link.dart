import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_navigator.dart';

/// An album title that links to the album's page: pointer cursor plus an
/// underline on hover, and a tap opens the album view. Renders as plain text
/// when [albumId] is null or [enabled] is false (e.g. while selection mode is active).
class AlbumLink extends StatefulWidget {
  const AlbumLink({
    super.key,
    required this.title,
    required this.albumId,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.enabled = true,
    this.onBeforeNavigate,
    this.suffix,
  });

  final String title;
  final String? albumId;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  final bool enabled;

  /// Runs just before the album view opens — e.g. the fullscreen player pops
  /// its route so the album isn't hidden underneath it.
  final VoidCallback? onBeforeNavigate;

  final String? suffix;

  @override
  State<AlbumLink> createState() => _AlbumLinkState();
}

class _AlbumLinkState extends State<AlbumLink> {
  bool _hover = false;

  bool get _links => widget.enabled && widget.albumId != null;

  @override
  Widget build(BuildContext context) {
    if (!_links) {
      if (widget.suffix == null) {
        return Text(
          widget.title,
          maxLines: widget.maxLines,
          overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
          textAlign: widget.textAlign,
          style: widget.style,
        );
      }
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: widget.title),
            TextSpan(text: widget.suffix),
          ],
          style: widget.style,
        ),
        maxLines: widget.maxLines,
        overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
        textAlign: widget.textAlign,
      );
    }

    final style = _hover
        ? (widget.style ?? const TextStyle())
            .copyWith(decoration: TextDecoration.underline)
        : widget.style;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          final navigator = context.read<PlayerNavigator>();
          widget.onBeforeNavigate?.call();
          navigator.openAlbum(widget.albumId!);
        },
        child: widget.suffix == null
            ? Text(
                widget.title,
                maxLines: widget.maxLines,
                overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
                textAlign: widget.textAlign,
                style: style,
              )
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: widget.title, style: style),
                    TextSpan(text: widget.suffix, style: widget.style),
                  ],
                ),
                maxLines: widget.maxLines,
                overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
                textAlign: widget.textAlign,
              ),
      ),
    );
  }
}
