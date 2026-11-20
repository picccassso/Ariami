import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_navigator.dart';
import 'adaptive_marquee_span.dart';
import 'artist_link.dart';

/// Renders a raw artist credit string as one link per credited artist, so
/// "Kanye West, Big Sean" becomes two links separated by ", ". Falls back to
/// the raw string as a single [ArtistLink] — or plain text when [enabled] is
/// false — for names the splitter can't break apart.
class ArtistCreditLinks extends StatefulWidget {
  const ArtistCreditLinks({
    super.key,
    required this.name,
    this.style,
    this.enabled = true,
    this.textAlign,
    this.maxLines,
    this.marquee = false,
    this.onBeforeNavigate,
    this.trailingSuffix,
    this.albumTitle,
    this.albumId,
  });

  /// Raw display artist string, e.g. "Kanye West, Big Sean".
  final String name;
  final TextStyle? style;

  final bool enabled;
  final TextAlign? textAlign;
  
  final int? maxLines;
  
  /// Whether to use a marquee effect when overflowing (requires maxLines == 1).
  final bool marquee;

  /// Runs just before an artist view opens (see [ArtistLink]).
  final VoidCallback? onBeforeNavigate;
  
  final String? trailingSuffix;

  /// Optional album title to display after the artist credits (e.g. 'Music To Be Murdered By').
  /// Displayed prefixed by ' • '.
  final String? albumTitle;

  final String? albumId;

  @override
  State<ArtistCreditLinks> createState() => _ArtistCreditLinksState();
}

class _ArtistCreditLinksState extends State<ArtistCreditLinks> {
  late List<CreditedArtist> _credits;
  final List<TapGestureRecognizer> _recognizers = [];
  TapGestureRecognizer? _albumRecognizer;
  int? _hoveredIndex;
  bool _hoveredAlbum = false;

  @override
  void initState() {
    super.initState();
    _parseCredits();
    _setupAlbumRecognizer();
  }

  @override
  void didUpdateWidget(ArtistCreditLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name) {
      _parseCredits();
    }
    if (widget.albumId != oldWidget.albumId || widget.enabled != oldWidget.enabled) {
      _setupAlbumRecognizer();
    }
  }

  void _setupAlbumRecognizer() {
    _albumRecognizer?.dispose();
    _albumRecognizer = null;
    if (widget.albumId != null) {
      _albumRecognizer = TapGestureRecognizer()
        ..onTap = () {
          if (!widget.enabled) return;
          final navigator = context.read<PlayerNavigator>();
          widget.onBeforeNavigate?.call();
          navigator.openAlbum(widget.albumId!);
        };
    }
  }

  void _parseCredits() {
    _credits = CreditedArtistSplitter().split(widget.name);
    _disposeRecognizers();
    for (int i = 0; i < _credits.length; i++) {
      final name = _credits[i].display;
      _recognizers.add(TapGestureRecognizer()
        ..onTap = () {
          if (!widget.enabled) return;
          final navigator = context.read<PlayerNavigator>();
          widget.onBeforeNavigate?.call();
          navigator.openArtist(name);
        });
    }
    _hoveredIndex = null;
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _albumRecognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only use the ArtistLink fast-path if there's no album title to display.
    if (widget.albumTitle == null && (!widget.marquee || widget.maxLines != 1)) {
      if (!widget.enabled || _credits.isEmpty) {
        return ArtistLink(
          name: widget.name,
          style: widget.style,
          enabled: false,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          suffix: widget.trailingSuffix,
        );
      }
      if (_credits.length == 1) {
        return ArtistLink(
          name: widget.name,
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          onBeforeNavigate: widget.onBeforeNavigate,
          suffix: widget.trailingSuffix,
        );
      }
    }

    final spans = <InlineSpan>[];
    if (_credits.isEmpty) {
      spans.add(TextSpan(text: widget.name, style: widget.style));
    } else {
      for (var i = 0; i < _credits.length; i++) {
        final style = _hoveredIndex == i && widget.enabled
            ? (widget.style ?? const TextStyle())
                .copyWith(decoration: TextDecoration.underline)
            : widget.style;

        spans.add(
          TextSpan(
            text: _credits[i].display,
            style: style,
            recognizer: widget.enabled ? _recognizers[i] : null,
            mouseCursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: widget.enabled ? (_) => setState(() => _hoveredIndex = i) : null,
            onExit: widget.enabled
                ? (_) {
                    if (_hoveredIndex == i) setState(() => _hoveredIndex = null);
                  }
                : null,
          ),
        );

        if (i < _credits.length - 1) {
          spans.add(TextSpan(text: ', ', style: widget.style));
        }
      }
    }

    if (widget.albumTitle != null) {
      spans.add(TextSpan(text: ' • ', style: widget.style));
      final canLinkAlbum = widget.enabled && widget.albumId != null;
      final albumStyle = _hoveredAlbum && canLinkAlbum
          ? (widget.style ?? const TextStyle())
              .copyWith(decoration: TextDecoration.underline)
          : widget.style;

      spans.add(
        TextSpan(
          text: widget.albumTitle,
          style: albumStyle,
          recognizer: canLinkAlbum ? _albumRecognizer : null,
          mouseCursor: canLinkAlbum ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: canLinkAlbum ? (_) => setState(() => _hoveredAlbum = true) : null,
          onExit: canLinkAlbum
              ? (_) {
                  if (_hoveredAlbum) setState(() => _hoveredAlbum = false);
                }
              : null,
        ),
      );
    }

    if (widget.trailingSuffix != null) {
      spans.add(TextSpan(text: widget.trailingSuffix, style: widget.style));
    }

    final span = TextSpan(children: spans);

    if (widget.marquee && widget.maxLines == 1) {
      return AdaptiveMarqueeSpan(
        span: span,
        style: widget.style,
      );
    }

    return Text.rich(
      span,
      maxLines: widget.maxLines,
      overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
      textAlign: widget.textAlign,
    );
  }
}
