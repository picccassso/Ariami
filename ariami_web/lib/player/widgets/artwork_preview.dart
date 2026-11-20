import 'package:flutter/material.dart';

import '../services/player_api_client.dart';
import 'artwork.dart';

/// Opens a centered, dimmed preview of an album/track cover (Spotify-style):
/// the artwork scales up in the middle of the screen over a darkened backdrop.
/// Tapping anywhere — the image or the backdrop — or pressing Esc dismisses it.
Future<void> showArtworkPreview(
  BuildContext context, {
  required PlayerApiClient? client,
  String? albumId,
  String? songId,
  String? imageUrl,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      // Fit a large square within the smaller window dimension so the cover is
      // big but never runs off-screen or overlaps the window chrome.
      final shortest = MediaQuery.sizeOf(dialogContext).shortestSide;
      final side = (shortest * 0.78).clamp(260.0, 720.0);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 48,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              // The tap on the image itself shouldn't bubble oddly; the outer
              // GestureDetector already closes on any tap, so a plain Artwork is
              // fine here.
              child: imageUrl != null && client != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image(
                        image: Artwork.cachedImage(
                          imageUrl,
                          client,
                          cacheWidth: (side *
                                  MediaQuery.devicePixelRatioOf(context) *
                                  2)
                              .round(),
                        ),
                        width: side,
                        height: side,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, __) => Artwork(
                          client: client,
                          albumId: albumId,
                          songId: songId,
                          thumbnail: false,
                          size: side,
                          borderRadius: 12,
                          iconScale: 0.35,
                        ),
                      ),
                    )
                  : Artwork(
                      client: client,
                      albumId: albumId,
                      songId: songId,
                      thumbnail: false,
                      size: side,
                      borderRadius: 12,
                      iconScale: 0.35,
                    ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
