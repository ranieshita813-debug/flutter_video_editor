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

/// One adjustment slider. [real] = the five values the controller already stores.
class _Adj {
  const _Adj(this.key, this.label, this.min, this.max, this.def, {this.real = false});
  final String key;
  final String label;
  final double min;
  final double max;
  final double def;
  final bool real;
}

const List<(String, List<_Adj>)> _groups = <(String, List<_Adj>)>[
  ('Light', <_Adj>[
    _Adj('brightness', 'Brightness', -1, 1, 0, real: true),
    _Adj('contrast', 'Contrast', 0, 2, 1, real: true),
    _Adj('exposure', 'Exposure', -1, 1, 0),
    _Adj('highlights', 'Highlights', -1, 1, 0),
    _Adj('shadows', 'Shadows', -1, 1, 0),
  ]),
  ('Color', <_Adj>[
    _Adj('saturation', 'Saturation', 0, 2, 1, real: true),
    _Adj('temperature', 'Temperature', -1, 1, 0, real: true),
    _Adj('tint', 'Tint', -1, 1, 0),
  ]),
  ('Effects', <_Adj>[
    _Adj('vignette', 'Vignette', 0, 1, 0, real: true),
    _Adj('sharpen', 'Sharpen', 0, 1, 0),
    _Adj('grain', 'Grain', 0, 1, 0),
    _Adj('fade', 'Fade', 0, 1, 0),
  ]),
];

class ColorGradingSheet extends StatefulWidget {
  const ColorGradingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ColorGradingSheet(),
    );
  }

  @override
  State<ColorGradingSheet> createState() => _ColorGradingSheetState();
}

class _ColorGradingSheetState extends State<ColorGradingSheet> {
  static const List<String> _tabs = <String>['Presets', 'Adjust', 'Wheels', 'Curves'];

  int tab = 1;
  late VideoEffect currentEffect;
  late final Map<String, double> v;
  double intensity = 1.0;

  // Local-only pro controls (see Apply hook note in the reply).
  final List<Offset> wheels = <Offset>[Offset.zero, Offset.zero, Offset.zero];
  List<Offset> curve = <Offset>[const Offset(0, 0), const Offset(1, 1)];
  int? dragPt;

  @override
  void initState() {
    super.initState();
    final c = context.read<EditorController>();
    final clip = c.selectedClip;
    final s = clip?.colorGrading ?? const ColorGradingSettings();
    currentEffect = clip?.effect ?? VideoEffect.none;
    v = <String, double>{
      for (final g in _groups) for (final a in g.$2) a.key: a.def,
      'brightness': s.brightness,
      'contrast': s.contrast,
      'saturation': s.saturation,
      'temperature': s.temperature,
      'vignette': s.vignette,
    };
  }

  ColorGradingSettings _settings() => ColorGradingSettings(
        brightness: v['brightness']!,
        contrast: v['contrast']!,
        saturation: v['saturation']!,
        temperature: v['temperature']!,
        vignette: v['vignette']!,
      );

  void _update(EditorController c) => c.updateColorGrading(_settings());

  void _resetAll(EditorController c) {
    setState(() {
      for (final g in _groups) {
        for (final a in g.$2) {
          v[a.key] = a.def;
        }
      }
      for (int i = 0; i < 3; i++) {
        wheels[i] = Offset.zero;
      }
      curve = <Offset>[const Offset(0, 0), const Offset(1, 1)];
      intensity = 1.0;
      currentEffect = VideoEffect.none;
    });
    c.applyEffect(VideoEffect.none);
    _update(c);
  }

  bool get _edited =>
      _groups.any((g) => g.$2.any((a) => (v[a.key]! - a.def).abs() > 0.001)) ||
      currentEffect != VideoEffect.none;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 14 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration:
                    BoxDecoration(color: _track, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Text('Adjust',
                    style: TextStyle(
                        color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Hold to compare with the original
                Listener(
                  onPointerDown: (_) {
                    HapticFeedback.selectionClick();
                    c.updateColorGrading(const ColorGradingSettings());
                  },
                  onPointerUp: (_) => _update(c),
                  onPointerCancel: (_) => _update(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: _card, borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: <Widget>[
                      Icon(Icons.compare_rounded, size: 16, color: _text),
                      SizedBox(width: 6),
                      Text('Hold to compare',
                          style: TextStyle(color: _text, fontSize: 12)),
                    ]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            _tabBar(),
            const SizedBox(height: 14),
            SizedBox(
              height: 330,
              child: switch (tab) {
                0 => _presets(c),
                1 => _adjust(c),
                2 => _wheels(),
                _ => _curves(),
              },
            ),
            const SizedBox(height: 12),
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
                    onPressed: _edited || wheels.any((w) => w != Offset.zero) || curve.length > 2
                        ? () => _resetAll(c)
                        : null,
                    child: const Text('Reset all'),
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done',
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

  Widget _tabBar() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < _tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab == i ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(_tabs[i],
                        style: TextStyle(
                            color: tab == i ? Colors.black : _text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      );

  // ---- Presets --------------------------------------------------------------

  Widget _presets(EditorController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: <Widget>[
              for (final fx in VideoEffect.values)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => currentEffect = fx);
                    c.applyEffect(fx);
                  },
                  child: Container(
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
                    decoration: BoxDecoration(
                      color: currentEffect == fx ? Colors.white : _card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      fx.name[0].toUpperCase() + fx.name.substring(1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: currentEffect == fx ? Colors.black : _text,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _slider('Intensity', intensity, 0, 1, 1, (x) => setState(() => intensity = x),
            unipolar: true),
      ],
    );
  }

  // ---- Adjust ---------------------------------------------------------------

  Widget _adjust(EditorController c) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final g in _groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(g.$1,
                style: const TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          for (final a in g.$2)
            _slider(a.label, v[a.key]!, a.min, a.max, a.def, (x) {
              setState(() => v[a.key] = x);
              if (a.real) _update(c);
            }, unipolar: a.def == a.min),
        ],
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, double def,
      ValueChanged<double> onChanged,
      {required bool unipolar}) {
    final double shown =
        unipolar ? (value - min) / (max - min) * 100 : (value - def) / (max - min) * 200;
    return Column(
      children: <Widget>[
        GestureDetector(
          onDoubleTap: () => onChanged(def),
          child: Row(
            children: <Widget>[
              Text(label, style: const TextStyle(color: _text, fontSize: 13)),
              const Spacer(),
              Text(
                '${shown >= 0 && !unipolar ? '+' : ''}${shown.round()}',
                style: TextStyle(
                    color: (value - def).abs() < 0.001 ? _muted : _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: Colors.white,
            inactiveTrackColor: _track,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: (x) {
              // magnet to default
              onChanged((x - def).abs() < (max - min) * 0.02 ? def : x);
            },
          ),
        ),
      ],
    );
  }

  // ---- Wheels ---------------------------------------------------------------

  Widget _wheels() {
    const List<String> names = <String>['Shadows', 'Midtones', 'Highlights'];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              Column(
                children: <Widget>[
                  LayoutBuilder(builder: (context, _) {
                    const double d = 96;
                    return GestureDetector(
                      onDoubleTap: () => setState(() => wheels[i] = Offset.zero),
                      onPanUpdate: (e) {
                        Offset o = (e.localPosition - const Offset(d / 2, d / 2)) / (d / 2);
                        if (o.distance > 1) o = o / o.distance;
                        setState(() => wheels[i] = o);
                      },
                      onPanDown: (e) {
                        Offset o = (e.localPosition - const Offset(d / 2, d / 2)) / (d / 2);
                        if (o.distance > 1) o = o / o.distance;
                        setState(() => wheels[i] = o);
                      },
                      child: SizedBox(
                        width: d,
                        height: d,
                        child: CustomPaint(painter: _WheelPainter(wheels[i])),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(names[i],
                      style: const TextStyle(
                          color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('${(wheels[i].distance * 100).round()}',
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Drag to shift color. Double-tap a wheel to reset.',
            style: TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }

  // ---- Curves ---------------------------------------------------------------

  Widget _curves() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (context, box) {
                final double w = box.maxWidth;
                Offset px(Offset p) => Offset(p.dx * w, (1 - p.dy) * w);
                int? near(Offset o) {
                  int? b;
                  double bd = 26;
                  for (int i = 0; i < curve.length; i++) {
                    final double d = (px(curve[i]) - o).distance;
                    if (d < bd) {
                      bd = d;
                      b = i;
                    }
                  }
                  return b;
                }

                return GestureDetector(
                  onPanStart: (e) => dragPt = near(e.localPosition),
                  onPanUpdate: (e) {
                    final int? i = dragPt;
                    if (i == null) return;
                    final double x = (e.localPosition.dx / w).clamp(0.0, 1.0).toDouble();
                    final double y = (1 - e.localPosition.dy / w).clamp(0.0, 1.0).toDouble();
                    setState(() {
                      final bool end = i == 0 || i == curve.length - 1;
                      final double lo = i == 0 ? 0 : curve[i - 1].dx + 0.03;
                      final double hi = i == curve.length - 1 ? 1 : curve[i + 1].dx - 0.03;
                      curve[i] = Offset(end ? curve[i].dx : x.clamp(lo, hi).toDouble(), y);
                    });
                  },
                  onPanEnd: (_) => dragPt = null,
                  onTapUp: (e) {
                    if (near(e.localPosition) != null) return;
                    HapticFeedback.selectionClick();
                    setState(() {
                      curve.add(Offset((e.localPosition.dx / w).clamp(0.05, 0.95).toDouble(),
                          (1 - e.localPosition.dy / w).clamp(0.0, 1.0).toDouble()));
                      curve.sort((a, b) => a.dx.compareTo(b.dx));
                    });
                  },
                  onLongPressStart: (e) {
                    final int? i = near(e.localPosition);
                    if (i != null && i != 0 && i != curve.length - 1) {
                      HapticFeedback.mediumImpact();
                      setState(() => curve.removeAt(i));
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                        color: _card, borderRadius: BorderRadius.circular(14)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CustomPaint(painter: _CurvePainter(curve)),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Tap to add a point, long-press to delete',
            style: TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.o);
  final Offset o;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = _card);
    for (final double k in <double>[1, 0.66, 0.33]) {
      canvas.drawCircle(
          c,
          r * k - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _track);
    }
    final Paint cross = Paint()
      ..color = _track
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), cross);
    final Offset p = c + o * (r - 8);
    canvas.drawLine(c, p, Paint()..color = Colors.white38..strokeWidth = 1.5);
    canvas.drawCircle(p, 8, Paint()..color = Colors.white);
    canvas.drawCircle(p, 3, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.o != o;
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.pts);
  final List<Offset> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    Offset px(Offset p) => Offset(p.dx * w, (1 - p.dy) * w);

    final Paint grid = Paint()
      ..color = _track
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(w * i / 4, 0), Offset(w * i / 4, w), grid);
      canvas.drawLine(Offset(0, w * i / 4), Offset(w, w * i / 4), grid);
    }
    canvas.drawLine(Offset(0, w), Offset(w, 0),
        Paint()..color = Colors.white24..strokeWidth = 1);

    final Path path = Path()..moveTo(px(pts.first).dx, px(pts.first).dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final Offset a = px(pts[i]), b = px(pts[i + 1]);
      final double mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
    for (final Offset p in pts) {
      final Offset o = px(p);
      canvas.drawCircle(o, 6.5, Paint()..color = Colors.black);
      canvas.drawCircle(
          o,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
    final tp = TextPainter(
      text: const TextSpan(text: 'Master', style: TextStyle(color: _muted, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(8, 6));
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}