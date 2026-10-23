import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dot-style audio waveform for a timeline audio clip.
///
/// [amplitudes] are normalized values (0.0 - 1.0), any length. They are
/// resampled to fit the available width, so pinch-zoom only needs to change
/// the width of this widget.
///
/// [progress] (0.0 - 1.0) colors the played part. Pass null for a static clip
/// with no playhead coloring.
class DotsWaveform extends StatelessWidget {
  const DotsWaveform({
    super.key,
    required this.amplitudes,
    this.progress,
    this.height = 40,
    this.columnSpacing = 4.0,
    this.dotSpacing = 4.0,
    this.dotSize = 2.4,
    this.playedColor = const Color(0xFFFFB86B),
    this.unplayedColor = const Color(0xFF9A6A34),
    this.onSeek,
  });

  final List<double> amplitudes;
  final double? progress;
  final double height;

  /// Horizontal distance between dot columns.
  final double columnSpacing;

  /// Vertical distance between dots in one column.
  final double dotSpacing;

  /// Dot diameter.
  final double dotSize;

  final Color playedColor;
  final Color unplayedColor;

  /// Called with 0.0 - 1.0 when the user taps or drags on the waveform.
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;

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
              painter: DotsWaveformPainter(
                amplitudes: amplitudes,
                progress: progress,
                columnSpacing: columnSpacing,
                dotSpacing: dotSpacing,
                dotSize: dotSize,
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

class DotsWaveformPainter extends CustomPainter {
  DotsWaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.columnSpacing,
    required this.dotSpacing,
    required this.dotSize,
    required this.playedColor,
    required this.unplayedColor,
  });

  final List<double> amplitudes;
  final double? progress;
  final double columnSpacing;
  final double dotSpacing;
  final double dotSize;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0 || size.height <= 0) return;

    final columns = math.max(1, (size.width / columnSpacing).floor());
    final centerY = size.height / 2;
    // Max dots above (and below) the center line, leaving a small margin.
    final maxHalfDots =
        math.max(1, ((size.height / 2 - dotSize) / dotSpacing).floor());

    final playedX = progress == null ? -1.0 : progress!.clamp(0.0, 1.0) * size.width;

    final played = <Offset>[];
    final unplayed = <Offset>[];

    for (int c = 0; c < columns; c++) {
      final x = (c + 0.5) * (size.width / columns);
      final amp = _sample(c, columns);
      final half = (amp * maxHalfDots).round().clamp(0, maxHalfDots);
      final target = x <= playedX ? played : unplayed;

      // Center dot is always drawn so silence still shows a baseline.
      target.add(Offset(x, centerY));
      for (int k = 1; k <= half; k++) {
        target.add(Offset(x, centerY - k * dotSpacing));
        target.add(Offset(x, centerY + k * dotSpacing));
      }
    }

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dotSize
      ..isAntiAlias = true;

    // One draw call per color keeps this cheap even for long clips.
    canvas.drawPoints(ui.PointMode.points, unplayed, paint..color = unplayedColor);
    canvas.drawPoints(ui.PointMode.points, played, paint..color = playedColor);
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
  bool shouldRepaint(DotsWaveformPainter old) =>
      old.progress != progress ||
      old.amplitudes != amplitudes ||
      old.columnSpacing != columnSpacing ||
      old.dotSpacing != dotSpacing ||
      old.dotSize != dotSize ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

/// Demo / usage example. Delete if you don't need it.
class DotsWaveformDemo extends StatefulWidget {
  const DotsWaveformDemo({super.key});

  @override
  State<DotsWaveformDemo> createState() => _DotsWaveformDemoState();
}

class _DotsWaveformDemoState extends State<DotsWaveformDemo> {
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
          child: DotsWaveform(
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