import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// [cover], blurred once into a small, 60%-opaque image and scaled up to
/// fill. A live blur would be re-run by the GPU on every frame the player
/// draws (each seek-bar tick, every frame of a moving backdrop); blurred
/// first, the upscale shows no pixels.
class BlurredCover extends StatefulWidget {
  const BlurredCover(this.cover, {super.key});

  final ImageProvider cover;

  @override
  State<BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<BlurredCover> {
  static const _size = 48;
  // A sixteenth of the cover, as the live blur was at window size.
  static const _sigma = _size / 16;

  ImageStream? _stream;
  late final _listener = ImageStreamListener(_bake, onError: (_, __) {});
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BlurredCover old) {
    super.didUpdateWidget(old);
    if (old.cover != widget.cover) _resolve();
  }

  void _resolve() {
    final stream = ResizeImage(widget.cover, height: _size)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _bake(ImageInfo info, bool _) {
    final recorder = ui.PictureRecorder();
    final cover = info.image;
    // Centre-cropped square, like the covers themselves.
    final side = math.min(cover.width, cover.height).toDouble();
    Canvas(recorder).drawImageRect(
      cover,
      Rect.fromCenter(
        center: Offset(cover.width / 2, cover.height / 2),
        width: side,
        height: side,
      ),
      const Rect.fromLTWH(0, 0, _size + 0.0, _size + 0.0),
      Paint()
        // Baked in, so drawing it costs no extra layer.
        ..color = const Color(0x99000000)
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _sigma,
          sigmaY: _sigma,
          tileMode: TileMode.clamp,
        ),
    );
    info.dispose();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_size, _size);
    picture.dispose();
    if (!mounted) return image.dispose();
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
        image: _image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
}
