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
  element,
  camera,
  overlay,
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
  glow,
  retro,
  matrix,
  flame,
}

enum TextAnimationStyle {
  none,
  fadeIn,
  typewriter,
  slideUp,
  bounce,
  scaleUp,
}

enum ClipAnimation {
  none,
  fadeIn,
  fadeOut,
  slideLeft,
  slideRight,
  zoomIn,
  zoomOut,
  bounce,
  spin,
  glitch,
}

enum TransitionType {
  none,
  fade,
  dissolve,
  slide,
  zoom,
}

class ClipTransition {
  const ClipTransition({
    this.type = TransitionType.none,
    this.duration = const Duration(milliseconds: 500),
  });

  final TransitionType type;
  final Duration duration;

  ClipTransition copyWith({
    TransitionType? type,
    Duration? duration,
  }) {
    return ClipTransition(
      type: type ?? this.type,
      duration: duration ?? this.duration,
    );
  }
}

enum ElementShape {
  rectangle,
  circle,
  star,
  triangle,
  arrow,
  line,
}

enum MaskType {
  none,
  rectangle,
  circle,
  linear,
  mirror,
  star,
}

enum KeyframeProperty {
  positionX,
  positionY,
  scale,
  rotation,
  opacity,
  volume,
}

enum CurveType {
  linear,
  easeIn,
  easeOut,
  cubicBezier,
}

class Keyframe {
  const Keyframe({
    required this.id,
    required this.time,
    required this.property,
    required this.value,
    this.curveType = CurveType.linear,
  });

  final String id;
  final Duration time;
  final KeyframeProperty property;
  final double value;
  final CurveType curveType;

  Keyframe copyWith({
    String? id,
    Duration? time,
    KeyframeProperty? property,
    double? value,
    CurveType? curveType,
  }) {
    return Keyframe(
      id: id ?? this.id,
      time: time ?? this.time,
      property: property ?? this.property,
      value: value ?? this.value,
      curveType: curveType ?? this.curveType,
    );
  }
}

class ElementProperties {
  const ElementProperties({
    this.shape = ElementShape.rectangle,
    this.fillColor = Colors.white,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 2.0,
    this.size = 100.0,
  });

  final ElementShape shape;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double size;

  ElementProperties copyWith({
    ElementShape? shape,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    double? size,
  }) {
    return ElementProperties(
      shape: shape ?? this.shape,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      size: size ?? this.size,
    );
  }
}

class CameraProperties {
  const CameraProperties({
    this.fov = 60.0,
    this.focalLength = 35.0,
    this.iso = 400,
    this.shutterSpeed = 0.02,
    this.aperture = 2.8,
    this.whiteBalance = 5600,
    this.zoom = 1.0,
    this.pan = 0.0,
    this.tilt = 0.0,
    this.roll = 0.0,
    this.positionZ = 0.0,
  });

  final double fov;
  final double focalLength;
  final int iso;
  final double shutterSpeed;
  final double aperture;
  final int whiteBalance;
  final double zoom;
  final double pan;
  final double tilt;
  final double roll;
  final double positionZ;

  CameraProperties copyWith({
    double? fov,
    double? focalLength,
    int? iso,
    double? shutterSpeed,
    double? aperture,
    int? whiteBalance,
    double? zoom,
    double? pan,
    double? tilt,
    double? roll,
    double? positionZ,
  }) {
    return CameraProperties(
      fov: fov ?? this.fov,
      focalLength: focalLength ?? this.focalLength,
      iso: iso ?? this.iso,
      shutterSpeed: shutterSpeed ?? this.shutterSpeed,
      aperture: aperture ?? this.aperture,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      zoom: zoom ?? this.zoom,
      pan: pan ?? this.pan,
      tilt: tilt ?? this.tilt,
      roll: roll ?? this.roll,
      positionZ: positionZ ?? this.positionZ,
    );
  }
}

class MaskProperties {
  const MaskProperties({
    this.type = MaskType.none,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.width = 100.0,
    this.height = 100.0,
    this.rotation = 0.0,
    this.feather = 0.0,
    this.isInverted = false,
  });

  final MaskType type;
  final double positionX;
  final double positionY;
  final double width;
  final double height;
  final double rotation;
  final double feather;
  final bool isInverted;

  MaskProperties copyWith({
    MaskType? type,
    double? positionX,
    double? positionY,
    double? width,
    double? height,
    double? rotation,
    double? feather,
    bool? isInverted,
  }) {
    return MaskProperties(
      type: type ?? this.type,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      feather: feather ?? this.feather,
      isInverted: isInverted ?? this.isInverted,
    );
  }
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
    this.noiseReduction = 0.0,
    this.voiceEffect = 'Normal',
  });

  final double volume;
  final double speed;
  final double pitch;
  final Duration fadeIn;
  final Duration fadeOut;
  final String equalizerPreset;
  final double noiseReduction;
  final String voiceEffect;

  AudioProperties copyWith({
    double? volume,
    double? speed,
    double? pitch,
    Duration? fadeIn,
    Duration? fadeOut,
    String? equalizerPreset,
    double? noiseReduction,
    String? voiceEffect,
  }) {
    return AudioProperties(
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      voiceEffect: voiceEffect ?? this.voiceEffect,
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
    this.trimStart = Duration.zero,
    this.trimEnd = Duration.zero,
    this.sourceDuration = const Duration(seconds: 1000),
    this.speed = 1.0,
    this.volume = 1.0,
    this.opacity = 1.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.effect = VideoEffect.none,
    this.sourcePath,
    this.stickerAssetPath,
    this.fontFamily = 'Poppins',
    this.textAnimationStyle = TextAnimationStyle.none,
    this.colorGrading = const ColorGradingSettings(),
    this.audioProperties = const AudioProperties(),
    this.elementProperties = const ElementProperties(),
    this.cameraProperties = const CameraProperties(),
    this.maskProperties = const MaskProperties(),
    this.keyframes = const <Keyframe>[],
    this.inAnimation = ClipAnimation.none,
    this.outAnimation = ClipAnimation.none,
    this.loopAnimation = ClipAnimation.none,
    this.transition = const ClipTransition(),
    this.isReversed = false,
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
  final Duration trimStart;
  final Duration trimEnd;
  final Duration sourceDuration;
  final double speed;
  final double volume;
  final double opacity;
  final double scale;
  final double rotation;
  final double positionX;
  final double positionY;
  final double anchorX;
  final double anchorY;
  final VideoEffect effect;
  final String? sourcePath;
  final String? stickerAssetPath;
  final String fontFamily;
  final TextAnimationStyle textAnimationStyle;
  final ColorGradingSettings colorGrading;
  final AudioProperties audioProperties;
  final ElementProperties elementProperties;
  final CameraProperties cameraProperties;
  final MaskProperties maskProperties;
  final List<Keyframe> keyframes;
  final ClipAnimation inAnimation;
  final ClipAnimation outAnimation;
  final ClipAnimation loopAnimation;
  final ClipTransition transition;
  final bool isReversed;
  final List<DrawingStroke> strokes;
  final TrackingData trackingData;
  final List<double>? waveform;
  final List<String>? thumbnails;

  Duration get trimIn => trimStart;
  Duration get trimOut => trimEnd;

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
    Duration? trimStart,
    Duration? trimEnd,
    Duration? sourceDuration,
    double? speed,
    double? volume,
    double? opacity,
    double? scale,
    double? rotation,
    double? positionX,
    double? positionY,
    double? anchorX,
    double? anchorY,
    VideoEffect? effect,
    String? sourcePath,
    String? stickerAssetPath,
    String? fontFamily,
    TextAnimationStyle? textAnimationStyle,
    ColorGradingSettings? colorGrading,
    AudioProperties? audioProperties,
    ElementProperties? elementProperties,
    CameraProperties? cameraProperties,
    MaskProperties? maskProperties,
    List<Keyframe>? keyframes,
    ClipAnimation? inAnimation,
    ClipAnimation? outAnimation,
    ClipAnimation? loopAnimation,
    ClipTransition? transition,
    bool? isReversed,
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
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      effect: effect ?? this.effect,
      sourcePath: sourcePath ?? this.sourcePath,
      stickerAssetPath: stickerAssetPath ?? this.stickerAssetPath,
      fontFamily: fontFamily ?? this.fontFamily,
      textAnimationStyle: textAnimationStyle ?? this.textAnimationStyle,
      colorGrading: colorGrading ?? this.colorGrading,
      audioProperties: audioProperties ?? this.audioProperties,
      elementProperties: elementProperties ?? this.elementProperties,
      cameraProperties: cameraProperties ?? this.cameraProperties,
      maskProperties: maskProperties ?? this.maskProperties,
      keyframes: keyframes ?? this.keyframes,
      inAnimation: inAnimation ?? this.inAnimation,
      outAnimation: outAnimation ?? this.outAnimation,
      loopAnimation: loopAnimation ?? this.loopAnimation,
      transition: transition ?? this.transition,
      isReversed: isReversed ?? this.isReversed,
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
    this.fps = 30,
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
  final int fps;
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
    int? fps,
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
      fps: fps ?? this.fps,
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
