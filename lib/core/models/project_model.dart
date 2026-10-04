import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ClipType {
  video,
  audio,
  image,
  text,
}

enum VideoEffect {
  none,
  warm,
  cinematic,
  noir,
  vibrant,
}

class TimelineClip {
  TimelineClip({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.clipType,
    this.trimIn = Duration.zero,
    this.trimOut = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.effect = VideoEffect.none,
    this.sourcePath,
  });

  final String id;
  final String label;
  final Duration start;
  final Duration end;
  final ClipType clipType;
  final Duration trimIn;
  final Duration trimOut;
  final double speed;
  final double volume;
  final VideoEffect effect;
  final String? sourcePath;

  Duration get duration => end - start;

  TimelineClip copyWith({
    String? id,
    String? label,
    Duration? start,
    Duration? end,
    ClipType? clipType,
    Duration? trimIn,
    Duration? trimOut,
    double? speed,
    double? volume,
    VideoEffect? effect,
    String? sourcePath,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      label: label ?? this.label,
      start: start ?? this.start,
      end: end ?? this.end,
      clipType: clipType ?? this.clipType,
      trimIn: trimIn ?? this.trimIn,
      trimOut: trimOut ?? this.trimOut,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      effect: effect ?? this.effect,
      sourcePath: sourcePath ?? this.sourcePath,
    );
  }
}

class VideoProject {
  VideoProject({
    List<TimelineClip>? clips,
    this.projectName = 'Untitled Project',
  }) : clips = clips ?? <TimelineClip>[];

  final String projectName;
  final List<TimelineClip> clips;

  Duration get totalDuration {
    if (clips.isEmpty) return Duration.zero;

    final maxEnd = clips
        .map((clip) => clip.end)
        .reduce((Duration current, Duration next) => current > next ? current : next);
    return maxEnd;
  }

  void addClip(TimelineClip clip) {
    clips.add(clip);
  }

  void removeClip(String id) {
    clips.removeWhere((clip) => clip.id == id);
  }

  List<TimelineClip> timelineByTrack() {
    return List<TimelineClip>.from(clips);
  }
}

class EditorStats {
  EditorStats({
    required this.playhead,
    required this.isPlaying,
    required this.zoom,
    required this.selectedClipId,
  });

  final Duration playhead;
  final bool isPlaying;
  final double zoom;
  final String? selectedClipId;

  EditorStats copyWith({
    Duration? playhead,
    bool? isPlaying,
    double? zoom,
    String? selectedClipId,
  }) {
    return EditorStats(
      playhead: playhead ?? this.playhead,
      isPlaying: isPlaying ?? this.isPlaying,
      zoom: zoom ?? this.zoom,
      selectedClipId: selectedClipId ?? this.selectedClipId,
    );
  }
}

class EditorUtils {
  static double clamp(double value, double min, double max) {
    return math.min(math.max(value, min), max);
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
