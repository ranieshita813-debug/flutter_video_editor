// widgets/chroma_key_preview.dart
//
//   ChromaKeyPreview(
//     chroma: clip.chromaKey,
//     background: bg,
//     child: VideoPlayer(controller),
//   )
//
// Requires Impeller. On Skia, or if the shader fails to load, the child is
// shown unkeyed.
//
// pubspec.yaml:
//   flutter:
//     shaders:
//       - shaders/chroma_key.frag

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';

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
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _program ??= ui.FragmentProgram.fromAsset('shaders/chroma_key.frag');
    _program!.then((p) {
      if (mounted) setState(() => _p = p);
    }).catchError((_) {
      // Allow a retry next time (hot reload, etc.).
      _program = null;
    });
  }

  @override
  void dispose() {
    _disposeShader(_shader);
    _shader = null;
    super.dispose();
  }

  // FIX: the previous shader may still be referenced by the frame being
  // rendered, so dispose it only after the frame has finished.
  void _disposeShader(ui.FragmentShader? s) {
    if (s == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => s.dispose());
  }

  ui.ImageFilter? _filter(ChromaKey k, Size size) {
    final p = _p;
    if (p == null) return null;
    try {
      final old = _shader;
      final s = p.fragmentShader();
      _shader = s;
      _disposeShader(old);

      final double width = math.max(1.0, size.width);
      final double height = math.max(1.0, size.height);
      s.setFloat(0, width);
      s.setFloat(1, height);
      int i = 2;
      void f(double v) => s.setFloat(i++, v);
      f(k.keyColor.r);
      f(k.keyColor.g);
      f(k.keyColor.b);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 1920.0,
          constraints.hasBoundedHeight && constraints.maxHeight > 0
              ? constraints.maxHeight
              : 1080.0,
        );
        final filter = _filter(k, size);
        if (filter == null) return widget.child;

        final showBg = k.output == ChromaOutput.composite;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (showBg) Positioned.fill(child: _Background(widget.background)),
            ImageFiltered(imageFilter: filter, child: widget.child),
          ],
        );
      },
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
        return const RepaintBoundary(child: CustomPaint(painter: _CheckerPainter()));
    }
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

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