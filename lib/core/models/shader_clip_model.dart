import 'package:flutter/material.dart';

enum AnimationEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
}

class ShaderKeyframe {
  const ShaderKeyframe({
    required this.id,
    required this.time,
    required this.value,
    this.easing = AnimationEasing.linear,
  });

  final String id;
  final Duration time;
  final dynamic value;
  final AnimationEasing easing;

  ShaderKeyframe copyWith({
    String? id,
    Duration? time,
    dynamic value,
    AnimationEasing? easing,
  }) {
    return ShaderKeyframe(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      easing: easing ?? this.easing,
    );
  }

  Map<String, dynamic> toJson() {
    dynamic val = value;
    if (value is Color) {
      val = (value as Color).toARGB32();
    } else if (value is Offset) {
      val = <String, double>{
        'x': (value as Offset).dx,
        'y': (value as Offset).dy,
      };
    }

    return <String, dynamic>{
      'id': id,
      'timeMs': time.inMilliseconds,
      'value': val,
      'easing': easing.name,
    };
  }

  factory ShaderKeyframe.fromJson(Map<String, dynamic> json) {
    dynamic val = json['value'];
    if (val is Map) {
      val = Offset(
        (val['x'] as num?)?.toDouble() ?? 0.0,
        (val['y'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return ShaderKeyframe(
      id: json['id'] as String? ?? '',
      time: Duration(milliseconds: json['timeMs'] as int? ?? 0),
      value: val ?? 0.0,
      easing: AnimationEasing.values.firstWhere(
        (e) => e.name == json['easing'],
        orElse: () => AnimationEasing.linear,
      ),
    );
  }
}

class KeyframeAnimation {
  const KeyframeAnimation({
    required this.id,
    required this.parameterId,
    this.keyframes = const <ShaderKeyframe>[],
  });

  final String id;
  final String parameterId;
  final List<ShaderKeyframe> keyframes;

  KeyframeAnimation copyWith({
    String? id,
    String? parameterId,
    List<ShaderKeyframe>? keyframes,
  }) {
    return KeyframeAnimation(
      id: id ?? this.id,
      parameterId: parameterId ?? this.parameterId,
      keyframes: keyframes ?? this.keyframes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'parameterId': parameterId,
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
    };
  }

  factory KeyframeAnimation.fromJson(Map<String, dynamic> json) {
    return KeyframeAnimation(
      id: json['id'] as String? ?? '',
      parameterId: json['parameterId'] as String? ?? '',
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((e) => ShaderKeyframe.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const <ShaderKeyframe>[],
    );
  }

  dynamic evaluateAt(Duration time) {
    if (keyframes.isEmpty) return null;

    final sorted = List<ShaderKeyframe>.from(keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));

    if (time <= sorted.first.time) return sorted.first.value;
    if (time >= sorted.last.time) return sorted.last.value;

    for (int i = 0; i < sorted.length - 1; i++) {
      final k1 = sorted[i];
      final k2 = sorted[i + 1];
      if (time >= k1.time && time <= k2.time) {
        final totalMs = (k2.time - k1.time).inMilliseconds;
        if (totalMs == 0) return k1.value;
        final elapsedMs = (time - k1.time).inMilliseconds;
        final rawT = (elapsedMs / totalMs).clamp(0.0, 1.0);
        final t = _applyEasing(rawT, k2.easing);
        return _interpolateValues(k1.value, k2.value, t);
      }
    }

    return sorted.last.value;
  }

  static double _applyEasing(double t, AnimationEasing easing) {
    switch (easing) {
      case AnimationEasing.linear:
        return t;
      case AnimationEasing.easeIn:
        return t * t;
      case AnimationEasing.easeOut:
        return t * (2 - t);
      case AnimationEasing.easeInOut:
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    }
  }

  static dynamic _interpolateValues(dynamic v1, dynamic v2, double t) {
    if (v1 is num && v2 is num) {
      return (v1.toDouble() + (v2.toDouble() - v1.toDouble()) * t);
    }
    if (v1 is Color && v2 is Color) {
      return Color.lerp(v1, v2, t) ?? v1;
    }
    if (v1 is int && v2 is Color) {
      return Color.lerp(Color(v1), v2, t) ?? Color(v1);
    }
    if (v1 is Color && v2 is int) {
      return Color.lerp(v1, Color(v2), t) ?? v1;
    }
    if (v1 is int && v2 is int) {
      return Color.lerp(Color(v1), Color(v2), t)?.toARGB32() ?? v1;
    }
    if (v1 is Offset && v2 is Offset) {
      return Offset.lerp(v1, v2, t) ?? v1;
    }
    if (t >= 0.5) return v2;
    return v1;
  }
}

class ShaderEffectClip {
  ShaderEffectClip({
    required this.id,
    required this.effectId,
    required this.name,
    required this.start,
    required this.end,
    this.isEnabled = true,
    this.zIndex = 0,
    Map<String, dynamic>? parameterValues,
    List<KeyframeAnimation>? keyframeAnimations,
  })  : parameterValues = parameterValues ?? <String, dynamic>{},
        keyframeAnimations = keyframeAnimations ?? <KeyframeAnimation>[];

  final String id;
  final String effectId;
  final String name;
  final Duration start;
  final Duration end;
  final bool isEnabled;
  final int zIndex;
  final Map<String, dynamic> parameterValues;
  final List<KeyframeAnimation> keyframeAnimations;

  Duration get duration => end - start;

  ShaderEffectClip copyWith({
    String? id,
    String? effectId,
    String? name,
    Duration? start,
    Duration? end,
    bool? isEnabled,
    int? zIndex,
    Map<String, dynamic>? parameterValues,
    List<KeyframeAnimation>? keyframeAnimations,
  }) {
    return ShaderEffectClip(
      id: id ?? this.id,
      effectId: effectId ?? this.effectId,
      name: name ?? this.name,
      start: start ?? this.start,
      end: end ?? this.end,
      isEnabled: isEnabled ?? this.isEnabled,
      zIndex: zIndex ?? this.zIndex,
      parameterValues: parameterValues != null
          ? Map<String, dynamic>.from(parameterValues)
          : Map<String, dynamic>.from(this.parameterValues),
      keyframeAnimations: keyframeAnimations != null
          ? List<KeyframeAnimation>.from(keyframeAnimations)
          : List<KeyframeAnimation>.from(this.keyframeAnimations),
    );
  }

  Map<String, dynamic> getInterpolatedParameters(Duration clipRelativeTime) {
    final result = Map<String, dynamic>.from(parameterValues);

    for (final anim in keyframeAnimations) {
      final evaluated = anim.evaluateAt(clipRelativeTime);
      if (evaluated != null) {
        result[anim.parameterId] = evaluated;
      }
    }

    return result;
  }

  Map<String, dynamic> toJson() {
    final serializedParams = <String, dynamic>{};
    parameterValues.forEach((key, val) {
      if (val is Color) {
        serializedParams[key] = val.toARGB32();
      } else if (val is Offset) {
        serializedParams[key] = <String, double>{'x': val.dx, 'y': val.dy};
      } else {
        serializedParams[key] = val;
      }
    });

    return <String, dynamic>{
      'id': id,
      'effectId': effectId,
      'name': name,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
      'isEnabled': isEnabled,
      'zIndex': zIndex,
      'parameterValues': serializedParams,
      'keyframeAnimations': keyframeAnimations.map((a) => a.toJson()).toList(),
    };
  }

  factory ShaderEffectClip.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameterValues'] as Map<String, dynamic>? ?? {};
    final parsedParams = <String, dynamic>{};

    rawParams.forEach((key, val) {
      if (val is Map) {
        parsedParams[key] = Offset(
          (val['x'] as num?)?.toDouble() ?? 0.0,
          (val['y'] as num?)?.toDouble() ?? 0.0,
        );
      } else {
        parsedParams[key] = val;
      }
    });

    return ShaderEffectClip(
      id: json['id'] as String? ?? '',
      effectId: json['effectId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
      isEnabled: json['isEnabled'] as bool? ?? true,
      zIndex: json['zIndex'] as int? ?? 0,
      parameterValues: parsedParams,
      keyframeAnimations: (json['keyframeAnimations'] as List<dynamic>?)
              ?.map((e) => KeyframeAnimation.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <KeyframeAnimation>[],
    );
  }
}
