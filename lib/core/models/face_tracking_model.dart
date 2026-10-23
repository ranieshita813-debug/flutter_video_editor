import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class FaceKeyframe {
  const FaceKeyframe({
    required this.timeMs,
    required this.rect,
  });

  final int timeMs;
  final Rect rect; // Normalized 0..1 coordinates

  FaceKeyframe copyWith({
    int? timeMs,
    Rect? rect,
  }) {
    return FaceKeyframe(
      timeMs: timeMs ?? this.timeMs,
      rect: rect ?? this.rect,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timeMs': timeMs,
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }

  factory FaceKeyframe.fromJson(Map<String, dynamic> json) {
    return FaceKeyframe(
      timeMs: json['timeMs'] as int? ?? 0,
      rect: Rect.fromLTWH(
        (json['left'] as num?)?.toDouble() ?? 0.0,
        (json['top'] as num?)?.toDouble() ?? 0.0,
        (json['width'] as num?)?.toDouble() ?? 0.0,
        (json['height'] as num?)?.toDouble() ?? 0.0,
      ),
    );
  }
}

class FaceTrack {
  FaceTrack({
    required this.id,
    required this.frames,
  });

  final String id;
  final List<FaceKeyframe> frames;

  /// Performs binary search on keyframes to find surrounding keyframes and lerps bounding rect.
  /// Holds the last known bounding box during detection misses up to [maxGapMs].
  /// Returns null if the gap to closest keyframes exceeds [maxGapMs].
  Rect? rectAt(int tMs, {int maxGapMs = 500}) {
    if (frames.isEmpty) return null;

    if (tMs < frames.first.timeMs - maxGapMs) return null;
    if (tMs > frames.last.timeMs + maxGapMs) return null;

    int low = 0;
    int high = frames.length - 1;

    while (low <= high) {
      final int mid = (low + high) ~/ 2;
      final int midTime = frames[mid].timeMs;

      if (midTime == tMs) {
        return frames[mid].rect;
      } else if (midTime < tMs) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    final FaceKeyframe? prev = high >= 0 && high < frames.length ? frames[high] : null;
    final FaceKeyframe? next = low >= 0 && low < frames.length ? frames[low] : null;

    if (prev != null && next != null) {
      final int gap = next.timeMs - prev.timeMs;
      if (gap <= maxGapMs) {
        final double t = (tMs - prev.timeMs) / gap.toDouble();
        return Rect.lerp(prev.rect, next.rect, t.clamp(0.0, 1.0));
      } else {
        if ((tMs - prev.timeMs).abs() <= maxGapMs) return prev.rect;
        if ((next.timeMs - tMs).abs() <= maxGapMs) return next.rect;
        return null;
      }
    } else if (prev != null) {
      if ((tMs - prev.timeMs).abs() <= maxGapMs) return prev.rect;
    } else if (next != null) {
      if ((next.timeMs - tMs).abs() <= maxGapMs) return next.rect;
    }

    return null;
  }

  /// Simplifies trajectory keyframes using the Ramer-Douglas-Peucker (RDP) algorithm.
  static List<FaceKeyframe> simplifyRdp(List<FaceKeyframe> keyframes, {double epsilon = 0.01}) {
    if (keyframes.length <= 2) return List.from(keyframes);

    double maxDistance = 0.0;
    int indexWithMaxDistance = 0;

    final Offset startPoint = keyframes.first.rect.center;
    final Offset endPoint = keyframes.last.rect.center;

    for (int i = 1; i < keyframes.length - 1; i++) {
      final Offset point = keyframes[i].rect.center;
      final double dist = _perpendicularDistance(point, startPoint, endPoint);
      if (dist > maxDistance) {
        maxDistance = dist;
        indexWithMaxDistance = i;
      }
    }

    if (maxDistance > epsilon) {
      final List<FaceKeyframe> leftSegment = simplifyRdp(
        keyframes.sublist(0, indexWithMaxDistance + 1),
        epsilon: epsilon,
      );
      final List<FaceKeyframe> rightSegment = simplifyRdp(
        keyframes.sublist(indexWithMaxDistance),
        epsilon: epsilon,
      );

      return [...leftSegment.sublist(0, leftSegment.length - 1), ...rightSegment];
    } else {
      return [keyframes.first, keyframes.last];
    }
  }

  /// Smooths keyframe bounding box coordinates using Exponential Moving Average (EMA).
  static List<FaceKeyframe> applyEmaSmoothing(List<FaceKeyframe> keyframes, {double alpha = 0.3}) {
    if (keyframes.isEmpty) return [];
    final List<FaceKeyframe> smoothed = [];

    Rect prevRect = keyframes.first.rect;
    smoothed.add(keyframes.first);

    for (int i = 1; i < keyframes.length; i++) {
      final Rect currRect = keyframes[i].rect;
      final double left = alpha * currRect.left + (1.0 - alpha) * prevRect.left;
      final double top = alpha * currRect.top + (1.0 - alpha) * prevRect.top;
      final double width = alpha * currRect.width + (1.0 - alpha) * prevRect.width;
      final double height = alpha * currRect.height + (1.0 - alpha) * prevRect.height;

      final Rect newRect = Rect.fromLTWH(left, top, width, height);
      smoothed.add(keyframes[i].copyWith(rect: newRect));
      prevRect = newRect;
    }

    return smoothed;
  }

  static double _perpendicularDistance(Offset point, Offset start, Offset end) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double norm = math.sqrt(dx * dx + dy * dy);
    if (norm == 0) {
      return math.sqrt((point.dx - start.dx) * (point.dx - start.dx) + (point.dy - start.dy) * (point.dy - start.dy));
    }
    return ((dy * point.dx - dx * point.dy + end.dx * start.dy - end.dy * start.dx).abs()) / norm;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'frames': frames.map((f) => f.toJson()).toList(),
    };
  }

  factory FaceTrack.fromJson(Map<String, dynamic> json) {
    return FaceTrack(
      id: json['id'] as String? ?? '',
      frames: (json['frames'] as List<dynamic>?)
              ?.map((e) => FaceKeyframe.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <FaceKeyframe>[],
    );
  }
}

enum PersonEffectType {
  none,
  blur,
  mosaic,
  text,
  sticker,
}

class PersonEffect {
  const PersonEffect({
    this.type = PersonEffectType.none,
    this.intensity = 1.0,
    this.text = 'Face',
    this.stickerAsset = '😎',
    this.color = Colors.white,
  });

  final PersonEffectType type;
  final double intensity; // Blur sigma or mosaic pixel size
  final String text;
  final String stickerAsset;
  final Color color;

  PersonEffect copyWith({
    PersonEffectType? type,
    double? intensity,
    String? text,
    String? stickerAsset,
    Color? color,
  }) {
    return PersonEffect(
      type: type ?? this.type,
      intensity: intensity ?? this.intensity,
      text: text ?? this.text,
      stickerAsset: stickerAsset ?? this.stickerAsset,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'intensity': intensity,
      'text': text,
      'stickerAsset': stickerAsset,
      'color': color.toARGB32(),
    };
  }

  factory PersonEffect.fromJson(Map<String, dynamic> json) {
    return PersonEffect(
      type: PersonEffectType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PersonEffectType.none,
      ),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String? ?? 'Face',
      stickerAsset: json['stickerAsset'] as String? ?? '😎',
      color: Color(json['color'] as int? ?? 0xFFFFFFFF),
    );
  }
}

class Person {
  Person({
    required this.id,
    required this.name,
    this.thumbnailBytes,
    required this.tracks,
    this.effects = const <PersonEffect>[],
  });

  final String id;
  final String name;
  final Uint8List? thumbnailBytes;
  final List<FaceTrack> tracks;
  final List<PersonEffect> effects;

  /// Returns the face rect at [tMs], expanded by [margin] (20-30% privacy safety margin).
  Rect? rectAt(int tMs, {int maxGapMs = 500, double margin = 0.25}) {
    for (final track in tracks) {
      final Rect? rect = track.rectAt(tMs, maxGapMs: maxGapMs);
      if (rect != null) {
        if (margin <= 0) return rect;
        final double dw = rect.width * margin;
        final double dh = rect.height * margin;
        return Rect.fromLTRB(
          (rect.left - dw / 2).clamp(0.0, 1.0),
          (rect.top - dh / 2).clamp(0.0, 1.0),
          (rect.right + dw / 2).clamp(0.0, 1.0),
          (rect.bottom + dh / 2).clamp(0.0, 1.0),
        );
      }
    }
    return null;
  }

  /// Converts person tracks into FFmpeg filter complex expressions with spatial bounding coordinates.
  String generateFFmpegFilterComplex({double fps = 30.0, double margin = 0.25}) {
    if (effects.isEmpty || effects.first.type == PersonEffectType.none) return '';

    final PersonEffect primaryFx = effects.first;
    final List<String> filters = [];

    for (final track in tracks) {
      final List<FaceKeyframe> simplified = FaceTrack.simplifyRdp(track.frames, epsilon: 0.015);
      if (simplified.isEmpty) continue;

      final double startSec = simplified.first.timeMs / 1000.0;
      final double endSec = simplified.last.timeMs / 1000.0;
      final String enableCond = "between(t,${startSec.toStringAsFixed(2)},${endSec.toStringAsFixed(2)})";

      final Rect rawRect = simplified.first.rect;
      final double dw = rawRect.width * margin;
      final double dh = rawRect.height * margin;
      final Rect expRect = Rect.fromLTRB(
        (rawRect.left - dw / 2).clamp(0.0, 1.0),
        (rawRect.top - dh / 2).clamp(0.0, 1.0),
        (rawRect.right + dw / 2).clamp(0.0, 1.0),
        (rawRect.bottom + dh / 2).clamp(0.0, 1.0),
      );

      final String xExpr = "iw*${expRect.left.toStringAsFixed(3)}";
      final String yExpr = "ih*${expRect.top.toStringAsFixed(3)}";
      final String wExpr = "iw*${expRect.width.toStringAsFixed(3)}";
      final String hExpr = "ih*${expRect.height.toStringAsFixed(3)}";

      switch (primaryFx.type) {
        case PersonEffectType.blur:
        case PersonEffectType.mosaic:
          filters.add("drawbox=x=$xExpr:y=$yExpr:w=$wExpr:h=$hExpr:color=black@0.85:t=fill:enable='$enableCond'");
          break;
        case PersonEffectType.text:
          final String txt = primaryFx.text.replaceAll("'", "");
          filters.add("drawtext=text='$txt':x=$xExpr:y=$yExpr:fontcolor=white:fontsize=24:enable='$enableCond'");
          break;
        case PersonEffectType.sticker:
          filters.add("drawtext=text='${primaryFx.stickerAsset}':x=$xExpr:y=$yExpr:fontsize=36:enable='$enableCond'");
          break;
        case PersonEffectType.none:
          break;
      }
    }

    return filters.join(';');
  }

  Person copyWith({
    String? id,
    String? name,
    Uint8List? thumbnailBytes,
    List<FaceTrack>? tracks,
    List<PersonEffect>? effects,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      tracks: tracks != null ? List<FaceTrack>.from(tracks) : List<FaceTrack>.from(this.tracks),
      effects: effects != null ? List<PersonEffect>.from(effects) : List<PersonEffect>.from(this.effects),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'thumbnailBase64': thumbnailBytes != null ? base64Encode(thumbnailBytes!) : null,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'effects': effects.map((e) => e.toJson()).toList(),
    };
  }

  factory Person.fromJson(Map<String, dynamic> json) {
    final String? thumbStr = json['thumbnailBase64'] as String?;
    return Person(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Person',
      thumbnailBytes: thumbStr != null ? base64Decode(thumbStr) : null,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => FaceTrack.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <FaceTrack>[],
      effects: (json['effects'] as List<dynamic>?)
              ?.map((e) => PersonEffect.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <PersonEffect>[],
    );
  }
}

class FaceTrackingData {
  const FaceTrackingData({
    this.isProcessed = false,
    this.sampledFps = 5,
    this.persons = const <Person>[],
  });

  final bool isProcessed;
  final int sampledFps;
  final List<Person> persons;

  FaceTrackingData copyWith({
    bool? isProcessed,
    int? sampledFps,
    List<Person>? persons,
  }) {
    return FaceTrackingData(
      isProcessed: isProcessed ?? this.isProcessed,
      sampledFps: sampledFps ?? this.sampledFps,
      persons: persons != null ? List<Person>.from(persons) : List<Person>.from(this.persons),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isProcessed': isProcessed,
      'sampledFps': sampledFps,
      'persons': persons.map((p) => p.toJson()).toList(),
    };
  }

  factory FaceTrackingData.fromJson(Map<String, dynamic> json) {
    return FaceTrackingData(
      isProcessed: json['isProcessed'] as bool? ?? false,
      sampledFps: json['sampledFps'] as int? ?? 5,
      persons: (json['persons'] as List<dynamic>?)
              ?.map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <Person>[],
    );
  }
}
