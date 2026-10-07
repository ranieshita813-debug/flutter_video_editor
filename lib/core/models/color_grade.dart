// lib/core/models/color_grade.dart
//
// Lumetri / DaVinci-style grade model.
//  - Basic:    temperature, tint, exposure, contrast, highlights, shadows,
//              whites, blacks, saturation
//  - Creative: vibrance, fade, sharpen, vignette, grain
//  - Wheels:   shadows / midtones / highlights (hue, amount, luma)
//  - Curves:   master + red + green + blue (monotone cubic through points)
//
// [toColorFilter] is an approximate live preview (matrix only), so highlights,
// shadows, curves and the exact wheel behaviour are export-accurate but only
// roughly previewed. [toFfmpeg] builds the -vf chain used for export.

import 'dart:math' as math;
import 'dart:ui' show Color, ColorFilter, Offset;

import 'package:flutter/foundation.dart';

enum GradeParam {
  temperature('Temperature'),
  tint('Tint'),
  exposure('Exposure'),
  contrast('Contrast'),
  highlights('Highlights'),
  shadows('Shadows'),
  whites('Whites'),
  blacks('Blacks'),
  saturation('Saturation'),
  vibrance('Vibrance'),
  fade('Fade'),
  sharpen('Sharpen'),
  vignette('Vignette'),
  grain('Grain');

  const GradeParam(this.label);
  final String label;

  /// Fade, sharpen, vignette and grain only go one way.
  double get min => switch (this) {
        GradeParam.fade ||
        GradeParam.sharpen ||
        GradeParam.vignette ||
        GradeParam.grain =>
          0,
        _ => -100,
      };
}

enum GradeRange { shadows, midtones, highlights }

enum CurveChannel { master, red, green, blue }

@immutable
class GradeWheel {
  const GradeWheel({this.hue = 0, this.amount = 0, this.luma = 0});

  /// Degrees, 0 = red, clockwise like a color wheel.
  final double hue;

  /// 0..1 distance from the wheel centre.
  final double amount;

  /// -100..100 brightness of this tonal range.
  final double luma;

  bool get isIdentity => amount == 0 && luma == 0;

  GradeWheel copyWith({double? hue, double? amount, double? luma}) => GradeWheel(
        hue: hue ?? this.hue,
        amount: amount ?? this.amount,
        luma: luma ?? this.luma,
      );

  /// Zero-mean RGB offset for this wheel position (about -0.67..0.67).
  (double, double, double) get rgb {
    if (amount == 0) return (0.0, 0.0, 0.0);
    final double h = (hue % 360) / 60;
    final double x = 1 - ((h % 2) - 1).abs();
    double r = 0, g = 0, b = 0;
    switch (h.floor()) {
      case 0:
        r = 1;
        g = x;
      case 1:
        r = x;
        g = 1;
      case 2:
        g = 1;
        b = x;
      case 3:
        g = x;
        b = 1;
      case 4:
        r = x;
        b = 1;
      default:
        r = 1;
        b = x;
    }
    final double m = (r + g + b) / 3;
    return ((r - m) * amount, (g - m) * amount, (b - m) * amount);
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'h': hue, 'a': amount, 'l': luma};

  factory GradeWheel.fromJson(Map<String, dynamic> j) => GradeWheel(
        hue: (j['h'] as num?)?.toDouble() ?? 0,
        amount: (j['a'] as num?)?.toDouble() ?? 0,
        luma: (j['l'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is GradeWheel &&
      other.hue == hue &&
      other.amount == amount &&
      other.luma == luma;

  @override
  int get hashCode => Object.hash(hue, amount, luma);
}

@immutable
class ColorGrade {
  const ColorGrade({
    this.values = const <GradeParam, double>{},
    this.wheels = const <GradeRange, GradeWheel>{},
    this.curves = const <CurveChannel, List<Offset>>{},
  });

  static const ColorGrade identity = ColorGrade();
  static const List<Offset> defaultCurve = <Offset>[Offset(0, 0), Offset(1, 1)];

  final Map<GradeParam, double> values;
  final Map<GradeRange, GradeWheel> wheels;
  final Map<CurveChannel, List<Offset>> curves;

  double operator [](GradeParam p) => values[p] ?? 0;
  GradeWheel wheel(GradeRange r) => wheels[r] ?? const GradeWheel();
  List<Offset> curve(CurveChannel c) => curves[c] ?? defaultCurve;
  bool get isIdentity => values.isEmpty && wheels.isEmpty && curves.isEmpty;

  ColorGrade setParam(GradeParam p, double v) {
    final m = Map<GradeParam, double>.of(values);
    final double c = v.clamp(p.min, 100.0).toDouble();
    c == 0 ? m.remove(p) : m[p] = c;
    return ColorGrade(values: m, wheels: wheels, curves: curves);
  }

  ColorGrade setWheel(GradeRange r, GradeWheel w) {
    final m = Map<GradeRange, GradeWheel>.of(wheels);
    w.isIdentity ? m.remove(r) : m[r] = w;
    return ColorGrade(values: values, wheels: m, curves: curves);
  }

  ColorGrade setCurve(CurveChannel c, List<Offset> pts) {
    final m = Map<CurveChannel, List<Offset>>.of(curves);
    _isDefaultCurve(pts) ? m.remove(c) : m[c] = List<Offset>.unmodifiable(pts);
    return ColorGrade(values: values, wheels: wheels, curves: m);
  }

  static bool _isDefaultCurve(List<Offset> p) =>
      p.length == 2 &&
      (p[0] - const Offset(0, 0)).distance < 1e-4 &&
      (p[1] - const Offset(1, 1)).distance < 1e-4;

  /// Scale every adjustment toward neutral (used by look strength).
  static ColorGrade scaled(ColorGrade g, double t) {
    if (t >= 1) return g;
    if (t <= 0) return identity;
    return ColorGrade(
      values: <GradeParam, double>{
        for (final e in g.values.entries) e.key: e.value * t,
      },
      wheels: <GradeRange, GradeWheel>{
        for (final e in g.wheels.entries)
          e.key: e.value.copyWith(amount: e.value.amount * t, luma: e.value.luma * t),
      },
      curves: <CurveChannel, List<Offset>>{
        for (final e in g.curves.entries)
          e.key: <Offset>[
            for (final p in e.value) Offset(p.dx, p.dx + (p.dy - p.dx) * t),
          ],
      },
    );
  }

  // ---- curves ---------------------------------------------------------------

  /// Monotone cubic (Fritsch-Carlson) through [p], sorted by x. Returns 0..1.
  static double evalCurve(List<Offset> p, double x) {
    final int n = p.length;
    if (n == 0) return x;
    if (x <= p.first.dx) return p.first.dy;
    if (x >= p.last.dx) return p.last.dy;
    final List<double> d = List<double>.generate(
        n - 1, (i) => (p[i + 1].dy - p[i].dy) / (p[i + 1].dx - p[i].dx));
    final List<double> m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (int i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (int i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final double a = m[i] / d[i], b = m[i + 1] / d[i];
        final double s = a * a + b * b;
        if (s > 9) {
          final double t = 3 / math.sqrt(s);
          m[i] = t * a * d[i];
          m[i + 1] = t * b * d[i];
        }
      }
    }
    int k = 0;
    while (k < n - 2 && x > p[k + 1].dx) {
      k++;
    }
    final double h = p[k + 1].dx - p[k].dx;
    final double t = (x - p[k].dx) / h;
    final double t2 = t * t, t3 = t2 * t;
    final double y = (2 * t3 - 3 * t2 + 1) * p[k].dy +
        (t3 - 2 * t2 + t) * h * m[k] +
        (-2 * t3 + 3 * t2) * p[k + 1].dy +
        (t3 - t2) * h * m[k + 1];
    return y.clamp(0.0, 1.0).toDouble();
  }

  static double _bell(double x, double c, double w) =>
      math.exp(-2 * math.pow((x - c) / w, 2));

  bool get _toneActive =>
      this[GradeParam.highlights] != 0 ||
      this[GradeParam.shadows] != 0 ||
      this[GradeParam.whites] != 0 ||
      this[GradeParam.blacks] != 0 ||
      this[GradeParam.fade] != 0 ||
      GradeRange.values.any((r) => wheel(r).luma != 0);

  /// Tonal sliders + wheel luma + fade as one input->output curve.
  double toneAt(double x) {
    double y = x;
    y += this[GradeParam.blacks] / 100 * 0.12 * _bell(x, 0.0, 0.2);
    y += this[GradeParam.shadows] / 100 * 0.15 * _bell(x, 0.25, 0.22);
    y += wheel(GradeRange.shadows).luma / 100 * 0.15 * _bell(x, 0.2, 0.25);
    y += wheel(GradeRange.midtones).luma / 100 * 0.15 * _bell(x, 0.5, 0.3);
    y += this[GradeParam.highlights] / 100 * 0.15 * _bell(x, 0.75, 0.22);
    y += wheel(GradeRange.highlights).luma / 100 * 0.15 * _bell(x, 0.8, 0.25);
    y += this[GradeParam.whites] / 100 * 0.12 * _bell(x, 1.0, 0.2);
    y += this[GradeParam.fade] / 100 * 0.2 * (1 - x);
    return y.clamp(0.0, 1.0).toDouble();
  }

  double masterAt(double x) => evalCurve(curve(CurveChannel.master), toneAt(x));

  // ---- export ---------------------------------------------------------------

  /// colorbalance amounts: shadows rgb, midtones rgb, highlights rgb.
  List<double> _balance() {
    final double t = this[GradeParam.temperature] / 100 * 0.25;
    final double g = -this[GradeParam.tint] / 100 * 0.2;
    const List<double> weights = <double>[0.6, 1.0, 0.8];
    final List<double> out = <double>[];
    for (int i = 0; i < 3; i++) {
      final w = wheel(GradeRange.values[i]).rgb;
      out.add((w.$1 * 0.5 + t * weights[i]).clamp(-1.0, 1.0).toDouble());
      out.add((w.$2 * 0.5 + g * weights[i]).clamp(-1.0, 1.0).toDouble());
      out.add((w.$3 * 0.5 - t * weights[i]).clamp(-1.0, 1.0).toDouble());
    }
    return out;
  }

  /// FFmpeg -vf chain for export, or null when nothing changed.
  String? toFfmpeg() {
    if (isIdentity) return null;
    String n(double v) => v.toStringAsFixed(3);
    final List<String> f = <String>[];

    final double ex = this[GradeParam.exposure];
    if (ex != 0) f.add('exposure=exposure=${n(ex / 100 * 2)}');

    final double c = this[GradeParam.contrast];
    final double s = this[GradeParam.saturation];
    if (c != 0 || s != 0) {
      f.add('eq=contrast=${n(1 + c / 100)}:saturation=${n(1 + s / 100)}');
    }

    final List<double> b = _balance();
    if (b.any((v) => v.abs() > 1e-4)) {
      f.add('colorbalance=rs=${n(b[0])}:gs=${n(b[1])}:bs=${n(b[2])}'
          ':rm=${n(b[3])}:gm=${n(b[4])}:bm=${n(b[5])}'
          ':rh=${n(b[6])}:gh=${n(b[7])}:bh=${n(b[8])}');
    }

    final double vib = this[GradeParam.vibrance];
    if (vib != 0) f.add('vibrance=intensity=${n(vib / 100 * 2)}');

    String samples(double Function(double) fn) => List<String>.generate(17, (i) {
          final double x = i / 16;
          return '${n(x)}/${n(fn(x).clamp(0.0, 1.0).toDouble())}';
        }).join(' ');
    final List<String> cv = <String>[];
    if (_toneActive || curves.containsKey(CurveChannel.master)) {
      cv.add("master='${samples(masterAt)}'");
    }
    for (final ch in const <CurveChannel>[
      CurveChannel.red,
      CurveChannel.green,
      CurveChannel.blue,
    ]) {
      if (curves.containsKey(ch)) {
        cv.add("${ch.name}='${samples((x) => evalCurve(curve(ch), x))}'");
      }
    }
    if (cv.isNotEmpty) f.add('curves=${cv.join(':')}');

    final double sh = this[GradeParam.sharpen];
    if (sh != 0) f.add('unsharp=5:5:${n(sh / 100 * 2)}:5:5:0');
    final double v = this[GradeParam.vignette];
    if (v != 0) {
      f.add('vignette=angle=${n(math.pi / 2 - v / 100 * (math.pi / 2 - 0.35))}');
    }
    final double g = this[GradeParam.grain];
    if (g != 0) f.add('noise=alls=${(g / 100 * 30).round()}:allf=t');
    return f.isEmpty ? null : f.join(',');
  }

  // ---- live preview ---------------------------------------------------------

  /// Approximate live preview as one 5x4 color matrix.
  ColorFilter? toColorFilter() {
    if (isIdentity) return null;
    final double ex = math.pow(2, this[GradeParam.exposure] / 100 * 1.2).toDouble();
    final double t = this[GradeParam.temperature] / 100;
    final double ti = this[GradeParam.tint] / 100;
    double gr = ex * (1 + t * 0.15), gg = ex * (1 - ti * 0.1), gb = ex * (1 - t * 0.15);
    double ofr = 0, ofg = 0, ofb = 0;

    final double wh = 1 + this[GradeParam.whites] / 100 * 0.1;
    final double hi = 1 + this[GradeParam.highlights] / 100 * 0.08;
    gr *= wh * hi;
    gg *= wh * hi;
    gb *= wh * hi;

    final double lift = this[GradeParam.blacks] / 100 * 12 + this[GradeParam.shadows] / 100 * 10;
    ofr += lift;
    ofg += lift;
    ofb += lift;

    final double fd = this[GradeParam.fade] / 100;
    gr *= 1 - fd * 0.15;
    gg *= 1 - fd * 0.15;
    gb *= 1 - fd * 0.15;
    ofr += fd * 38;
    ofg += fd * 38;
    ofb += fd * 38;

    final sw = wheel(GradeRange.shadows), mw = wheel(GradeRange.midtones), hw = wheel(GradeRange.highlights);
    final sr = sw.rgb, mr = mw.rgb, hr = hw.rgb;
    ofr += sr.$1 * 90 + sw.luma / 100 * 20;
    ofg += sr.$2 * 90 + sw.luma / 100 * 20;
    ofb += sr.$3 * 90 + sw.luma / 100 * 20;
    gr *= (1 + mr.$1 * 0.6 + mw.luma / 100 * 0.12) * (1 + hr.$1 * 0.6 + hw.luma / 100 * 0.1);
    gg *= (1 + mr.$2 * 0.6 + mw.luma / 100 * 0.12) * (1 + hr.$2 * 0.6 + hw.luma / 100 * 0.1);
    gb *= (1 + mr.$3 * 0.6 + mw.luma / 100 * 0.12) * (1 + hr.$3 * 0.6 + hw.luma / 100 * 0.1);

    final double c = 1 + this[GradeParam.contrast] / 100;
    final double s = (1 + this[GradeParam.saturation] / 100) *
        (1 + this[GradeParam.vibrance] / 100 * 0.4);

    final List<double> cg = <double>[c * gr, c * gg, c * gb];
    final List<double> kk = <double>[
      c * ofr + 128 * (1 - c),
      c * ofg + 128 * (1 - c),
      c * ofb + 128 * (1 - c),
    ];
    final List<List<double>> sat = <List<double>>[
      <double>[.213 + .787 * s, .715 - .715 * s, .072 - .072 * s],
      <double>[.213 - .213 * s, .715 + .285 * s, .072 - .072 * s],
      <double>[.213 - .213 * s, .715 - .715 * s, .072 + .928 * s],
    ];
    final List<double> m = <double>[];
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        m.add(sat[i][j] * cg[j]);
      }
      m
        ..add(0)
        ..add(sat[i][0] * kk[0] + sat[i][1] * kk[1] + sat[i][2] * kk[2]);
    }
    m.addAll(<double>[0, 0, 0, 1, 0]);
    return ColorFilter.matrix(m);
  }

  // ---- legacy bridge --------------------------------------------------------

  /// From the old brightness (-0.5..0.5), contrast (0.5..2), saturation (0..2).
  factory ColorGrade.fromLegacy({
    double brightness = 0,
    double contrast = 1,
    double saturation = 1,
  }) =>
      identity
          .setParam(GradeParam.exposure, (brightness * 200).clamp(-100.0, 100.0).toDouble())
          .setParam(GradeParam.contrast, ((contrast - 1) * 100).clamp(-100.0, 100.0).toDouble())
          .setParam(GradeParam.saturation, ((saturation - 1) * 100).clamp(-100.0, 100.0).toDouble());

  /// Closest old-model values (loses wheels, curves, and the rest).
  ({double brightness, double contrast, double saturation}) toLegacy() => (
        brightness: (this[GradeParam.exposure] / 200).clamp(-0.5, 0.5).toDouble(),
        contrast: (1 + this[GradeParam.contrast] / 100).clamp(0.5, 2.0).toDouble(),
        saturation: (1 + this[GradeParam.saturation] / 100).clamp(0.0, 2.0).toDouble(),
      );

  // ---- json / equality ------------------------------------------------------

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final e in values.entries) e.key.name: e.value,
        if (wheels.isNotEmpty)
          'wheels': <String, dynamic>{
            for (final e in wheels.entries) e.key.name: e.value.toJson(),
          },
        if (curves.isNotEmpty)
          'curves': <String, dynamic>{
            for (final e in curves.entries)
              e.key.name: <List<double>>[
                for (final p in e.value) <double>[p.dx, p.dy],
              ],
          },
      };

  factory ColorGrade.fromJson(Map<String, dynamic>? j) {
    if (j == null) return identity;
    ColorGrade g = identity;
    for (final p in GradeParam.values) {
      final Object? v = j[p.name];
      if (v is num) g = g.setParam(p, v.toDouble());
    }
    final Object? w = j['wheels'];
    if (w is Map) {
      for (final r in GradeRange.values) {
        final Object? e = w[r.name];
        if (e is Map) g = g.setWheel(r, GradeWheel.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final Object? c = j['curves'];
    if (c is Map) {
      for (final ch in CurveChannel.values) {
        final Object? e = c[ch.name];
        if (e is List && e.length >= 2) {
          g = g.setCurve(ch, <Offset>[
            for (final p in e)
              if (p is List && p.length == 2)
                Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ]);
        }
      }
    }
    return g;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ColorGrade) return false;
    if (!mapEquals(other.values, values) || !mapEquals(other.wheels, wheels)) return false;
    if (other.curves.length != curves.length) return false;
    for (final e in curves.entries) {
      final o = other.curves[e.key];
      if (o == null || !listEquals(o, e.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        ...values.entries.map((e) => Object.hash(e.key, e.value)),
        ...wheels.entries.map((e) => Object.hash(e.key, e.value)),
        ...curves.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
      ]);
}

/// A named preset ("look") shown as a tile in the Looks tab.
@immutable
class GradeLook {
  const GradeLook(this.name, this.grade, this.a, this.b);
  final String name;
  final ColorGrade grade;

  /// Two swatch colors for the tile.
  final Color a;
  final Color b;
}

const List<GradeLook> kGradeLooks = <GradeLook>[
  GradeLook(
    'Cinematic',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.contrast: 18,
        GradeParam.saturation: -8,
        GradeParam.fade: 8,
        GradeParam.vignette: 25,
      },
      wheels: <GradeRange, GradeWheel>{
        GradeRange.shadows: GradeWheel(hue: 190, amount: 0.35),
        GradeRange.highlights: GradeWheel(hue: 30, amount: 0.3),
      },
    ),
    Color(0xFF1F4E5F),
    Color(0xFFE0A070),
  ),
  GradeLook(
    'Teal and orange',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.contrast: 12,
        GradeParam.saturation: 10,
      },
      wheels: <GradeRange, GradeWheel>{
        GradeRange.shadows: GradeWheel(hue: 185, amount: 0.5),
        GradeRange.highlights: GradeWheel(hue: 28, amount: 0.45),
      },
    ),
    Color(0xFF0E7C86),
    Color(0xFFF08A3C),
  ),
  GradeLook(
    'Golden hour',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.temperature: 45,
        GradeParam.exposure: 8,
        GradeParam.saturation: 10,
        GradeParam.vignette: 15,
      },
      wheels: <GradeRange, GradeWheel>{
        GradeRange.highlights: GradeWheel(hue: 38, amount: 0.35),
      },
    ),
    Color(0xFFE8A33D),
    Color(0xFFF7D88A),
  ),
  GradeLook(
    'Vintage',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.temperature: 25,
        GradeParam.fade: 35,
        GradeParam.saturation: -20,
        GradeParam.contrast: -8,
        GradeParam.grain: 20,
      },
    ),
    Color(0xFF8C6A4A),
    Color(0xFFD9C2A0),
  ),
  GradeLook(
    'Noir',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.saturation: -100,
        GradeParam.contrast: 35,
        GradeParam.blacks: -15,
        GradeParam.vignette: 40,
      },
    ),
    Color(0xFF1A1A1A),
    Color(0xFFBEBEBE),
  ),
  GradeLook(
    'Vivid',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.saturation: 25,
        GradeParam.vibrance: 35,
        GradeParam.contrast: 12,
        GradeParam.sharpen: 25,
      },
    ),
    Color(0xFFE5484D),
    Color(0xFF3B82F6),
  ),
  GradeLook(
    'Cool',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.temperature: -30,
        GradeParam.saturation: -5,
      },
      wheels: <GradeRange, GradeWheel>{
        GradeRange.shadows: GradeWheel(hue: 220, amount: 0.3),
      },
    ),
    Color(0xFF2B4C7E),
    Color(0xFF8FB8E8),
  ),
  GradeLook(
    'Matte',
    ColorGrade(
      values: <GradeParam, double>{
        GradeParam.fade: 45,
        GradeParam.contrast: -10,
        GradeParam.blacks: 20,
        GradeParam.saturation: -10,
      },
    ),
    Color(0xFF5E5A56),
    Color(0xFFB8B3AC),
  ),
];