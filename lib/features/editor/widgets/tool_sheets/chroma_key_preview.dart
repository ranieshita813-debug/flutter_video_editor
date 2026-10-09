// widgets/chroma_key_preview.dart
//
// Wrap your VideoPlayer with this widget in the preview canvas:
//
//   ChromaKeyPreview(
//     chroma: clip.chromaKey,
//     background: bg,
//     child: VideoPlayer(controller),
//   )
//
// Requires Impeller (default on iOS and on Android with recent Flutter).
// On Skia, or if the shader fails to load, the child is shown unkeyed.
//
// pubspec.yaml:
//   flutter:
//     shaders:
//       - shaders/chroma_key.frag

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'chroma_key.dart';

enum ChromaBackground { checker, black, white, gray }

class ChromaKeyPreview extends StatefulWidget {
  const ChromaKeyPreview({
    super.key,
    required this.child,
    required this.chroma,
    this.background = ChromaBackground.checker,
  });

  final Widget child;
  final ChromaKey chroma;
  final ChromaBackground background;

  @override
  State<ChromaKeyPreview> createState() => _ChromaKeyPreviewState();
}

class _ChromaKeyPreviewState extends State<ChromaKeyPreview> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentProgram? _p;

  @override
  void initState() {
    super.initState();
    _program ??= ui.FragmentProgram.fromAsset('shaders/chroma_key.frag');
    _program!.then((p) {
      if (mounted) setState(() => _p = p);
    }).catchError((_) {});
  }

  ui.ImageFilter? _filter(ChromaKey k) {
    final p = _p;
    if (p == null) return null;
    try {
      final s = p.fragmentShader();
      int i = 2; // 0,1 = uSize (engine-provided)
      void f(double v) => s.setFloat(i++, v);
      f(k.keyColor.red / 255);
      f(k.keyColor.green / 255);
      f(k.keyColor.blue / 255);
      f(k.similarity / 100);
      f(k.smoothness / 100);
      f(k.highlight / 100);
      f(k.shadow / 100);
      f(k.pedestal / 100);
      f(k.choke / 100);
      f(k.soften / 100);
      f(k.contrast / 100);
      f(k.midPoint / 100);
      f(k.spill / 100);
      f(k.spillRange / 100);
      f(k.desaturate / 100);
      f(k.spillLuma / 100);
      f(k.saturation / 100);
      f(k.hue * math.pi / 180);
      f(k.luminance / 100);
      f(k.output.index.toDouble());
      return ui.ImageFilter.shader(s);
    } catch (_) {
      return null; // Skia / unsupported
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.chroma;
    if (!k.enabled) return widget.child;
    final filter = _filter(k);
    if (filter == null) return widget.child;

    final showBg = k.output == ChromaOutput.composite;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (showBg)
          Positioned.fill(child: _Background(widget.background)),
        ImageFiltered(imageFilter: filter, child: widget.child),
      ],
    );
  }
}

class _Background extends StatelessWidget {
  const _Background(this.type);
  final ChromaBackground type;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ChromaBackground.black:
        return const ColoredBox(color: Colors.black);
      case ChromaBackground.white:
        return const ColoredBox(color: Colors.white);
      case ChromaBackground.gray:
        return const ColoredBox(color: Color(0xFF7F7F7F));
      case ChromaBackground.checker:
        return CustomPaint(painter: _CheckerPainter());
    }
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 12.0;
    final a = Paint()..color = const Color(0xFF3A3A3D);
    final b = Paint()..color = const Color(0xFF2A2A2D);
    for (double y = 0; y < size.height; y += s) {
      for (double x = 0; x < size.width; x += s) {
        final odd = ((x / s).floor() + (y / s).floor()).isOdd;
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), odd ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}