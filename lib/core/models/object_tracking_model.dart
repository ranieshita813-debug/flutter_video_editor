import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ObjectKeyframe {
  const ObjectKeyframe({
    required this.timeMs,
    required this.rect,
  });

  final int timeMs;
  final Rect rect; // Normalized 0..1 bounding box coordinates

  ObjectKeyframe copyWith({
    int? timeMs,
    Rect? rect,
  }) {
    return ObjectKeyframe(
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

  factory ObjectKeyframe.fromJson(Map<String, dynamic> json) {
    return ObjectKeyframe(
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

class ObjectTrack {
  ObjectTrack({
    required this.id,
    required this.frames,
  });

  final String id;
  final List<ObjectKeyframe> frames;

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

    final ObjectKeyframe? prev = high >= 0 && high < frames.length ? frames[high] : null;
    final ObjectKeyframe? next = low >= 0 && low < frames.length ? frames[low] : null;

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

  static List<ObjectKeyframe> applyEmaSmoothing(List<ObjectKeyframe> keyframes, {double alpha = 0.3}) {
    if (keyframes.isEmpty) return [];
    final List<ObjectKeyframe> smoothed = [];

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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'frames': frames.map((f) => f.toJson()).toList(),
    };
  }

  factory ObjectTrack.fromJson(Map<String, dynamic> json) {
    return ObjectTrack(
      id: json['id'] as String? ?? '',
      frames: (json['frames'] as List<dynamic>?)
              ?.map((e) => ObjectKeyframe.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <ObjectKeyframe>[],
    );
  }
}

enum ObjectEffectType {
  none,
  blur,
  mosaic,
  text,
  sticker,
  boxHighlight,
}

class ObjectEffect {
  const ObjectEffect({
    this.type = ObjectEffectType.none,
    this.intensity = 1.0,
    this.text = 'Target',
    this.stickerAsset = '🎯',
    this.color = Colors.cyan,
  });

  final ObjectEffectType type;
  final double intensity;
  final String text;
  final String stickerAsset;
  final Color color;

  ObjectEffect copyWith({
    ObjectEffectType? type,
    double? intensity,
    String? text,
    String? stickerAsset,
    Color? color,
  }) {
    return ObjectEffect(
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

  factory ObjectEffect.fromJson(Map<String, dynamic> json) {
    return ObjectEffect(
      type: ObjectEffectType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ObjectEffectType.none,
      ),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String? ?? 'Target',
      stickerAsset: json['stickerAsset'] as String? ?? '🎯',
      color: Color(json['color'] as int? ?? 0xFF00E5FF),
    );
  }
}

class TrackedObject {
  TrackedObject({
    required this.id,
    required this.label,
    required this.category,
    this.thumbnailBytes,
    required this.tracks,
    this.effects = const <ObjectEffect>[],
  });

  final String id;
  final String label;
  final String category; // e.g. "vehicle", "pet", "person", "phone", "general"
  final Uint8List? thumbnailBytes;
  final List<ObjectTrack> tracks;
  final List<ObjectEffect> effects;

  Rect? rectAt(int tMs, {int maxGapMs = 500, double margin = 0.15}) {
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

  TrackedObject copyWith({
    String? id,
    String? label,
    String? category,
    Uint8List? thumbnailBytes,
    List<ObjectTrack>? tracks,
    List<ObjectEffect>? effects,
  }) {
    return TrackedObject(
      id: id ?? this.id,
      label: label ?? this.label,
      category: category ?? this.category,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      tracks: tracks != null ? List<ObjectTrack>.from(tracks) : List<ObjectTrack>.from(this.tracks),
      effects: effects != null ? List<ObjectEffect>.from(effects) : List<ObjectEffect>.from(this.effects),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'category': category,
      'thumbnailBase64': thumbnailBytes != null ? base64Encode(thumbnailBytes!) : null,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'effects': effects.map((e) => e.toJson()).toList(),
    };
  }

  factory TrackedObject.fromJson(Map<String, dynamic> json) {
    final String? thumbStr = json['thumbnailBase64'] as String?;
    return TrackedObject(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Object',
      category: json['category'] as String? ?? 'general',
      thumbnailBytes: thumbStr != null ? base64Decode(thumbStr) : null,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => ObjectTrack.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <ObjectTrack>[],
      effects: (json['effects'] as List<dynamic>?)
              ?.map((e) => ObjectEffect.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <ObjectEffect>[],
    );
  }
}

class ObjectTrackingData {
  const ObjectTrackingData({
    this.isProcessed = false,
    this.sampledFps = 5,
    this.objects = const <TrackedObject>[],
  });

  final bool isProcessed;
  final int sampledFps;
  final List<TrackedObject> objects;

  ObjectTrackingData copyWith({
    bool? isProcessed,
    int? sampledFps,
    List<TrackedObject>? objects,
  }) {
    return ObjectTrackingData(
      isProcessed: isProcessed ?? this.isProcessed,
      sampledFps: sampledFps ?? this.sampledFps,
      objects: objects != null ? List<TrackedObject>.from(objects) : List<TrackedObject>.from(this.objects),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isProcessed': isProcessed,
      'sampledFps': sampledFps,
      'objects': objects.map((o) => o.toJson()).toList(),
    };
  }

  factory ObjectTrackingData.fromJson(Map<String, dynamic> json) {
    return ObjectTrackingData(
      isProcessed: json['isProcessed'] as bool? ?? false,
      sampledFps: json['sampledFps'] as int? ?? 5,
      objects: (json['objects'] as List<dynamic>?)
              ?.map((e) => TrackedObject.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <TrackedObject>[],
    );
  }
}
