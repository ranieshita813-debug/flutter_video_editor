import 'dart:math' as math;

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

// ============================================================================
// Bounce and random keyframe curves
//
// 1. Add `bounce` and `random` to your CurveType enum:
//
//      enum CurveType { linear, easeIn, easeOut, cubicBezier, bounce, random }
//
// 2. Add these fields to Keyframe (and to copyWith / toJson / fromJson):
//
//      final int bounceCount;      // default 3,  range 1..6
//      final double bounciness;    // default 0.5, range 0.2..0.8
//      final double randomAmount;  // default 0.4, range 0.05..1.0
//      final int randomDetail;     // default 10,  range 3..24
//      final int randomSeed;       // default 7
//
//    Save randomSeed with the project so preview and FFmpeg export match.
//
// 3. Replace _kfEval in keyframe_sheet.dart and your playback evaluator with
//    evalKeyframeCurve below. t is 0..1, the result is 0..1 (it may overshoot).
// ============================================================================

class CurveParams {
  const CurveParams({
    this.bounceCount = 3,
    this.bounciness = 0.5,
    this.randomAmount = 0.4,
    this.randomDetail = 10,
    this.randomSeed = 7,
  });

  final int bounceCount;
  final double bounciness;
  final double randomAmount;
  final int randomDetail;
  final int randomSeed;
}

/// Ball-drop bounce. The fall takes 1 unit of time, and bounce k takes
/// 2 * r^k units and peaks at r^(2k) of the drop height.
double bounceCurve(double t, {int bounces = 3, double bounciness = 0.5}) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  final int n = bounces.clamp(1, 6);
  final double r = bounciness.clamp(0.2, 0.8);

  double total = 1;
  for (int i = 1; i <= n; i++) {
    total += 2 * math.pow(r, i);
  }

  double u = t * total;
  if (u <= 1) return u * u; // first fall

  u -= 1;
  for (int i = 1; i <= n; i++) {
    final double half = math.pow(r, i).toDouble();
    if (u <= 2 * half) {
      final double d = (u - half) / half; // -1..1 across this bounce
      return 1 - math.pow(r, 2 * i) * (1 - d * d);
    }
    u -= 2 * half;
  }
  return 1;
}

final Map<int, List<double>> _noiseCache = <int, List<double>>{};

List<double> _noisePoints(int seed, int detail) {
  final int key = seed * 100 + detail;
  return _noiseCache.putIfAbsent(key, () {
    final math.Random rng = math.Random(seed);
    return List<double>.generate(detail + 1, (_) => rng.nextDouble() * 2 - 1);
  });
}

/// Smooth seeded wobble around a linear ramp. Start and end are pinned to
/// 0 and 1, so the value never jumps at the keyframes.
double randomCurve(
  double t, {
  double amount = 0.4,
  int detail = 10,
  int seed = 7,
}) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  final int n = detail.clamp(3, 24);
  final List<double> pts = _noisePoints(seed, n);

  final double x = t * n;
  final int i = x.floor();
  final double f = x - i;
  final double s = f * f * (3 - 2 * f); // smoothstep
  final double noise = pts[i] * (1 - s) + pts[i + 1] * s;

  return t + amount * 0.5 * noise * math.sin(math.pi * t);
}

/// Drop-in replacement for _kfEval. Reuse your existing easing and cubic bezier
/// code for the first four cases.
double evalKeyframeCurve(
  double t,
  CurveType type, {
  double cp1x = 0.25,
  double cp1y = 0.1,
  double cp2x = 0.25,
  double cp2y = 1.0,
  CurveParams params = const CurveParams(),
}) {
  switch (type) {
    case CurveType.linear:
      return t;
    case CurveType.easeIn:
      return t * t;
    case CurveType.easeOut:
      return t * (2 - t);
    case CurveType.cubicBezier:
      return solveCubicBezierY(t, cp1x, cp1y, cp2x, cp2y);
    case CurveType.bounce:
      return bounceCurve(t,
          bounces: params.bounceCount, bounciness: params.bounciness);
    case CurveType.random:
      return randomCurve(t,
          amount: params.randomAmount,
          detail: params.randomDetail,
          seed: params.randomSeed);
  }
}

/// Use this in playback and export: `kf.ease(t)` where t is 0..1 inside the
/// segment that starts at this keyframe.
extension KeyframeCurveX on Keyframe {
  double ease(double t) => evalKeyframeCurve(
        t,
        curveType,
        cp1x: cp1x,
        cp1y: cp1y,
        cp2x: cp2x,
        cp2y: cp2y,
        params: CurveParams(
          bounceCount: bounceCount,
          bounciness: bounciness,
          randomAmount: randomAmount,
          randomDetail: randomDetail,
          randomSeed: randomSeed,
        ),
      );
}