import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ClipType {
  video,
  audio,
  image,
  text,
  drawing,
  sticker,
  caption,
}

enum VideoEffect {
  none,
  warm,
  cinematic,
  noir,
  vibrant,
  vintage,
  glitch,
  blur,
}

enum TextAnimationStyle {
  none,
  fadeIn,
  typewriter,
  slideUp,
  bounce,
  scaleUp,
}

enum ExportFormat {
  mp4,
  mov,
  gif,
}

enum ExportResolution {
  res720p('720p', 1280, 720),
  res1080p('1080p', 1920, 1080),
  res4k('4K', 3840, 2160);

  const ExportResolution(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;
}

enum ExportQuality {
  low('Low Quality', 4.0),
  medium('Medium Quality', 8.0),
  high('High Quality', 16.0),
  ultra('Ultra High Quality', 25.0);

  const ExportQuality(this.label, this.bitrateMbps);
  final String label;
  final double bitrateMbps;
}

enum AspectRatioPreset {
  nineSixteen('9:16', 9 / 16),
  sixteenNine('16:9', 16 / 9),
  oneOne('1:1', 1 / 1),
  fourFive('4:5', 4 / 5),
  original('Original', 0.0);

  const AspectRatioPreset(this.label, this.ratio);
  final String label;
  final double ratio;
}

class DrawingPoint {
  DrawingPoint({
    required this.offset,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });

  final Offset offset;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
}

class DrawingStroke {
  DrawingStroke({
    required this.id,
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final String id;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
}

class ColorGradingSettings {
  const ColorGradingSettings({
    this.brightness = 0.0, // -1.0 to 1.0
    this.contrast = 1.0,   // 0.0 to 2.0
    this.saturation = 1.0, // 0.0 to 2.0
    this.temperature = 0.0, // -1.0 to 1.0
    this.tint = 0.0,       // -1.0 to 1.0
    this.exposure = 0.0,   // -1.0 to 1.0
    this.vignette = 0.0,   // 0.0 to 1.0
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double exposure;
  final double vignette;

  ColorGradingSettings copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    double? exposure,
    double? vignette,
  }) {
    return ColorGradingSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      exposure: exposure ?? this.exposure,
      vignette: vignette ?? this.vignette,
    );
  }
}

class AudioProperties {
  const AudioProperties({
    this.volume = 1.0,
    this.speed = 1.0,
    this.pitch = 1.0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.equalizerPreset = 'Flat',
  });

  final double volume;
  final double speed;
  final double pitch;
  final Duration fadeIn;
  final Duration fadeOut;
  final String equalizerPreset;

  AudioProperties copyWith({
    double? volume,
    double? speed,
    double? pitch,
    Duration? fadeIn,
    Duration? fadeOut,
    String? equalizerPreset,
  }) {
    return AudioProperties(
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
    );
  }
}

class CaptionCue {
  CaptionCue({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
  });

  final String id;
  final Duration start;
  final Duration end;
  final String text;

  CaptionCue copyWith({
    String? id,
    Duration? start,
    Duration? end,
    String? text,
  }) {
    return CaptionCue(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
    );
  }
}

class TrackingData {
  const TrackingData({
    this.isEnabled = false,
    this.targetName = 'Face',
    this.rect = const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    this.smoothness = 0.8,
  });

  final bool isEnabled;
  final String targetName;
  final Rect rect; // Normalized coordinates (0..1)
  final double smoothness;

  TrackingData copyWith({
    bool? isEnabled,
    String? targetName,
    Rect? rect,
    double? smoothness,
  }) {
    return TrackingData(
      isEnabled: isEnabled ?? this.isEnabled,
      targetName: targetName ?? this.targetName,
      rect: rect ?? this.rect,
      smoothness: smoothness ?? this.smoothness,
    );
  }
}

class ExportSettings {
  const ExportSettings({
    this.resolution = ExportResolution.res1080p,
    this.fps = 30,
    this.quality = ExportQuality.high,
    this.format = ExportFormat.mp4,
    this.customBitrateMbps,
  });

  final ExportResolution resolution;
  final int fps;
  final ExportQuality quality;
  final ExportFormat format;
  final double? customBitrateMbps;

  double get effectiveBitrate => customBitrateMbps ?? quality.bitrateMbps;

  ExportSettings copyWith({
    ExportResolution? resolution,
    int? fps,
    ExportQuality? quality,
    ExportFormat? format,
    double? customBitrateMbps,
  }) {
    return ExportSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      quality: quality ?? this.quality,
      format: format ?? this.format,
      customBitrateMbps: customBitrateMbps ?? this.customBitrateMbps,
    );
  }
}

class TimelineClip {
  TimelineClip({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.clipType,
    this.layerIndex = 0,
    this.isVisible = true,
    this.isLocked = false,
    this.trimIn = Duration.zero,
    this.trimOut = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.opacity = 1.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.effect = VideoEffect.none,
    this.sourcePath,
    this.stickerAssetPath,
    this.fontFamily = 'Poppins',
    this.textAnimationStyle = TextAnimationStyle.none,
    this.colorGrading = const ColorGradingSettings(),
    this.audioProperties = const AudioProperties(),
    this.strokes = const <DrawingStroke>[],
    this.trackingData = const TrackingData(),
    this.waveform,
    this.thumbnails,
  });

  final String id;
  final String label;
  final Duration start;
  final Duration end;
  final ClipType clipType;
  final int layerIndex;
  final bool isVisible;
  final bool isLocked;
  final Duration trimIn;
  final Duration trimOut;
  final double speed;
  final double volume;
  final double opacity;
  final double scale;
  final double rotation;
  final double positionX;
  final double positionY;
  final VideoEffect effect;
  final String? sourcePath;
  final String? stickerAssetPath;
  final String fontFamily;
  final TextAnimationStyle textAnimationStyle;
  final ColorGradingSettings colorGrading;
  final AudioProperties audioProperties;
  final List<DrawingStroke> strokes;
  final TrackingData trackingData;
  final List<double>? waveform;
  final List<String>? thumbnails;

  Duration get duration => end - start;

  TimelineClip copyWith({
    String? id,
    String? label,
    Duration? start,
    Duration? end,
    ClipType? clipType,
    int? layerIndex,
    bool? isVisible,
    bool? isLocked,
    Duration? trimIn,
    Duration? trimOut,
    double? speed,
    double? volume,
    double? opacity,
    double? scale,
    double? rotation,
    double? positionX,
    double? positionY,
    VideoEffect? effect,
    String? sourcePath,
    String? stickerAssetPath,
    String? fontFamily,
    TextAnimationStyle? textAnimationStyle,
    ColorGradingSettings? colorGrading,
    AudioProperties? audioProperties,
    List<DrawingStroke>? strokes,
    TrackingData? trackingData,
    List<double>? waveform,
    List<String>? thumbnails,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      label: label ?? this.label,
      start: start ?? this.start,
      end: end ?? this.end,
      clipType: clipType ?? this.clipType,
      layerIndex: layerIndex ?? this.layerIndex,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      trimIn: trimIn ?? this.trimIn,
      trimOut: trimOut ?? this.trimOut,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      effect: effect ?? this.effect,
      sourcePath: sourcePath ?? this.sourcePath,
      stickerAssetPath: stickerAssetPath ?? this.stickerAssetPath,
      fontFamily: fontFamily ?? this.fontFamily,
      textAnimationStyle: textAnimationStyle ?? this.textAnimationStyle,
      colorGrading: colorGrading ?? this.colorGrading,
      audioProperties: audioProperties ?? this.audioProperties,
      strokes: strokes ?? this.strokes,
      trackingData: trackingData ?? this.trackingData,
      waveform: waveform ?? this.waveform,
      thumbnails: thumbnails ?? this.thumbnails,
    );
  }
}

class Project {
  Project({
    required this.id,
    required String name,
    String? projectName,
    this.aspectRatio = AspectRatioPreset.nineSixteen,
    this.resolution = ExportResolution.res1080p,
    List<TimelineClip>? clips,
    List<CaptionCue>? captions,
    List<String>? customFonts,
    String? thumbnail,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : name = projectName ?? name,
        clips = clips ?? <TimelineClip>[],
        captions = captions ?? <CaptionCue>[],
        customFonts = customFonts ??
            <String>[
              'Roboto',
              'Montserrat',
              'Poppins',
              'Playfair Display',
              'Bebas Neue',
              'Caveat'
            ],
        thumbnail = thumbnail ?? 'assets/placeholder.png',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  String get projectName => name;
  final AspectRatioPreset aspectRatio;
  final ExportResolution resolution;
  final List<TimelineClip> clips;
  final List<CaptionCue> captions;
  final List<String> customFonts;
  final String thumbnail;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get duration => totalDuration;

  Duration get totalDuration {
    if (clips.isEmpty && captions.isEmpty) return Duration.zero;

    Duration maxEnd = Duration.zero;
    for (final clip in clips) {
      if (clip.end > maxEnd) maxEnd = clip.end;
    }
    for (final caption in captions) {
      if (caption.end > maxEnd) maxEnd = caption.end;
    }
    return maxEnd;
  }

  void addClip(TimelineClip clip) {
    clips.add(clip);
  }

  void removeClip(String id) {
    clips.removeWhere((TimelineClip clip) => clip.id == id);
  }

  Project copyWith({
    String? id,
    String? name,
    AspectRatioPreset? aspectRatio,
    ExportResolution? resolution,
    List<TimelineClip>? clips,
    List<CaptionCue>? captions,
    List<String>? customFonts,
    String? thumbnail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      resolution: resolution ?? this.resolution,
      clips: clips != null ? List<TimelineClip>.from(clips) : List<TimelineClip>.from(this.clips),
      captions: captions != null ? List<CaptionCue>.from(captions) : List<CaptionCue>.from(this.captions),
      customFonts: customFonts != null ? List<String>.from(customFonts) : List<String>.from(this.customFonts),
      thumbnail: thumbnail ?? this.thumbnail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

typedef VideoProject = Project;

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

  static String formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (value.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }
}
