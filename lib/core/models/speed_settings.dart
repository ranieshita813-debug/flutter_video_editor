// lib/core/models/speed_settings.dart
//
// Pure Dart (no Flutter widgets): model, validation, time remapping and
// FFmpeg filter generation for constant-speed and speed-curve clips.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const double kMinSpeed = 0.1;
const double kMaxSpeed = 10.0;
const int kMaxCurvePoints = 12;

enum SpeedMode { normal, curve }

@immutable
class SpeedPoint {
  const SpeedPoint(this.x, this.speed);

  /// Position along the clip, 0..1.
  final double x;

  /// Speed multiplier, [kMinSpeed]..[kMaxSpeed].
  final double speed;

  SpeedPoint copyWith({double? x, double? speed}) =>
      SpeedPoint(x ?? this.x, speed ?? this.speed);

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'speed': speed};

  factory SpeedPoint.fromJson(Map<String, dynamic> j) =>
      SpeedPoint((j['x'] as num).toDouble(), (j['speed'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is SpeedPoint && other.x == x && other.speed == speed;

  @override
  int get hashCode => Object.hash(x, speed);
}

@immutable
class SpeedSettings {
  const SpeedSettings({
    this.mode = SpeedMode.normal,
    this.speed = 1.0,
    this.points = _flat,
    this.maintainPitch = true,
    this.smoothSlowMotion = false,
    this.reverse = false,
    this.preset = 'Custom',
  });

  static const List<SpeedPoint> _flat = <SpeedPoint>[
    SpeedPoint(0, 1),
    SpeedPoint(1, 1),
  ];

  static const SpeedSettings identity = SpeedSettings();

  final SpeedMode mode;
  final double speed;
  final List<SpeedPoint> points;
  final bool maintainPitch;
  final bool smoothSlowMotion;
  final bool reverse;

  /// UI-only label of the last curve preset. Ignored by ==.
  final String preset;

  // ---- derived --------------------------------------------------------------

  /// True when applying these settings changes nothing.
  bool get isIdentity {
    if (reverse) return false;
    if (mode == SpeedMode.normal) return (speed - 1).abs() < 1e-6;
    return points.every((p) => (p.speed - 1).abs() < 1e-6);
  }

  /// Speed at position [x] (0..1) along the played clip.
  double speedAt(double x) =>
      mode == SpeedMode.normal ? speed : interpolate(points, x);

  /// Output duration / source duration (mean of 1/speed along the clip).
  double get durationFactor {
    if (mode == SpeedMode.normal) return 1 / speed;
    const int n = 400;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      sum += 1 / interpolate(points, (i + 0.5) / n);
    }
    return sum / n;
  }

  /// Constant speed that produces the same output duration.
  double get averageSpeed => 1 / durationFactor;

  Duration outputDuration(Duration source) => Duration(
      microseconds: (source.inMicroseconds * durationFactor).round());

  // ---- editing --------------------------------------------------------------

  SpeedSettings copyWith({
    SpeedMode? mode,
    double? speed,
    List<SpeedPoint>? points,
    bool? maintainPitch,
    bool? smoothSlowMotion,
    bool? reverse,
    String? preset,
  }) =>
      SpeedSettings(
        mode: mode ?? this.mode,
        speed: speed ?? this.speed,
        points: points ?? this.points,
        maintainPitch: maintainPitch ?? this.maintainPitch,
        smoothSlowMotion: smoothSlowMotion ?? this.smoothSlowMotion,
        reverse: reverse ?? this.reverse,
        preset: preset ?? this.preset,
      );

  /// Clamps speeds, sorts and de-duplicates points, pins the ends to x=0
  /// and x=1, and caps the point count. Always call before persisting.
  SpeedSettings normalized() => copyWith(
        speed: speed.clamp(kMinSpeed, kMaxSpeed).toDouble(),
        points: cleanPoints(points),
      );

  static List<SpeedPoint> cleanPoints(List<SpeedPoint> src) {
    final List<SpeedPoint> l = src
        .where((p) => p.x.isFinite && p.speed.isFinite && p.speed > 0)
        .map((p) => SpeedPoint(
              p.x.clamp(0.0, 1.0).toDouble(),
              p.speed.clamp(kMinSpeed, kMaxSpeed).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    final List<SpeedPoint> out = <SpeedPoint>[];
    for (final p in l) {
      if (out.isNotEmpty && p.x - out.last.x < 1e-3) continue;
      out.add(p);
    }
    if (out.isEmpty) return _flat;
    if (out.first.x > 0) out.insert(0, SpeedPoint(0, out.first.speed));
    if (out.last.x < 1) out.add(SpeedPoint(1, out.last.speed));
    return out.length > kMaxCurvePoints ? out.sublist(0, kMaxCurvePoints) : out;
  }

  /// Smoothstep easing in log-speed space between neighbouring points.
  static double interpolate(List<SpeedPoint> pts, double x) {
    if (pts.isEmpty) return 1;
    if (x <= pts.first.x) return pts.first.speed;
    for (int i = 0; i < pts.length - 1; i++) {
      final SpeedPoint a = pts[i], b = pts[i + 1];
      if (x <= b.x) {
        final double k = (x - a.x) / math.max(b.x - a.x, 1e-6);
        final double e = k * k * (3 - 2 * k);
        return math.exp(
            math.log(a.speed) + (math.log(b.speed) - math.log(a.speed)) * e);
      }
    }
    return pts.last.speed;
  }

  // ---- persistence ----------------------------------------------------------

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.name,
        'speed': speed,
        'points': points.map((p) => p.toJson()).toList(),
        'maintainPitch': maintainPitch,
        'smoothSlowMotion': smoothSlowMotion,
        'reverse': reverse,
      };

  /// Tolerant of missing/invalid fields (older projects).
  factory SpeedSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return identity;
    try {
      return SpeedSettings(
        mode: SpeedMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => SpeedMode.normal,
        ),
        speed: ((j['speed'] as num?) ?? 1).toDouble(),
        points: ((j['points'] as List?) ?? const <dynamic>[])
            .map((e) => SpeedPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        maintainPitch: (j['maintainPitch'] as bool?) ?? true,
        smoothSlowMotion: (j['smoothSlowMotion'] as bool?) ?? false,
        reverse: (j['reverse'] as bool?) ?? false,
      ).normalized();
    } catch (_) {
      return identity;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SpeedSettings &&
      other.mode == mode &&
      other.speed == speed &&
      listEquals(other.points, points) &&
      other.maintainPitch == maintainPitch &&
      other.smoothSlowMotion == smoothSlowMotion &&
      other.reverse == reverse;

  @override
  int get hashCode => Object.hash(
      mode, speed, Object.hashAll(points), maintainPitch, smoothSlowMotion, reverse);
}

/// Maps between output time and source time for a clip with a speed curve.
/// Use it for playback seeking, the playhead and thumbnail sampling.
///
/// All values are fractions in 0..1. When [SpeedSettings.reverse] is set the
/// source fraction runs backwards.
class SpeedRamp {
  SpeedRamp(this.settings, {int resolution = 512})
      : _n = resolution,
        _cum = List<double>.filled(resolution + 1, 0) {
    for (int i = 1; i <= _n; i++) {
      _cum[i] = _cum[i - 1] + 1 / settings.speedAt((i - 0.5) / _n);
    }
    final double total = _cum[_n];
    for (int i = 0; i <= _n; i++) {
      _cum[i] /= total;
    }
  }

  final SpeedSettings settings;
  final int _n;
  final List<double> _cum; // output fraction at source fraction i/_n

  /// Where in the source to read for a given position in the output.
  double sourceFractionAtOutput(double out) {
    final double o = out.clamp(0.0, 1.0).toDouble();
    int lo = 0, hi = _n;
    while (hi - lo > 1) {
      final int mid = (lo + hi) >> 1;
      if (_cum[mid] <= o) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final double span = math.max(_cum[hi] - _cum[lo], 1e-12);
    final double f = (lo + (o - _cum[lo]) / span) / _n;
    final double clamped = f.clamp(0.0, 1.0).toDouble();
    return settings.reverse ? 1 - clamped : clamped;
  }

  /// Where in the output a given source position lands.
  double outputFractionAtSource(double src) {
    final double s = (settings.reverse ? 1 - src : src).clamp(0.0, 1.0).toDouble();
    final double pos = s * _n;
    final int i = math.min(pos.floor(), _n - 1);
    return _cum[i] + (_cum[i + 1] - _cum[i]) * (pos - i);
  }
}

/// FFmpeg filter strings for [SpeedSettings].
class SpeedFilterGraph {
  const SpeedFilterGraph({this.videoFilter, this.audioFilter, this.filterComplex});

  /// Simple graph (-vf / -af). Set in normal mode.
  final String? videoFilter;
  final String? audioFilter;

  /// Full graph (-filter_complex) with outputs [outv] and [outa].
  /// Set in curve mode.
  final String? filterComplex;

  bool get isComplex => filterComplex != null;
}

abstract final class SpeedFilters {
  static String _n(double v) => v.toStringAsFixed(6);

  /// atempo only accepts 0.5..2.0 on older FFmpeg builds, so chain it.
  static String atempoChain(double speed) {
    final List<String> parts = <String>[];
    double s = speed;
    while (s > 2.0) {
      parts.add('atempo=2.0');
      s /= 2;
    }
    while (s < 0.5) {
      parts.add('atempo=0.5');
      s /= 0.5;
    }
    parts.add('atempo=${_n(s)}');
    return parts.join(',');
  }

  static String _audio(double s, bool keepPitch, int sampleRate) => keepPitch
      ? atempoChain(s)
      : 'asetrate=${(sampleRate * s).round()},aresample=$sampleRate';

  /// Builds the filters for [settings] applied to a clip of [sourceSeconds].
  ///
  /// Curves are rendered as [segments] constant-speed slices (trim + setpts +
  /// concat). Raise [segments] for smoother ramps, lower it for faster exports.
  static SpeedFilterGraph build(
    SpeedSettings settings, {
    required double sourceSeconds,
    bool hasAudio = true,
    int sampleRate = 44100,
    int smoothFps = 60,
    int segments = 32,
  }) {
    final SpeedSettings s = settings.normalized();

    String minterp(double speedForCheck) => s.smoothSlowMotion && speedForCheck < 1
        ? ',minterpolate=fps=$smoothFps:mi_mode=mci:mc_mode=aobmc:vsbmc=1'
        : '';

    if (s.mode == SpeedMode.normal) {
      final String v = '${s.reverse ? 'reverse,' : ''}'
          'setpts=${_n(1 / s.speed)}*PTS${minterp(s.speed)}';
      final String? a = hasAudio
          ? '${s.reverse ? 'areverse,' : ''}${_audio(s.speed, s.maintainPitch, sampleRate)}'
          : null;
      return SpeedFilterGraph(videoFilter: v, audioFilter: a);
    }

    final int n = math.max(2, segments);
    final StringBuffer g = StringBuffer();
    String vIn = '0:v', aIn = '0:a';
    if (s.reverse) {
      g.write('[0:v]reverse[rv];');
      vIn = 'rv';
      if (hasAudio) {
        g.write('[0:a]areverse[ra];');
        aIn = 'ra';
      }
    }
    for (int i = 0; i < n; i++) {
      final double x0 = i / n, x1 = (i + 1) / n;
      // Harmonic mean over the slice keeps the slice duration exact.
      final double sp = 1 / ((1 / s.speedAt(x0 + (x1 - x0) * 0.25) +
              1 / s.speedAt(x0 + (x1 - x0) * 0.75)) /
          2);
      final String t0 = _n(x0 * sourceSeconds), t1 = _n(x1 * sourceSeconds);
      g.write('[$vIn]trim=start=$t0:end=$t1,'
          'setpts=(PTS-STARTPTS)*${_n(1 / sp)}${minterp(sp)}[v$i];');
      if (hasAudio) {
        g.write('[$aIn]atrim=start=$t0:end=$t1,asetpts=PTS-STARTPTS,'
            '${_audio(sp, s.maintainPitch, sampleRate)}[a$i];');
      }
    }
    g.write('${List<String>.generate(n, (i) => '[v$i]').join()}'
        'concat=n=$n:v=1:a=0[outv]');
    if (hasAudio) {
      g.write(';${List<String>.generate(n, (i) => '[a$i]').join()}'
          'concat=n=$n:v=0:a=1[outa]');
    }
    return SpeedFilterGraph(filterComplex: g.toString());
  }
}