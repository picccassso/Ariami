import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ariami_mobile/utils/image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  for (var x = 0; x < width; x += 7) {
    paint.color = ui.Color(0xFF000000 | (x * 2654435761 & 0xFFFFFF));
    canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 7, height.toDouble()), paint);
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(int, int)> _size(Uint8List bytes) async {
  final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes));
  return (descriptor.width, descriptor.height);
}

void main() {
  test('leaves images within the cap untouched', () async {
    final bytes = await _png(400, 300);
    expect(identical(await downscaleIfOversized(bytes), bytes), isTrue);
  });

  test('downscales an oversized image to a bounded PNG without upscaling',
      () async {
    final landscape = await _png(2400, 1600);
    final shrunk =
        await downscaleIfOversized(landscape, maxBytes: landscape.length - 1);
    expect(await _size(shrunk), (1200, 800));

    final portrait = await _png(1500, 3000);
    final shrunkPortrait =
        await downscaleIfOversized(portrait, maxBytes: portrait.length - 1);
    expect(await _size(shrunkPortrait), (600, 1200));
  });

  test('returns the original when nothing fits or it cannot be decoded',
      () async {
    final bytes = await _png(2400, 1600);
    expect(identical(await downscaleIfOversized(bytes, maxBytes: 10), bytes),
        isTrue);

    final garbage = Uint8List.fromList(List.filled(100, 7));
    expect(
        identical(await downscaleIfOversized(garbage, maxBytes: 10), garbage),
        isTrue);
  });
}
