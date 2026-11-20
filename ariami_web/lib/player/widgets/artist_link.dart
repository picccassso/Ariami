import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_navigator.dart';

/// An artist name that links to the artist's page: pointer cursor plus an
/// underline on hover, and a tap opens the artist view. Renders as plain text
/// when [enabled] is false (e.g. while selection mode is active).
class ArtistLink extends StatefulWidget {
  const ArtistLink({
    super.key,
    required this.name,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.enabled = true,
    this.onBeforeNavigate,
    this.suffix,
  });

  final String name;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  final bool enabled;

  /// Runs just before the artist view opens — e.g. the fullscreen player pops
  /// its route so the artist page isn't hidden underneath it.
  final VoidCallback? onBeforeNavigate;
  
  final String? suffix;

  @override
  State<ArtistLink> createState() => _ArtistLinkState();
}

class _ArtistLinkState extends State<ArtistLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      if (widget.suffix == null) {
        return Text(
          widget.name,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: widget.textAlign,
          style: widget.style,
        );
      }
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: widget.name),
            TextSpan(text: widget.suffix),
          ],
          style: widget.style,
        ),
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
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
          // Capture the navigator before onBeforeNavigate runs: the fullscreen
          // player pops its route there, which deactivates this context.
          final navigator = context.read<PlayerNavigator>();
          widget.onBeforeNavigate?.call();
          navigator.openArtist(widget.name);
        },
        child: widget.suffix == null
            ? Text(
                widget.name,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.textAlign,
                style: style,
              )
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: widget.name, style: style),
                    TextSpan(text: widget.suffix, style: widget.style),
                  ],
                ),
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.textAlign,
              ),
      ),
    );
  }
}
