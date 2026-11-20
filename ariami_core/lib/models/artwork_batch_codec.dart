import 'dart:convert';
import 'dart:typed_data';

class ArtworkBatchItem {
  const ArtworkBatchItem({
    required this.key,
    required this.bytes,
    this.contentType = 'image/jpeg',
  });

  final String key;
  final Uint8List? bytes;
  final String contentType;

  bool get found => bytes != null && bytes!.isNotEmpty;
}

/// Compact binary framing for `/api/artwork/batch` responses.
///
/// Format:
/// - uint32 count
/// - repeated count times:
///   - uint16 keyLen + utf8 key (`a:<albumId>` or `s:<songId>`)
///   - uint8 status (0 = missing, 1 = jpeg, 2 = webp)
///   - uint32 bodyLen + raw image bytes
class ArtworkBatchCodec {
  static const int _statusMissing = 0;
  static const int _statusJpeg = 1;
  static const int _statusWebp = 2;

  static String albumKey(String albumId) => 'a:$albumId';
  static String songKey(String songId) => 's:$songId';

  static Uint8List encode(List<ArtworkBatchItem> items) {
    final builder = BytesBuilder(copy: false);
    final header = ByteData(4)..setUint32(0, items.length, Endian.big);
    builder.add(header.buffer.asUint8List());

    for (final item in items) {
      final keyBytes = utf8.encode(item.key);
      final body = item.bytes;
      final status = !item.found
          ? _statusMissing
          : (item.contentType.contains('webp') ? _statusWebp : _statusJpeg);
      final meta = ByteData(2 + keyBytes.length + 1 + 4);
      meta.setUint16(0, keyBytes.length, Endian.big);
      final metaBytes = meta.buffer.asUint8List();
      metaBytes.setRange(2, 2 + keyBytes.length, keyBytes);
      meta.setUint8(2 + keyBytes.length, status);
      meta.setUint32(
        3 + keyBytes.length,
        status == _statusMissing ? 0 : body!.length,
        Endian.big,
      );
      builder.add(metaBytes);
      if (status != _statusMissing) {
        builder.add(body!);
      }
    }
    return builder.takeBytes();
  }

  static List<ArtworkBatchItem> decode(Uint8List data) {
    if (data.length < 4) return const <ArtworkBatchItem>[];
    final view = ByteData.sublistView(data);
    final count = view.getUint32(0, Endian.big);
    var offset = 4;
    final items = <ArtworkBatchItem>[];

    for (var i = 0; i < count; i++) {
      if (offset + 2 > data.length) break;
      final keyLen = view.getUint16(offset, Endian.big);
      offset += 2;
      if (offset + keyLen + 5 > data.length) break;
      final key = utf8.decode(Uint8List.sublistView(data, offset, offset + keyLen));
      offset += keyLen;
      final status = view.getUint8(offset);
      offset += 1;
      final bodyLen = view.getUint32(offset, Endian.big);
      offset += 4;
      if (offset + bodyLen > data.length) break;
      final bytes = status == _statusMissing || bodyLen == 0
          ? null
          : Uint8List.fromList(
              Uint8List.sublistView(data, offset, offset + bodyLen),
            );
      offset += bodyLen;
      items.add(ArtworkBatchItem(
        key: key,
        bytes: bytes,
        contentType: status == _statusWebp ? 'image/webp' : 'image/jpeg',
      ));
    }
    return items;
  }
}
