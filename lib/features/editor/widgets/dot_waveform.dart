import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Filled, bottom-aligned (non-mirrored) audio waveform for a timeline clip.
///
/// [amplitudes] are normalized values (0.0 - 1.0), any length. They are
/// resampled to fit the available width, so pinch-zoom only needs to change
/// the width of this widget.
///
/// [progress] (0.0 - 1.0) paints the played part in solid [playedColor].
/// Pass null for a static clip with no playhead coloring.
class FilledAreaWaveform extends StatelessWidget {
  const FilledAreaWaveform({
    super.key,
    required this.amplitudes,
    this.progress,
    this.height = 40,
    this.columnWidth = 2.0,
    this.minHeight = 1.5,
    this.playedColor = Colors.white,
    this.unplayedColor = const Color(0x59FFFFFF), // white @ 35%
    this.onSeek,
  });

  final List<double> amplitudes;
  final double? progress;
  final double height;

  /// Horizontal distance between sampled points. Smaller = more detail.
  final double columnWidth;

  /// Minimum wave height in px so silence still shows a thin baseline.
  final double minHeight;

  final Color playedColor;
  final Color unplayedColor;

  /// Called with 0.0 - 1.0 when the user taps or drags on the waveform.
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;

        void seek(Offset p) {
          if (onSeek == null || width <= 0) return;
          onSeek!((p.dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
          onHorizontalDragUpdate:
              onSeek == null ? null : (d) => seek(d.localPosition),
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(width, height),
              painter: FilledAreaWaveformPainter(
                amplitudes: amplitudes,
                progress: progress,
                columnWidth: columnWidth,
                minHeight: minHeight,
                playedColor: playedColor,
                unplayedColor: unplayedColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class FilledAreaWaveformPainter extends CustomPainter {
  FilledAreaWaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.columnWidth,
    required this.minHeight,
    required this.playedColor,
    required this.unplayedColor,
  });

  final List<double> amplitudes;
  final double? progress;
  final double columnWidth;
  final double minHeight;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0 || size.height <= 0) return;

    final path = _buildPath(size);

    // Whole clip in the dim color.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = unplayedColor,
    );

    // Played part: same path, clipped at the playhead, in solid color.
    final p = progress;
    if (p != null && p > 0) {
      final playedX = p.clamp(0.0, 1.0) * size.width;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, playedX, size.height));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = playedColor,
      );
      canvas.restore();
    }
  }

  Path _buildPath(Size size) {
    final columns = math.max(2, (size.width / columnWidth).floor());
    final step = size.width / columns;
    final usable = size.height - 1; // small top margin

    double yAt(int c) {
      final h = math.max(minHeight, _sample(c, columns) * usable);
      return size.height - h;
    }

    final path = Path()..moveTo(0, size.height);
    path.lineTo(0, yAt(0));
    for (int c = 0; c < columns; c++) {
      path.lineTo((c + 0.5) * step, yAt(c));
    }
    path.lineTo(size.width, yAt(columns - 1));
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  /// Resample the amplitude list to [columns] by averaging the covered bucket.
  double _sample(int column, int columns) {
    final n = amplitudes.length;
    if (n == columns) return amplitudes[column].clamp(0.0, 1.0);
    final start = (column * n / columns).floor();
    final end = math.max(start + 1, ((column + 1) * n / columns).ceil());
    double sum = 0;
    int count = 0;
    for (int i = start; i < end && i < n; i++) {
      sum += amplitudes[i];
      count++;
    }
    return count == 0 ? 0 : (sum / count).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(FilledAreaWaveformPainter old) =>
      old.progress != progress ||
      old.amplitudes != amplitudes ||
      old.columnWidth != columnWidth ||
      old.minHeight != minHeight ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

/// Demo / usage example. Delete if you don't need it.
class FilledAreaWaveformDemo extends StatefulWidget {
  const FilledAreaWaveformDemo({super.key});

  @override
  State<FilledAreaWaveformDemo> createState() => _FilledAreaWaveformDemoState();
}

class _FilledAreaWaveformDemoState extends State<FilledAreaWaveformDemo> {
  late final List<double> _amps = _fakeAmps(240);
  double _progress = 0.38;

  static List<double> _fakeAmps(int n) {
    final r = math.Random(7);
    return List.generate(n, (i) {
      final env = 0.35 +
          0.65 * (math.sin(i / 9.5)).abs() * (0.6 + 0.4 * math.sin(i / 3.1 + 1));
      return (env * (0.45 + 0.55 * r.nextDouble())).clamp(0.06, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16161A),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF23232A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: FilledAreaWaveform(
            amplitudes: _amps,
            progress: _progress,
            height: 46,
            onSeek: (v) => setState(() => _progress = v),
          ),
        ),
      ),
    );
  }
}