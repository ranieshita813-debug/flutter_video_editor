// lib/features/editor/widgets/adjust_sheet.dart
//
// Adjust tool, CapCut x Premiere Pro hybrid.
//  - CapCut: thumb-friendly icon strip, one parameter at a time, compact
//    sheet that leaves the video visible, ✕ / title / ✓ footer.
//  - Premiere: boxed scrubbable value field, triangle-thumb slider with a
//    zero tick, colored tracks (temperature / hue), per-parameter reset,
//    group separators, press-and-hold compare.
// Edits stream to [onChanged] for live preview; ✓ commits via [onApply],
// ✕ reverts the preview.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _bg = Color(0xFF121214);
const Color _card = Color(0xFF232327);
const Color _field = Color(0xFF18181B);
const Color _line = Color(0xFF2C2C31);
const Color _track = Color(0xFF45454C);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8E8E96);
const Color _accent = Color(0xFF2DE2E6);

enum AdjustGroup { light, color, effects }

enum AdjustParam {
  brightness('Brightness', Icons.wb_sunny_outlined, AdjustGroup.light),
  contrast('Contrast', Icons.contrast_rounded, AdjustGroup.light),
  saturation('Saturation', Icons.water_drop_outlined, AdjustGroup.color),
  warmth('Warmth', Icons.thermostat_rounded, AdjustGroup.color),
  hue('Hue', Icons.palette_outlined, AdjustGroup.color),
  sharpness('Sharpen', Icons.deblur_rounded, AdjustGroup.effects),
  vignette('Vignette', Icons.vignette_rounded, AdjustGroup.effects),
  grain('Grain', Icons.grain_rounded, AdjustGroup.effects);

  const AdjustParam(this.label, this.icon, this.group);
  final String label;
  final IconData icon;
  final AdjustGroup group;

  /// Sharpen, vignette and grain only go one way.
  double get min => switch (this) {
        AdjustParam.sharpness || AdjustParam.vignette || AdjustParam.grain => 0,
        _ => -100,
      };

  /// Colored track hints, like Lumetri's temperature / tint bars.
  List<Color>? get gradient => switch (this) {
        AdjustParam.warmth => const <Color>[
            Color(0xFF3B82F6), Color(0xFF6B6B72), Color(0xFFF5A524)],
        AdjustParam.hue => const <Color>[
            Color(0xFFFF4D4D), Color(0xFFFFD84D), Color(0xFF4DFF88),
            Color(0xFF4DD2FF), Color(0xFF6B4DFF), Color(0xFFFF4DD2)],
        AdjustParam.saturation => const <Color>[
            Color(0xFF777780), Color(0xFF6B6B72), Color(0xFFE5484D)],
        _ => null,
      };
}

@immutable
class AdjustSettings {
  const AdjustSettings([this.values = const <AdjustParam, double>{}]);
  static const AdjustSettings identity = AdjustSettings();

  final Map<AdjustParam, double> values;

  double operator [](AdjustParam p) => values[p] ?? 0;
  bool get isIdentity => values.isEmpty;

  AdjustSettings set(AdjustParam p, double v) {
    final m = Map<AdjustParam, double>.of(values);
    final double c = v.clamp(p.min, 100.0).toDouble();
    c == 0 ? m.remove(p) : m[p] = c;
    return AdjustSettings(m);
  }

  /// Approximate live preview: wrap the video in `ColorFiltered`.
  /// (Sharpen, hue, vignette and grain are export-only.)
  ColorFilter? toColorFilter() {
    if (isIdentity) return null;
    final double c = 1 + this[AdjustParam.contrast] / 100;
    final double s = 1 + this[AdjustParam.saturation] / 100;
    final double off =
        128 * (1 - c) + this[AdjustParam.brightness] / 100 * 80;
    final double w = this[AdjustParam.warmth] / 100 * 40;
    return ColorFilter.matrix(<double>[
      c * (.213 + .787 * s), c * (.715 - .715 * s), c * (.072 - .072 * s), 0, off + w,
      c * (.213 - .213 * s), c * (.715 + .285 * s), c * (.072 - .072 * s), 0, off,
      c * (.213 - .213 * s), c * (.715 - .715 * s), c * (.072 + .928 * s), 0, off - w,
      0, 0, 0, 1, 0,
    ]);
  }

  /// FFmpeg -vf chain for export, or null when nothing changed.
  String? toFfmpeg() {
    if (isIdentity) return null;
    String n(double v) => v.toStringAsFixed(3);
    final List<String> f = <String>[];
    final double b = this[AdjustParam.brightness];
    final double c = this[AdjustParam.contrast];
    final double s = this[AdjustParam.saturation];
    if (b != 0 || c != 0 || s != 0) {
      f.add('eq=brightness=${n(b / 100 * 0.3)}:contrast=${n(1 + c / 100)}'
          ':saturation=${n(1 + s / 100)}');
    }
    final double w = this[AdjustParam.warmth];
    if (w != 0) f.add('colorbalance=rs=${n(w / 100 * 0.3)}:bs=${n(-w / 100 * 0.3)}');
    final double h = this[AdjustParam.hue];
    if (h != 0) f.add('hue=h=${n(h * 1.8)}');
    final double sh = this[AdjustParam.sharpness];
    if (sh != 0) f.add('unsharp=5:5:${n(sh / 100 * 2)}:5:5:0');
    final double v = this[AdjustParam.vignette];
    if (v != 0) f.add('vignette=angle=${n(math.pi / 2 - v / 100 * (math.pi / 2 - 0.35))}');
    final double g = this[AdjustParam.grain];
    if (g != 0) f.add('noise=alls=${(g / 100 * 30).round()}:allf=t');
    return f.join(',');
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{for (final e in values.entries) e.key.name: e.value};

  factory AdjustSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return identity;
    AdjustSettings s = identity;
    for (final p in AdjustParam.values) {
      final Object? v = j[p.name];
      if (v is num) s = s.set(p, v.toDouble());
    }
    return s;
  }

  @override
  bool operator ==(Object other) => other is AdjustSettings && mapEquals(other.values, values);
  @override
  int get hashCode => Object.hashAll(
      values.entries.map((e) => Object.hash(e.key, e.value)));
}

class AdjustSheet extends StatefulWidget {
  const AdjustSheet({
    super.key,
    this.initial = AdjustSettings.identity,
    this.onChanged,
    required this.onApply,
    required this.onClose,
  });

  final AdjustSettings initial;
  final ValueChanged<AdjustSettings>? onChanged;
  final ValueChanged<AdjustSettings> onApply;
  final VoidCallback onClose;

  @override
  State<AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<AdjustSheet> {
  late AdjustSettings _s = widget.initial;
  AdjustParam _p = AdjustParam.brightness;

  void _set(double v) {
    final double old = _s[_p];
    final AdjustSettings next = _s.set(_p, v);
    if (next == _s) return;
    if (old != 0 && next[_p] == 0) HapticFeedback.selectionClick();
    setState(() => _s = next);
    widget.onChanged?.call(_s);
  }

  void _resetAll() {
    HapticFeedback.selectionClick();
    setState(() => _s = AdjustSettings.identity);
    widget.onChanged?.call(_s);
  }

  void _cancel() {
    widget.onChanged?.call(widget.initial); // revert live preview
    widget.onClose();
  }

  void _apply() {
    HapticFeedback.lightImpact();
    if (_s != widget.initial) widget.onApply(_s);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final double v = _s[_p];
    return ColoredBox(
      color: _bg,
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 12),
                  _strip(),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: <Widget>[
                        Text(_p.label,
                            style: const TextStyle(
                                color: _text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (v != 0)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _set(0),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.undo_rounded, size: 16, color: _muted),
                            ),
                          ),
                        const Spacer(),
                        _ValueField(value: v, min: _p.min, onChanged: _set),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _PremiereSlider(
                      value: v,
                      min: _p.min,
                      gradient: _p.gradient,
                      onChanged: _set,
                    ),
                  ),
                  const Text('Drag the value to fine-tune · double-tap to reset',
                      style: TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  /// CapCut-style icon strip, with Premiere-style hairline separators
  /// between the Light / Color / Effects groups.
  Widget _strip() {
    final List<Widget> items = <Widget>[];
    AdjustGroup? last;
    for (final p in AdjustParam.values) {
      if (last != null && p.group != last) {
        items.add(Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.only(top: 5, left: 4, right: 4),
          color: _line,
        ));
      }
      items.add(_item(p));
      last = p.group;
    }
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: items,
      ),
    );
  }

  Widget _item(AdjustParam p) {
    final bool on = p == _p;
    final bool changed = _s[p] != 0;
    return Semantics(
      button: true,
      selected: on,
      label: '${p.label}${changed ? ', changed' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _p = p);
        },
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: on ? _accent.withAlpha(28) : _card,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: on ? _accent : Colors.transparent, width: 1.4),
                    ),
                    child: Icon(p.icon, size: 20, color: on ? _accent : _text),
                  ),
                  if (changed)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: CircleAvatar(radius: 4, backgroundColor: _accent),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(p.label,
                  maxLines: 1,
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
              onPointerDown: (_) => widget.onChanged?.call(AdjustSettings.identity),
              onPointerUp: (_) => widget.onChanged?.call(_s),
              onPointerCancel: (_) => widget.onChanged?.call(_s),
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
            const Text('Adjust',
                style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _s.isIdentity ? null : _resetAll,
              style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40), foregroundColor: _muted),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            const SizedBox(width: 48),
            IconButton(
              tooltip: 'Apply',
              icon: Icon(Icons.check_rounded,
                  color: _s != widget.initial ? _accent : _text, size: 26),
              onPressed: _apply,
            ),
          ],
        ),
      );
}

/// Boxed numeric readout. Drag left/right on it to scrub, double-tap to
/// reset (Premiere's "scrubby value" gesture).
class _ValueField extends StatelessWidget {
  const _ValueField({required this.value, required this.min, required this.onChanged});
  final double value;
  final double min;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final int r = value.round();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => onChanged(0),
      onHorizontalDragUpdate: (d) =>
          onChanged((value + d.delta.dx * 0.5).clamp(min, 100).toDouble()),
      child: Container(
        width: 64,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: r != 0 ? _accent.withAlpha(120) : _line),
        ),
        child: Text(
          '${r > 0 && min < 0 ? '+' : ''}$r',
          style: TextStyle(
            color: r != 0 ? _accent : _muted,
            fontSize: 15,
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
          onDoubleTap: () => onChanged(0),
          child: SizedBox(
            height: 44,
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
    const double y = 14;
    double px(double v) => pad + (v - min) / (100 - min) * w;
    final double z = px(0), x = px(value);

    final Rect bar = Rect.fromLTWH(pad, y - 2, w, 4);
    final RRect rbar = RRect.fromRectAndRadius(bar, const Radius.circular(2));
    if (gradient != null) {
      canvas.drawRRect(
        rbar,
        Paint()..shader = LinearGradient(colors: gradient!).createShader(bar),
      );
    } else {
      canvas.drawRRect(rbar, Paint()..color = _track);
      if (value != 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(math.min(z, x), y - 2, math.max(z, x), y + 2),
            const Radius.circular(2),
          ),
          Paint()..color = _accent,
        );
      }
    }

    // Zero tick for bipolar parameters.
    if (min < 0) {
      canvas.drawLine(Offset(z, y - 8), Offset(z, y + 8),
          Paint()..color = _muted..strokeWidth = 1.5);
    }

    // Premiere triangle thumb, pointing up at the track.
    final Path thumb = Path()
      ..moveTo(x, y + 5)
      ..lineTo(x - 8, y + 19)
      ..lineTo(x + 8, y + 19)
      ..close();
    canvas.drawPath(
      thumb,
      Paint()..color = value != 0 ? _accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) =>
      old.value != value || old.min != min || old.gradient != gradient;
}