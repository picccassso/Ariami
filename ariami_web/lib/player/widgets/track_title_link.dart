import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_navigator.dart';
import 'adaptive_marquee_span.dart';

/// A track title that links to the track's album: pointer cursor plus an
/// underline on hover, and a tap opens the album view. Renders as plain text
/// when the track has no album, or when [enabled] is false (playlist views
/// opt out — titles there stay non-navigational).
class TrackTitleLink extends StatefulWidget {
  const TrackTitleLink({
    super.key,
    required this.title,
    required this.albumId,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.enabled = true,
    this.marquee = false,
    this.forceUnderline = false,
    this.onBeforeNavigate,
  });

  final String title;
  final String? albumId;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  final bool enabled;

  final bool marquee;

  /// Underlines the title as if hovered, e.g. while its cover art is hovered.
  final bool forceUnderline;

  /// Runs just before the album view opens — e.g. the fullscreen player pops
  /// its route so the album isn't hidden underneath it.
  final VoidCallback? onBeforeNavigate;

  @override
  State<TrackTitleLink> createState() => _TrackTitleLinkState();
}

class _TrackTitleLinkState extends State<TrackTitleLink> {
  bool _hover = false;

  bool get _links => widget.enabled && widget.albumId != null;

  @override
  Widget build(BuildContext context) {
    if (!_links) {
      if (widget.marquee && widget.maxLines == 1) {
        return AdaptiveMarqueeSpan(
          span: TextSpan(text: widget.title, style: widget.style),
        );
      }
      return Text(
        widget.title,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }

    final style = _hover || widget.forceUnderline
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
        child: widget.marquee && widget.maxLines == 1
            ? AdaptiveMarqueeSpan(
                span: TextSpan(text: widget.title, style: style),
              )
            : Text(
                widget.title,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.textAlign,
                style: style,
              ),
      ),
    );
  }
}
