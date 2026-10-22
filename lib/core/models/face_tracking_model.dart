import 'dart:convert';
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
  /// If the gap to the closest keyframe exceeds [maxGapMs], returns null (no face detected).
  Rect? rectAt(int tMs, {int maxGapMs = 400}) {
    if (frames.isEmpty) return null;

    // Sort check - assume frames are ordered by timeMs
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

    // high is the index before tMs, low is index after tMs
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
  Rect? rectAt(int tMs, {int maxGapMs = 400, double margin = 0.25}) {
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
