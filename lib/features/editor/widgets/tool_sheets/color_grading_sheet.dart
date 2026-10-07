// lib/features/editor/widgets/color_grade_sheet.dart
//
// Advanced color grading, CapCut x Premiere Pro (Lumetri) hybrid.
//   Looks     one-tap presets with a strength slider
//   Basic     white balance, tone (exposure..blacks), saturation
//   Creative  vibrance, fade, sharpen, vignette, grain
//   Wheels    shadows / midtones / highlights color wheels + luma
//   Curves    master / R / G / B point curves
//
// Edits stream to [onChanged] for live preview (use grade.toColorFilter());
// ✓ commits via [onApply], ✕ reverts the preview. Hold the compare icon to
// see the original. Export with grade.toFfmpeg().

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_video_editor/core/models/color_grade.dart';

const Color _bg = Color(0xFF121214);
const Color _card = Color(0xFF232327);
const Color _field = Color(0xFF18181B);
const Color _line = Color(0xFF2C2C31);
const Color _track = Color(0xFF45454C);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8E8E96);
const Color _accent = Color(0xFF2DE2E6);

enum _Tab {
  looks('Looks', Icons.auto_awesome_outlined),
  basic('Basic', Icons.tune_rounded),
  creative('Creative', Icons.palette_outlined),
  wheels('Wheels', Icons.album_outlined),
  curves('Curves', Icons.show_chart_rounded);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

const List<GradeParam> _wb = <GradeParam>[GradeParam.temperature, GradeParam.tint];
const List<GradeParam> _tone = <GradeParam>[
  GradeParam.exposure,
  GradeParam.contrast,
  GradeParam.highlights,
  GradeParam.shadows,
  GradeParam.whites,
  GradeParam.blacks,
];
const List<GradeParam> _color = <GradeParam>[GradeParam.saturation];
const List<GradeParam> _look = <GradeParam>[GradeParam.vibrance, GradeParam.fade];
const List<GradeParam> _fx = <GradeParam>[
  GradeParam.sharpen,
  GradeParam.vignette,
  GradeParam.grain,
];

List<Color>? _gradient(GradeParam p) => switch (p) {
      GradeParam.temperature => const <Color>[
          Color(0xFF3B82F6), Color(0xFF6B6B72), Color(0xFFF5A524)],
      GradeParam.tint => const <Color>[
          Color(0xFF4ADE80), Color(0xFF6B6B72), Color(0xFFE879F9)],
      GradeParam.exposure => const <Color>[Color(0xFF111111), Color(0xFFEEEEEE)],
      GradeParam.saturation => const <Color>[
          Color(0xFF777780), Color(0xFF6B6B72), Color(0xFFE5484D)],
      GradeParam.vibrance => const <Color>[
          Color(0xFF777780), Color(0xFF6B6B72), Color(0xFFF0997B)],
      _ => null,
    };

Color _channelColor(CurveChannel c) => switch (c) {
      CurveChannel.master => const Color(0xFFEDEDED),
      CurveChannel.red => const Color(0xFFFF5A5A),
      CurveChannel.green => const Color(0xFF5AE08A),
      CurveChannel.blue => const Color(0xFF5A9CFF),
    };

class ColorGradeSheet extends StatefulWidget {
  const ColorGradeSheet({
    super.key,
    this.initial = ColorGrade.identity,
    this.onChanged,
    required this.onApply,
    required this.onClose,
  });

  final ColorGrade initial;
  final ValueChanged<ColorGrade>? onChanged;
  final ValueChanged<ColorGrade> onApply;
  final VoidCallback onClose;

  @override
  State<ColorGradeSheet> createState() => _ColorGradeSheetState();
}

class _ColorGradeSheetState extends State<ColorGradeSheet> {
  late ColorGrade _g = widget.initial;
  _Tab _tab = _Tab.basic;
  GradeLook? _activeLook;
  double _strength = 1;
  CurveChannel _ch = CurveChannel.master;

  // ---- state ----------------------------------------------------------------

  void _emit(ColorGrade g) {
    setState(() {
      _g = g;
      _activeLook = null; // manual edit detaches from the look
    });
    widget.onChanged?.call(g);
  }

  void _setParam(GradeParam p, double v) {
    final double old = _g[p];
    final ColorGrade next = _g.setParam(p, v);
    if (next == _g) return;
    if (old != 0 && next[p] == 0) HapticFeedback.selectionClick();
    _emit(next);
  }

  void _pickLook(GradeLook? look) {
    HapticFeedback.selectionClick();
    final ColorGrade g = look == null ? ColorGrade.identity : look.grade;
    setState(() {
      _activeLook = look;
      _strength = 1;
      _g = g;
    });
    widget.onChanged?.call(g);
  }

  void _setStrength(double v) {
    final GradeLook? l = _activeLook;
    if (l == null) return;
    final double s = (v / 100).clamp(0.0, 1.0).toDouble();
    final ColorGrade g = ColorGrade.scaled(l.grade, s);
    setState(() {
      _strength = s;
      _g = g;
    });
    widget.onChanged?.call(g);
  }

  void _resetAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _g = ColorGrade.identity;
      _activeLook = null;
      _strength = 1;
    });
    widget.onChanged?.call(_g);
  }

  void _cancel() {
    widget.onChanged?.call(widget.initial); // revert live preview
    widget.onClose();
  }

  void _apply() {
    HapticFeedback.lightImpact();
    if (_g != widget.initial) widget.onApply(_g);
    widget.onClose();
  }

  bool _edited(_Tab t) => switch (t) {
        _Tab.looks => _activeLook != null,
        _Tab.basic => <GradeParam>[..._wb, ..._tone, ..._color].any((p) => _g[p] != 0),
        _Tab.creative => <GradeParam>[..._look, ..._fx].any((p) => _g[p] != 0),
        _Tab.wheels => GradeRange.values.any((r) => !_g.wheel(r).isIdentity),
        _Tab.curves => _g.curves.isNotEmpty,
      };

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          _strip(),
          const Divider(height: 1, thickness: 1, color: _line),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: switch (_tab) {
                _Tab.looks => _looksTab(),
                _Tab.basic => _paramTab(<(String, List<GradeParam>)>[
                    ('White balance', _wb),
                    ('Tone', _tone),
                    ('Color', _color),
                  ]),
                _Tab.creative => _paramTab(<(String, List<GradeParam>)>[
                    ('Look', _look),
                    ('Effects', _fx),
                  ]),
                _Tab.wheels => _wheelsTab(),
                _Tab.curves => _curvesTab(),
              },
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _strip() => SizedBox(
        height: 70,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: <Widget>[for (final t in _Tab.values) _tabItem(t)],
        ),
      );

  Widget _tabItem(_Tab t) {
    final bool on = t == _tab;
    return Semantics(
      button: true,
      selected: on,
      label: '${t.label}${_edited(t) ? ', changed' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tab = t);
        },
        child: SizedBox(
          width: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: on ? _accent.withAlpha(28) : _card,
                      shape: BoxShape.circle,
                      border: Border.all(color: on ? _accent : Colors.transparent, width: 1.4),
                    ),
                    child: Icon(t.icon, size: 19, color: on ? _accent : _text),
                  ),
                  if (_edited(t))
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: CircleAvatar(radius: 4, backgroundColor: _accent),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(t.label,
                  style: TextStyle(
                      color: on ? _accent : _muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(String title) => Container(
        height: 32,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: _card,
          border: Border(top: BorderSide(color: _line), bottom: BorderSide(color: _line)),
        ),
        child: Text(title,
            style: const TextStyle(
                color: _text, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _footer() => Container(
        height: 52,
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E10),
          border: Border(top: BorderSide(color: _line)),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close_rounded, color: _text),
              onPressed: _cancel,
            ),
            // Press and hold to preview the original.
            Listener(
              onPointerDown: (_) => widget.onChanged?.call(ColorGrade.identity),
              onPointerUp: (_) => widget.onChanged?.call(_g),
              onPointerCancel: (_) => widget.onChanged?.call(_g),
              child: Semantics(
                button: true,
                label: 'Hold to compare with original',
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.compare_rounded, size: 22, color: _muted),
                ),
              ),
            ),
            const Spacer(),
            const Text('Color',
                style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _g.isIdentity ? null : _resetAll,
              style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40), foregroundColor: _muted),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            const SizedBox(width: 48),
            IconButton(
              tooltip: 'Apply',
              icon: Icon(Icons.check_rounded,
                  color: _g != widget.initial ? _accent : _text, size: 26),
              onPressed: _apply,
            ),
          ],
        ),
      );

  // ---- Looks ----------------------------------------------------------------

  Widget _looksTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _bar('Looks'),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              _lookTile('Original', null, _g.isIdentity && _activeLook == null),
              for (final l in kGradeLooks) _lookTile(l.name, l, _activeLook == l),
            ],
          ),
        ),
        _bar('Strength'),
        if (_activeLook != null)
          _Row(
            label: _activeLook!.name,
            value: _strength * 100,
            min: 0,
            resetTo: 100,
            onChanged: _setStrength,
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text('Pick a look to adjust how strong it is.',
                style: TextStyle(color: _muted, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _lookTile(String name, GradeLook? look, bool on) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: on,
        label: '$name look',
        child: GestureDetector(
          onTap: () => _pickLook(look),
          child: SizedBox(
            width: 74,
            child: Column(
              children: <Widget>[
                Container(
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? _accent : Colors.transparent, width: 1.6),
                    color: look == null ? _card : null,
                    gradient: look == null
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[look.a, look.b],
                          ),
                  ),
                  child: look == null
                      ? const Icon(Icons.block_rounded, color: _muted, size: 20)
                      : null,
                ),
                const SizedBox(height: 5),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: on ? _accent : _muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Basic / Creative -----------------------------------------------------

  Widget _paramTab(List<(String, List<GradeParam>)> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final g in groups) ...<Widget>[
          _bar(g.$1),
          for (final p in g.$2)
            _Row(
              label: p.label,
              value: _g[p],
              min: p.min,
              gradient: _gradient(p),
              onChanged: (v) => _setParam(p, v),
            ),
        ],
      ],
    );
  }

  // ---- Wheels ---------------------------------------------------------------

  Widget _wheelsTab() {
    const Map<GradeRange, String> names = <GradeRange, String>{
      GradeRange.shadows: 'Shadows',
      GradeRange.midtones: 'Midtones',
      GradeRange.highlights: 'Highlights',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _bar('Color wheels'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final r in GradeRange.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _WheelCard(
                      label: names[r]!,
                      wheel: _g.wheel(r),
                      onChanged: (w) => _emit(_g.setWheel(r, w)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Drag the dot toward a color to tint that range. Double-tap a wheel to reset it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  // ---- Curves ---------------------------------------------------------------

  Widget _curvesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _bar('Curves'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final c in CurveChannel.values) _channelChip(c),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _CurveEditor(
                key: ValueKey<CurveChannel>(_ch),
                points: _g.curve(_ch),
                color: _channelColor(_ch),
                onChanged: (p) => _emit(_g.setCurve(_ch, p)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _channelChip(CurveChannel c) {
    final bool on = c == _ch;
    final bool edited = _g.curves.containsKey(c);
    final Color col = _channelColor(c);
    return Semantics(
      button: true,
      selected: on,
      label: '${c.name} curve',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _ch = c);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? _accent.withAlpha(28) : _card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? _accent : Colors.transparent, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: col, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                c == CurveChannel.master
                    ? 'RGB'
                    : c.name[0].toUpperCase() + c.name.substring(1),
                style: TextStyle(
                    color: on ? _accent : _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              if (edited) ...<Widget>[
                const SizedBox(width: 5),
                const CircleAvatar(radius: 2.5, backgroundColor: _accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Premiere-style parameter row ---------------------------------------------

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.min,
    required this.onChanged,
    this.gradient,
    this.resetTo = 0,
  });

  final String label;
  final double value;
  final double min;
  final double resetTo;
  final List<Color>? gradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool changed = (value - resetTo).abs() > 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label,
                  style: TextStyle(
                      color: changed ? _text : _muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
              if (changed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(resetTo);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.undo_rounded, size: 14, color: _muted),
                  ),
                ),
              const Spacer(),
              _ValueField(
                  value: value, min: min, hot: changed, onChanged: onChanged, resetTo: resetTo),
            ],
          ),
          _PremiereSlider(value: value, min: min, gradient: gradient, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ValueField extends StatelessWidget {
  const _ValueField({
    required this.value,
    required this.min,
    required this.hot,
    required this.onChanged,
    required this.resetTo,
  });
  final double value;
  final double min;
  final bool hot;
  final double resetTo;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final int r = value.round();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => onChanged(resetTo),
      onHorizontalDragUpdate: (d) =>
          onChanged((value + d.delta.dx * 0.5).clamp(min, 100).toDouble()),
      child: Container(
        width: 64,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: hot ? _accent.withAlpha(120) : _line),
        ),
        child: Text(
          '${r > 0 && min < 0 ? '+' : ''}$r',
          style: TextStyle(
            color: hot ? _accent : _muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _PremiereSlider extends StatelessWidget {
  const _PremiereSlider({
    required this.value,
    required this.min,
    required this.onChanged,
    this.gradient,
  });
  final double value;
  final double min;
  final List<Color>? gradient;
  final ValueChanged<double> onChanged;

  static const double _pad = 12;

  double _fromDx(double dx, double w) {
    final double t = ((dx - _pad) / (w - _pad * 2)).clamp(0.0, 1.0).toDouble();
    double v = min + (100 - min) * t;
    if (v.abs() < 3) v = 0; // magnet at zero
    return v.roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final double w = box.maxWidth;
      return Semantics(
        slider: true,
        value: '${value.round()}',
        increasedValue: '${(value + 1).round()}',
        decreasedValue: '${(value - 1).round()}',
        onIncrease: () => onChanged((value + 1).clamp(min, 100).toDouble()),
        onDecrease: () => onChanged((value - 1).clamp(min, 100).toDouble()),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged(_fromDx(d.localPosition.dx, w)),
          onHorizontalDragUpdate: (d) => onChanged(_fromDx(d.localPosition.dx, w)),
          child: SizedBox(
            height: 40,
            width: w,
            child: CustomPaint(painter: _SliderPainter(value, min, gradient)),
          ),
        ),
      );
    });
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.value, this.min, this.gradient);
  final double value;
  final double min;
  final List<Color>? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = _PremiereSlider._pad;
    final double w = size.width - pad * 2;
    const double y = 13;
    double px(double v) => pad + (v - min) / (100 - min) * w;
    final double z = px(0), x = px(value);

    final Rect bar = Rect.fromLTWH(pad, y - 2, w, 4);
    final RRect rbar = RRect.fromRectAndRadius(bar, const Radius.circular(2));
    if (gradient != null) {
      canvas.drawRRect(
          rbar, Paint()..shader = LinearGradient(colors: gradient!).createShader(bar));
    } else {
      canvas.drawRRect(rbar, Paint()..color = _track);
      if ((x - z).abs() > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(math.min(z, x), y - 2, math.max(z, x), y + 2),
            const Radius.circular(2),
          ),
          Paint()..color = _accent,
        );
      }
    }
    if (min < 0) {
      canvas.drawLine(Offset(z, y - 8), Offset(z, y + 8),
          Paint()..color = _muted..strokeWidth = 1.5);
    }
    canvas.drawPath(
      Path()
        ..moveTo(x, y + 5)
        ..lineTo(x - 7.5, y + 18)
        ..lineTo(x + 7.5, y + 18)
        ..close(),
      Paint()..color = value != 0 ? _accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) =>
      old.value != value || old.min != min || old.gradient != gradient;
}

// ---- Color wheel ----------------------------------------------------------------

class _WheelCard extends StatelessWidget {
  const _WheelCard({required this.label, required this.wheel, required this.onChanged});
  final String label;
  final GradeWheel wheel;
  final ValueChanged<GradeWheel> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool edited = !wheel.isIdentity;
    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(builder: (context, box) {
            final Size size = box.biggest;
            void pick(Offset p) {
              final Offset c = size.center(Offset.zero);
              final double r = size.shortestSide / 2 - 3;
              final Offset d = p - c;
              final double amt = (d.distance / r).clamp(0.0, 1.0).toDouble();
              double h = math.atan2(d.dy, d.dx) * 180 / math.pi;
              if (h < 0) h += 360;
              onChanged(wheel.copyWith(hue: h, amount: amt < 0.04 ? 0 : amt));
            }

            return Semantics(
              label: '$label color wheel',
              child: GestureDetector(
                onPanStart: (d) => pick(d.localPosition),
                onPanUpdate: (d) => pick(d.localPosition),
                onTapDown: (d) => pick(d.localPosition),
                onDoubleTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(GradeWheel(luma: wheel.luma));
                },
                child: CustomPaint(size: size, painter: _WheelPainter(wheel)),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: edited ? _text : _muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ),
            Text('${wheel.luma > 0 ? '+' : ''}${wheel.luma.round()}',
                style: TextStyle(
                    color: wheel.luma != 0 ? _accent : _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          ],
        ),
        _PremiereSlider(
          value: wheel.luma,
          min: -100,
          onChanged: (v) => onChanged(wheel.copyWith(luma: v)),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.w);
  final GradeWheel w;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2 - 3;
    final Rect rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(colors: <Color>[
          for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 0.8, 0.95).toColor(),
        ]).createShader(rect),
    );
    // Neutral centre that fades into the hue ring.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFF2B2B30), Color(0x002B2B30)],
          stops: <double>[0.15, 1.0],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _line,
    );
    final Paint cross = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), cross);

    final double a = w.hue * math.pi / 180;
    final Offset puck = c + Offset(math.cos(a), math.sin(a)) * (w.amount * r);
    canvas.drawCircle(
      puck,
      7,
      Paint()
        ..color = w.amount == 0
            ? _bg
            : HSVColor.fromAHSV(1, w.hue % 360, 0.8, 0.95).toColor(),
    );
    canvas.drawCircle(
      puck,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.w != w;
}

// ---- Curve editor ---------------------------------------------------------------

class _CurveEditor extends StatefulWidget {
  const _CurveEditor({
    super.key,
    required this.points,
    required this.color,
    required this.onChanged,
  });
  final List<Offset> points;
  final Color color;
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<_CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<_CurveEditor> {
  static const int _maxPoints = 10;
  int? _sel;
  int? _drag;

  Offset _toPx(Offset p, Size s) => Offset(p.dx * s.width, (1 - p.dy) * s.height);

  int? _nearest(Offset o, Size s) {
    int? best;
    double bd = 24;
    for (int i = 0; i < widget.points.length; i++) {
      final double d = (_toPx(widget.points[i], s) - o).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void _start(Offset o, Size s) {
    int? i = _nearest(o, s);
    if (i == null) {
      final double x = (o.dx / s.width).clamp(0.03, 0.97).toDouble();
      final double y = (1 - o.dy / s.height).clamp(0.0, 1.0).toDouble();
      // Too close in x to an existing point: select that point instead.
      int? close;
      double cd = 0.04;
      for (int k = 0; k < widget.points.length; k++) {
        final double d = (widget.points[k].dx - x).abs();
        if (d < cd) {
          cd = d;
          close = k;
        }
      }
      if (close != null) {
        setState(() {
          _sel = close;
          _drag = close;
        });
        return;
      }
      if (widget.points.length >= _maxPoints) {
        HapticFeedback.heavyImpact();
        return;
      }
      HapticFeedback.selectionClick();
      final List<Offset> p = List<Offset>.of(widget.points)
        ..add(Offset(x, y))
        ..sort((a, b) => a.dx.compareTo(b.dx));
      i = p.indexWhere((q) => q.dx == x);
      widget.onChanged(p);
    }
    setState(() {
      _sel = i;
      _drag = i;
    });
  }

  void _update(Offset o, Size s) {
    final int? i = _drag;
    final List<Offset> pts = widget.points;
    if (i == null || i >= pts.length) return;
    final List<Offset> p = List<Offset>.of(pts);
    final double y = (1 - o.dy / s.height).clamp(0.0, 1.0).toDouble();
    double x = p[i].dx;
    if (i != 0 && i != p.length - 1) {
      final double lo = p[i - 1].dx + 0.02, hi = p[i + 1].dx - 0.02;
      if (lo <= hi) x = (o.dx / s.width).clamp(lo, hi).toDouble();
    }
    p[i] = Offset(x, y);
    widget.onChanged(p);
  }

  void _deleteAt(int i) {
    final List<Offset> pts = widget.points;
    if (i <= 0 || i >= pts.length - 1) return;
    HapticFeedback.mediumImpact();
    final List<Offset> p = List<Offset>.of(pts)..removeAt(i);
    setState(() => _sel = null);
    widget.onChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    final List<Offset> pts = widget.points;
    final int? sel = _sel != null && _sel! < pts.length ? _sel : null;
    final bool isDefault = pts.length == 2 &&
        (pts[0] - const Offset(0, 0)).distance < 1e-4 &&
        (pts[1] - const Offset(1, 1)).distance < 1e-4;
    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(builder: (context, box) {
            final Size size = box.biggest;
            return GestureDetector(
              onPanDown: (d) => _start(d.localPosition, size),
              onPanUpdate: (d) => _update(d.localPosition, size),
              onPanEnd: (_) => _drag = null,
              onPanCancel: () => _drag = null,
              onLongPressStart: (d) {
                final int? i = _nearest(d.localPosition, size);
                if (i != null) _deleteAt(i);
              },
              child: Semantics(
                label: 'Curve editor with ${pts.length} points',
                child: Container(
                  decoration: BoxDecoration(
                    color: _field,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _line),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      size: size,
                      painter: _CurvePainter(pts, widget.color, sel),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (sel != null) ...<Widget>[
              _box('In', '${(pts[sel].dx * 100).round()}'),
              const SizedBox(width: 8),
              _box('Out', '${(pts[sel].dy * 100).round()}', hot: true),
              const SizedBox(width: 8),
            ] else
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Text('Tap to add a point',
                    style: TextStyle(color: _muted, fontSize: 12)),
              ),
            _pill(Icons.restart_alt_rounded, 'Reset', !isDefault, () {
              HapticFeedback.selectionClick();
              setState(() => _sel = null);
              widget.onChanged(ColorGrade.defaultCurve);
            }),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Long-press a point to delete it',
              style: TextStyle(color: _muted, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _box(String label, String value, {bool hot = false}) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: hot ? _accent.withAlpha(120) : _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                    color: hot ? _accent : _text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          ],
        ),
      );

  Widget _pill(IconData icon, String label, bool enabled, VoidCallback f) => Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: GestureDetector(
          onTap: enabled ? f : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration:
                  BoxDecoration(color: _card, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(icon, size: 16, color: _text),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(
                        color: _text, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.pts, this.color, this.selected);
  final List<Offset> pts;
  final Color color;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = _track.withAlpha(90)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final double f = i / 4;
      canvas.drawLine(Offset(f * size.width, 0), Offset(f * size.width, size.height), grid);
      canvas.drawLine(Offset(0, f * size.height), Offset(size.width, f * size.height), grid);
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );

    final Path line = Path();
    const int n = 96;
    for (int i = 0; i <= n; i++) {
      final double x = i / n;
      final double y = ColorGrade.evalCurve(pts, x);
      final Offset o = Offset(x * size.width, (1 - y) * size.height);
      i == 0 ? line.moveTo(o.dx, o.dy) : line.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    for (int i = 0; i < pts.length; i++) {
      final Offset o = Offset(pts[i].dx * size.width, (1 - pts[i].dy) * size.height);
      final bool sel = i == selected;
      canvas.drawCircle(o, sel ? 7.5 : 6, Paint()..color = sel ? color : _bg);
      canvas.drawCircle(
        o,
        sel ? 7.5 : 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.pts != pts || old.color != color || old.selected != selected;
}