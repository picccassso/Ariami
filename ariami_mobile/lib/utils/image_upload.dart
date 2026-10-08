import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The server's cap on an uploaded avatar, playlist cover or artist photo.
const int maxImageUploadBytes = 5 * 1024 * 1024;

/// Returns [bytes] unchanged unless it exceeds [maxBytes]; then re-encodes it
/// as a PNG with its longest edge bounded by the first of [edges] that fits.
///
/// Camera originals are usually over the cap; the server shrinks what it
/// stores anyway, so this only has to get the upload accepted. Falls back to
/// the original bytes when decoding fails or nothing fits, leaving the
/// caller's own size check to reject it.
Future<Uint8List> downscaleIfOversized(
  Uint8List bytes, {
  int maxBytes = maxImageUploadBytes,
  List<int> edges = const [1200, 800],
}) async {
  if (bytes.lengthInBytes <= maxBytes) return bytes;
  try {
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    final landscape = descriptor.width >= descriptor.height;
    final longest = max(descriptor.width, descriptor.height);
    for (final edge in edges) {
      final target = min(edge, longest); // never upscale
      final codec = await descriptor.instantiateCodec(
        targetWidth: landscape ? target : null,
        targetHeight: landscape ? null : target,
      );
      final image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();
      if (encoded != null && encoded.lengthInBytes <= maxBytes) {
        return encoded.buffer.asUint8List();
      }
    }
  } catch (_) {
    // Undecodable here; let the caller's size check report it.
  }
  return bytes;
}
