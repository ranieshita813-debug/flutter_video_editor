import 'package:flutter/material.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class RulerPainter extends CustomPainter {
  RulerPainter({
    required this.pps,
    required this.seconds,
    required this.leftPad,
    required this.fps,
  });

  final double pps;
  final double seconds;
  final double leftPad;
  final int fps;

  final Map<String, TextPainter> _textCache = <String, TextPainter>{};

  @override
  void paint(Canvas canvas, Size size) {
    const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step = steps.firstWhere((s) => s * pps >= 64, orElse: () => steps.last);
    final Paint dot = Paint()..color = EditorTokens.faint;
    final int count = (seconds / step).ceil();

    // Virtualized tick bounds
    final double visibleStart = -leftPad;
    final double visibleEnd = size.width - leftPad;

    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;

      if (x < visibleStart - 50 || x > visibleEnd + 50) continue;

      final String label = _formatRulerText(t, step);
      final tp = _textCache.putIfAbsent(label, () {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(color: EditorTokens.muted, fontSize: EditorTokens.minFontSize),
          ),
          textDirection: TextDirection.ltr,
        );
        painter.layout();
        return painter;
      });

      tp.paint(canvas, Offset(x - tp.width / 2, 10));

      for (int j = 1; j < 4; j++) {
        final double dotX = x + j * step * pps / 4;
        if (dotX >= visibleStart && dotX <= visibleEnd) {
          canvas.drawCircle(Offset(dotX, 10 + tp.height / 2), 1, dot);
        }
      }
    }
  }

  String _formatRulerText(double t, double step) {
    if (t >= 60) {
      final int totalSec = t.floor();
      final int m = totalSec ~/ 60;
      final int s = totalSec % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    } else if (step < 1.0) {
      final int sec = t.floor();
      final int ms = ((t - sec) * 100).round();
      return '${sec.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
    } else {
      return '${t.toInt()}s';
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter oldDelegate) {
    return oldDelegate.pps != pps ||
        oldDelegate.seconds != seconds ||
        oldDelegate.leftPad != leftPad ||
        oldDelegate.fps != fps;
  }
}
