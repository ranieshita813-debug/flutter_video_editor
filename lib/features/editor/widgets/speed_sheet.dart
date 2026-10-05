import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);

const double _minSpeed = 0.1;
const double _maxSpeed = 10.0;

/// A point on the speed curve: x = 0..1 along the clip, s = speed multiplier.
class _Pt {
  _Pt(this.x, this.s);
  double x;
  double s;
}

const Map<String, List<List<double>>> _curvePresets = <String, List<List<double>>>{
  'Custom': <List<double>>[[0, 1], [1, 1]],
  'Montage': <List<double>>[[0, 1], [.25, .3], [.5, 3], [.75, .3], [1, 1]],
  'Hero': <List<double>>[[0, 1.5], [.3, .4], [.7, .4], [1, 1.5]],
  'Bullet': <List<double>>[[0, 3], [.4, .2], [.6, .2], [1, 3]],
  'Jumper': <List<double>>[[0, .5], [.35, 4], [.65, 4], [1, .5]],
  'Flash in': <List<double>>[[0, .3], [1, 3]],
  'Flash out': <List<double>>[[0, 3], [1, .3]],
};

double _toT(double speed) => ((math.log(speed) / math.ln10) + 1) / 2;
double _fromT(double t) => math.pow(10, t * 2 - 1).toDouble();

String _fmt(double sec) {
  final int m = sec ~/ 60;
  final double s = sec - m * 60;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

class SpeedSheet extends StatefulWidget {
  const SpeedSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SpeedSheet(),
    );
  }

  @override
  State<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<SpeedSheet> {
  static const List<double> _presets = <double>[0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0];

  late double speed;
  bool curveMode = false;
  bool keepPitch = true;
  bool smooth = false;
  bool reverse = false;
  String preset = 'Custom';
  int? selected;
  int? dragging;
  late List<_Pt> pts;

  @override
  void initState() {
    super.initState();
    final clip = context.read<EditorController>().selectedClip;
    speed = (clip?.speed ?? 1.0).clamp(_minSpeed, _maxSpeed).toDouble();
    pts = <_Pt>[_Pt(0, 1), _Pt(1, 1)];
  }

  // ---- math -----------------------------------------------------------------

  double _sourceSeconds(EditorController c) {
    final clip = c.selectedClip;
    if (clip == null) return 0;
    return clip.duration.inMilliseconds / 1000.0 * (clip.speed);
  }

  double _speedAt(double x) {
    if (x <= pts.first.x) return pts.first.s;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      if (x <= b.x) {
        final double k = (x - a.x) / math.max(b.x - a.x, 1e-6);
        final double e = k * k * (3 - 2 * k);
        return math.exp(math.log(a.s) + (math.log(b.s) - math.log(a.s)) * e);
      }
    }
    return pts.last.s;
  }

  /// Mean of 1/speed along the clip = output duration / source duration.
  double get _durationFactor {
    if (!curveMode) return 1 / speed;
    const int n = 200;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      sum += 1 / _speedAt((i + 0.5) / n);
    }
    return sum / n;
  }

  double get _effectiveSpeed => curveMode ? 1 / _durationFactor : speed;

  void _apply(EditorController c, double s) {
    c.updateAudioProperties(
      c.selectedClip?.audioProperties.copyWith(speed: s) ?? const AudioProperties(),
    );
  }

  void _setSpeed(EditorController c, double v) {
    setState(() => speed = double.parse(v.toStringAsFixed(2)));
    _apply(c, speed);
  }

  void _loadPreset(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      preset = name;
      selected = null;
      pts = _curvePresets[name]!.map((p) => _Pt(p[0], p[1])).toList();
    });
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final double src = _sourceSeconds(c);
    final double out = src * _durationFactor;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _track, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('Speed',
                    style: TextStyle(
                        color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            _tabs(),
            const SizedBox(height: 18),
            if (curveMode) _curveView() else _normalView(c),
            const SizedBox(height: 18),
            _durationCard(src, out),
            const SizedBox(height: 14),
            _toggle('Maintain pitch', 'Keep voice and music tone natural',
                keepPitch, (v) => setState(() => keepPitch = v)),
            _toggle('Smooth slow motion', 'Interpolate frames below 1x', smooth,
                (v) => setState(() => smooth = v)),
            _toggle('Reverse', 'Play the clip backwards', reverse,
                (v) => setState(() => reverse = v)),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _track),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      setState(() {
                        speed = 1.0;
                        preset = 'Custom';
                        selected = null;
                        pts = <_Pt>[_Pt(0, 1), _Pt(1, 1)];
                      });
                      _apply(c, 1.0);
                    },
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      // Constant speed or the curve's equivalent average speed.
                      // Hook for curve points, pitch, interpolation and reverse:
                      //   pts / keepPitch / smooth / reverse hold the values.
                      _apply(c, double.parse(_effectiveSpeed.toStringAsFixed(3)));
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool on, VoidCallback f) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: f,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: on ? Colors.black : _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Row(children: <Widget>[
        tab('Normal', !curveMode, () => setState(() => curveMode = false)),
        tab('Curve', curveMode, () => setState(() => curveMode = true)),
      ]),
    );
  }

  // ---- Normal tab -----------------------------------------------------------

  Widget _normalView(EditorController c) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(speed.toStringAsFixed(2),
                style: const TextStyle(
                    color: _text,
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
            const Text('x', style: TextStyle(color: _muted, fontSize: 20)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: Colors.white,
            inactiveTrackColor: _track,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            value: _toT(speed).clamp(0.0, 1.0).toDouble(),
            onChanged: (t) {
              double v = _fromT(t);
              if ((v - 1).abs() < 0.04) v = 1.0; // magnet to 1x
              _setSpeed(c, v);
            },
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('0.1x', style: TextStyle(color: _muted, fontSize: 11)),
            Text('1x', style: TextStyle(color: _muted, fontSize: 11)),
            Text('10x', style: TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final p in _presets)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _setSpeed(c, p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: (p - speed).abs() < 0.01 ? Colors.white : _card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${p}x',
                      style: TextStyle(
                          color: (p - speed).abs() < 0.01 ? Colors.black : _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---- Curve tab ------------------------------------------------------------

  Widget _curveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final name in _curvePresets.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _loadPreset(name),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: preset == name ? Colors.white : _card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(name,
                          style: TextStyle(
                              color: preset == name ? Colors.black : _text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final Size size = Size(box.maxWidth, 190);
          Offset toPx(_Pt p) =>
              Offset(p.x * size.width, size.height * (1 - _toT(p.s)));
          int? nearest(Offset o) {
            int? best;
            double bd = 28;
            for (int i = 0; i < pts.length; i++) {
              final double d = (toPx(pts[i]) - o).distance;
              if (d < bd) {
                bd = d;
                best = i;
              }
            }
            return best;
          }

          return GestureDetector(
            onPanStart: (d) {
              dragging = nearest(d.localPosition);
              if (dragging != null) setState(() => selected = dragging);
            },
            onPanUpdate: (d) {
              final int? i = dragging;
              if (i == null) return;
              final Offset o = d.localPosition;
              double s = _fromT((1 - o.dy / size.height).clamp(0.0, 1.0).toDouble());
              if ((s - 1).abs() < 0.06) s = 1.0;
              setState(() {
                pts[i].s = s.clamp(_minSpeed, _maxSpeed).toDouble();
                if (i != 0 && i != pts.length - 1) {
                  pts[i].x = (o.dx / size.width)
                      .clamp(pts[i - 1].x + 0.02, pts[i + 1].x - 0.02)
                      .toDouble();
                }
                preset = 'Custom';
              });
            },
            onPanEnd: (_) => dragging = null,
            onTapUp: (d) {
              final int? i = nearest(d.localPosition);
              if (i != null) {
                setState(() => selected = i);
                return;
              }
              final double x = (d.localPosition.dx / size.width).clamp(0.02, 0.98).toDouble();
              HapticFeedback.selectionClick();
              setState(() {
                pts.add(_Pt(x, _speedAt(x)));
                pts.sort((a, b) => a.x.compareTo(b.x));
                selected = pts.indexWhere((p) => p.x == x);
                preset = 'Custom';
              });
            },
            onLongPressStart: (d) {
              final int? i = nearest(d.localPosition);
              if (i != null && i != 0 && i != pts.length - 1) {
                HapticFeedback.mediumImpact();
                setState(() {
                  pts.removeAt(i);
                  selected = null;
                  preset = 'Custom';
                });
              }
            },
            child: Container(
              height: size.height,
              decoration: BoxDecoration(
                  color: _card, borderRadius: BorderRadius.circular(14)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  size: size,
                  painter: _CurvePainter(pts: pts, selected: selected),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          selected != null && selected! < pts.length
              ? 'Point ${selected! + 1}: ${pts[selected!].s.toStringAsFixed(2)}x'
              : 'Tap to add a point, drag to shape, long-press to delete',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }

  // ---- Shared bits ----------------------------------------------------------

  Widget _durationCard(double src, double out) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: <Widget>[
          const Icon(Icons.timer_outlined, size: 18, color: _muted),
          const SizedBox(width: 10),
          const Text('Duration', style: TextStyle(color: _muted, fontSize: 13)),
          const Spacer(),
          Text('${_fmt(src)}  →  ${_fmt(out)}',
              style: const TextStyle(
                  color: _text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _toggle(String title, String sub, bool value, ValueChanged<bool> f) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(sub, style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: f,
            activeThumbColor: Colors.black,
            activeTrackColor: Colors.white,
            inactiveThumbColor: _muted,
            inactiveTrackColor: _track,
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.pts, required this.selected});
  final List<_Pt> pts;
  final int? selected;

  Offset _px(_Pt p, Size s) => Offset(p.x * s.width, s.height * (1 - _toT(p.s)));

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = _track
      ..strokeWidth = 1;
    // guide lines at 0.1x, 0.3x(approx), 1x, 3x, 10x
    for (final double v in <double>[0.1, 0.3, 1, 3, 10]) {
      final double y = size.height * (1 - _toT(v));
      final bool one = v == 1;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = one ? Colors.white38 : _track
          ..strokeWidth = one ? 1.2 : 1,
      );
      final tp = TextPainter(
        text: TextSpan(
            text: '${v}x', style: const TextStyle(color: _muted, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(6, y - tp.height - 1));
    }
    for (int i = 1; i < 4; i++) {
      final double x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final Path line = Path();
    final Path fill = Path();
    const int n = 120;
    for (int i = 0; i <= n; i++) {
      final double x = i / n;
      double s = pts.last.s;
      if (x <= pts.first.x) {
        s = pts.first.s;
      } else {
        for (int j = 0; j < pts.length - 1; j++) {
          if (x <= pts[j + 1].x) {
            final double k = (x - pts[j].x) / math.max(pts[j + 1].x - pts[j].x, 1e-6);
            // smoothstep easing between points for a flowing curve
            final double e = k * k * (3 - 2 * k);
            s = math.exp(math.log(pts[j].s) +
                (math.log(pts[j + 1].s) - math.log(pts[j].s)) * e);
            break;
          }
        }
      }
      final Offset o = Offset(x * size.width, size.height * (1 - _toT(s)));
      if (i == 0) {
        line.moveTo(o.dx, o.dy);
        fill.moveTo(o.dx, size.height);
        fill.lineTo(o.dx, o.dy);
      } else {
        line.lineTo(o.dx, o.dy);
        fill.lineTo(o.dx, o.dy);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = Colors.white.withAlpha(24));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);

    for (int i = 0; i < pts.length; i++) {
      final Offset o = _px(pts[i], size);
      final bool sel = i == selected;
      canvas.drawCircle(o, sel ? 9 : 6.5, Paint()..color = sel ? Colors.white : Colors.black);
      canvas.drawCircle(
          o,
          sel ? 9 : 6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}