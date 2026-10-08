import 'package:flutter/widgets.dart';

/// Wraps [provider] so it decodes no wider than needed to show it
/// [logicalWidth] wide; unknown or unbounded widths decode at full size.
///
/// The 2x oversample keeps BoxFit.cover crops of non-square sources sharp.
ImageProvider resizedForDisplay(
  BuildContext context,
  ImageProvider provider,
  double? logicalWidth, {
  int maxWidth = 2048,
}) {
  if (logicalWidth == null || !logicalWidth.isFinite) return provider;
  final width = (logicalWidth * MediaQuery.devicePixelRatioOf(context) * 2)
      .round()
      .clamp(96, maxWidth);
  return ResizeImage.resizeIfNeeded(width, null, provider);
}

/// Bounds an avatar's decode (shown at ~72 logical px) on any device pixel
/// ratio, for call sites without a [BuildContext] (e.g. precaching).
ImageProvider avatarImage(ImageProvider provider) =>
    ResizeImage(provider, width: 512);
