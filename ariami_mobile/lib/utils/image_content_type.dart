import 'dart:typed_data';

const _jpegSignature = [0xFF, 0xD8, 0xFF];
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _riffSignature = [0x52, 0x49, 0x46, 0x46];
const _webpSignature = [0x57, 0x45, 0x42, 0x50];

bool _matches(Uint8List bytes, List<int> signature, [int offset = 0]) {
  if (bytes.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}

/// Whether [bytes] begin with the full 8-byte PNG signature.
bool hasPngSignature(Uint8List bytes) => _matches(bytes, _pngSignature);

/// Sniffs an image's content type from its magic bytes, falling back to the
/// [fileName] extension. [jpegPngOnly] limits it to JPEG/PNG (no WebP) and
/// requires the full PNG signature; otherwise a 4-byte PNG prefix suffices.
String? detectImageContentType(
  Uint8List bytes,
  String? fileName, {
  bool jpegPngOnly = false,
}) {
  if (_matches(bytes, _jpegSignature)) return 'image/jpeg';
  if (_matches(
      bytes, jpegPngOnly ? _pngSignature : _pngSignature.sublist(0, 4))) {
    return 'image/png';
  }
  if (!jpegPngOnly &&
      _matches(bytes, _riffSignature) &&
      _matches(bytes, _webpSignature, 8)) {
    return 'image/webp';
  }
  final lower = fileName?.toLowerCase() ?? '';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (!jpegPngOnly && lower.endsWith('.webp')) return 'image/webp';
  return null;
}
