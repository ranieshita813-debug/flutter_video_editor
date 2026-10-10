import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';

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
  vhs,
  wave,
  vignette,
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timeMs': time.inMilliseconds,
      'property': property.name,
      'value': value,
      'curveType': curveType.name,
    };
  }

  factory Keyframe.fromJson(Map<String, dynamic> json) {
    return Keyframe(
      id: json['id'] as String? ?? '',
      time: Duration(milliseconds: json['timeMs'] as int? ?? 0),
      property: KeyframeProperty.values.firstWhere(
        (e) => e.name == json['property'],
        orElse: () => KeyframeProperty.positionX,
      ),
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      curveType: CurveType.values.firstWhere(
        (e) => e.name == json['curveType'],
        orElse: () => CurveType.linear,
      ),
    );
  }
}

class TextStyleProperties {
  const TextStyleProperties({
    this.fontSize = 28.0,
    this.lineHeight = 1.2,
    this.textColor = Colors.white,
    this.textEffect = 'none',
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0.0,
    this.shadowColor = Colors.transparent,
    this.shadowBlurRadius = 0.0,
    this.shadowOffsetX = 0.0,
    this.shadowOffsetY = 0.0,
    this.backgroundColor = Colors.transparent,
    this.backgroundPadding = 8.0,
    this.textAlign = TextAlign.center,
  });

  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final String textEffect; // 'none', 'outline', 'shadow', 'glow', 'neon', '3d'
  final Color strokeColor;
  final double strokeWidth;
  final Color shadowColor;
  final double shadowBlurRadius;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final Color backgroundColor;
  final double backgroundPadding;
  final TextAlign textAlign;

  TextStyleProperties copyWith({
    double? fontSize,
    double? lineHeight,
    Color? textColor,
    String? textEffect,
    Color? strokeColor,
    double? strokeWidth,
    Color? shadowColor,
    double? shadowBlurRadius,
    double? shadowOffsetX,
    double? shadowOffsetY,
    Color? backgroundColor,
    double? backgroundPadding,
    TextAlign? textAlign,
  }) {
    return TextStyleProperties(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      textColor: textColor ?? this.textColor,
      textEffect: textEffect ?? this.textEffect,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      textAlign: textAlign ?? this.textAlign,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'textColor': textColor.toARGB32(),
      'textEffect': textEffect,
      'strokeColor': strokeColor.toARGB32(),
      'strokeWidth': strokeWidth,
      'shadowColor': shadowColor.toARGB32(),
      'shadowBlurRadius': shadowBlurRadius,
      'shadowOffsetX': shadowOffsetX,
      'shadowOffsetY': shadowOffsetY,
      'backgroundColor': backgroundColor.toARGB32(),
      'backgroundPadding': backgroundPadding,
      'textAlign': textAlign.name,
    };
  }

  factory TextStyleProperties.fromJson(Map<String, dynamic> json) {
    return TextStyleProperties(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 28.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      textColor: Color(json['textColor'] as int? ?? 0xFFFFFFFF),
      textEffect: json['textEffect'] as String? ?? 'none',
      strokeColor: Color(json['strokeColor'] as int? ?? 0x00000000),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.0,
      shadowColor: Color(json['shadowColor'] as int? ?? 0x00000000),
      shadowBlurRadius: (json['shadowBlurRadius'] as num?)?.toDouble() ?? 0.0,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 0.0,
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0x00000000),
      backgroundPadding: (json['backgroundPadding'] as num?)?.toDouble() ?? 8.0,
      textAlign: TextAlign.values.firstWhere(
        (e) => e.name == json['textAlign'],
        orElse: () => TextAlign.center,
      ),
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
    this.svgPath,
  });

  final ElementShape shape;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double size;
  final String? svgPath;

  ElementProperties copyWith({
    ElementShape? shape,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    double? size,
    String? svgPath,
  }) {
    return ElementProperties(
      shape: shape ?? this.shape,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      size: size ?? this.size,
      svgPath: svgPath ?? this.svgPath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'shape': shape.name,
      'fillColor': fillColor.toARGB32(),
      'strokeColor': strokeColor.toARGB32(),
      'strokeWidth': strokeWidth,
      'size': size,
      'svgPath': svgPath,
    };
  }

  factory ElementProperties.fromJson(Map<String, dynamic> json) {
    return ElementProperties(
      shape: ElementShape.values.firstWhere(
        (e) => e.name == json['shape'],
        orElse: () => ElementShape.rectangle,
      ),
      fillColor: Color(json['fillColor'] as int? ?? 0xFFFFFFFF),
      strokeColor: Color(json['strokeColor'] as int? ?? 0x00000000),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      size: (json['size'] as num?)?.toDouble() ?? 100.0,
      svgPath: json['svgPath'] as String?,
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fov': fov,
      'focalLength': focalLength,
      'iso': iso,
      'shutterSpeed': shutterSpeed,
      'aperture': aperture,
      'whiteBalance': whiteBalance,
      'zoom': zoom,
      'pan': pan,
      'tilt': tilt,
      'roll': roll,
      'positionZ': positionZ,
    };
  }

  factory CameraProperties.fromJson(Map<String, dynamic> json) {
    return CameraProperties(
      fov: (json['fov'] as num?)?.toDouble() ?? 60.0,
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 35.0,
      iso: json['iso'] as int? ?? 400,
      shutterSpeed: (json['shutterSpeed'] as num?)?.toDouble() ?? 0.02,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 2.8,
      whiteBalance: json['whiteBalance'] as int? ?? 5600,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      tilt: (json['tilt'] as num?)?.toDouble() ?? 0.0,
      roll: (json['roll'] as num?)?.toDouble() ?? 0.0,
      positionZ: (json['positionZ'] as num?)?.toDouble() ?? 0.0,
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'positionX': positionX,
      'positionY': positionY,
      'width': width,
      'height': height,
      'rotation': rotation,
      'feather': feather,
      'isInverted': isInverted,
    };
  }

  factory MaskProperties.fromJson(Map<String, dynamic> json) {
    return MaskProperties(
      type: MaskType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MaskType.none,
      ),
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 100.0,
      height: (json['height'] as num?)?.toDouble() ?? 100.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.0,
      isInverted: json['isInverted'] as bool? ?? false,
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'color': color.toARGB32(),
      'strokeWidth': strokeWidth,
      'points': points.map((p) => <String, double>{'x': p.dx, 'y': p.dy}).toList(),
    };
  }

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List<dynamic>?)?.map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
        }).toList() ??
        <Offset>[];
    return DrawingStroke(
      id: json['id'] as String? ?? '',
      color: Color(json['color'] as int? ?? 0xFFFFFFFF),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 4.0,
      points: pts,
    );
  }
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'temperature': temperature,
      'tint': tint,
      'exposure': exposure,
      'vignette': vignette,
    };
  }

  factory ColorGradingSettings.fromJson(Map<String, dynamic> json) {
    return ColorGradingSettings(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'volume': volume,
      'speed': speed,
      'pitch': pitch,
      'fadeInMs': fadeIn.inMilliseconds,
      'fadeOutMs': fadeOut.inMilliseconds,
      'equalizerPreset': equalizerPreset,
      'noiseReduction': noiseReduction,
      'voiceEffect': voiceEffect,
    };
  }

  factory AudioProperties.fromJson(Map<String, dynamic> json) {
    return AudioProperties(
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
      fadeIn: Duration(milliseconds: json['fadeInMs'] as int? ?? 0),
      fadeOut: Duration(milliseconds: json['fadeOutMs'] as int? ?? 0),
      equalizerPreset: json['equalizerPreset'] as String? ?? 'Flat',
      noiseReduction: (json['noiseReduction'] as num?)?.toDouble() ?? 0.0,
      voiceEffect: json['voiceEffect'] as String? ?? 'Normal',
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
      'text': text,
    };
  }

  factory CaptionCue.fromJson(Map<String, dynamic> json) {
    return CaptionCue(
      id: json['id'] as String? ?? '',
      start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
      text: json['text'] as String? ?? '',
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isEnabled': isEnabled,
      'targetName': targetName,
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
      'smoothness': smoothness,
    };
  }

  factory TrackingData.fromJson(Map<String, dynamic> json) {
    return TrackingData(
      isEnabled: json['isEnabled'] as bool? ?? false,
      targetName: json['targetName'] as String? ?? 'Face',
      rect: Rect.fromLTWH(
        (json['left'] as num?)?.toDouble() ?? 0.3,
        (json['top'] as num?)?.toDouble() ?? 0.3,
        (json['width'] as num?)?.toDouble() ?? 0.4,
        (json['height'] as num?)?.toDouble() ?? 0.4,
      ),
      smoothness: (json['smoothness'] as num?)?.toDouble() ?? 0.8,
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
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.effect = VideoEffect.none,
    this.sourcePath,
    this.stickerAssetPath,
    this.fontFamily = 'Poppins',
    this.textAnimationStyle = TextAnimationStyle.none,
    this.textStyle = const TextStyleProperties(),
    this.colorGrading = const ColorGradingSettings(),
    this.chromaKey = const ChromaKey(),
    this.audioProperties = const AudioProperties(),
    this.elementProperties = const ElementProperties(),
    this.cameraProperties = const CameraProperties(),
    this.maskProperties = const MaskProperties(),
    this.keyframes = const <Keyframe>[],
    this.shaderEffects = const <ShaderEffectClip>[],
    this.inAnimation = ClipAnimation.none,
    this.outAnimation = ClipAnimation.none,
    this.loopAnimation = ClipAnimation.none,
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
  final double anchorX;
  final double anchorY;
  final VideoEffect effect;
  final String? sourcePath;
  final String? stickerAssetPath;
  final String fontFamily;
  final TextAnimationStyle textAnimationStyle;
  final TextStyleProperties textStyle;
  final ColorGradingSettings colorGrading;
  final ChromaKey chromaKey;
  final AudioProperties audioProperties;
  final ElementProperties elementProperties;
  final CameraProperties cameraProperties;
  final MaskProperties maskProperties;
  final List<Keyframe> keyframes;
  final List<ShaderEffectClip> shaderEffects;
  final ClipAnimation inAnimation;
  final ClipAnimation outAnimation;
  final ClipAnimation loopAnimation;
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
    double? anchorX,
    double? anchorY,
    VideoEffect? effect,
    String? sourcePath,
    String? stickerAssetPath,
    String? fontFamily,
    TextAnimationStyle? textAnimationStyle,
    TextStyleProperties? textStyle,
    ColorGradingSettings? colorGrading,
    ChromaKey? chromaKey,
    AudioProperties? audioProperties,
    ElementProperties? elementProperties,
    CameraProperties? cameraProperties,
    MaskProperties? maskProperties,
    List<Keyframe>? keyframes,
    List<ShaderEffectClip>? shaderEffects,
    ClipAnimation? inAnimation,
    ClipAnimation? outAnimation,
    ClipAnimation? loopAnimation,
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
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      effect: effect ?? this.effect,
      sourcePath: sourcePath ?? this.sourcePath,
      stickerAssetPath: stickerAssetPath ?? this.stickerAssetPath,
      fontFamily: fontFamily ?? this.fontFamily,
      textAnimationStyle: textAnimationStyle ?? this.textAnimationStyle,
      textStyle: textStyle ?? this.textStyle,
      colorGrading: colorGrading ?? this.colorGrading,
      chromaKey: chromaKey ?? this.chromaKey,
      audioProperties: audioProperties ?? this.audioProperties,
      elementProperties: elementProperties ?? this.elementProperties,
      cameraProperties: cameraProperties ?? this.cameraProperties,
      maskProperties: maskProperties ?? this.maskProperties,
      keyframes: keyframes ?? this.keyframes,
      shaderEffects: shaderEffects ?? this.shaderEffects,
      inAnimation: inAnimation ?? this.inAnimation,
      outAnimation: outAnimation ?? this.outAnimation,
      loopAnimation: loopAnimation ?? this.loopAnimation,
      strokes: strokes ?? this.strokes,
      trackingData: trackingData ?? this.trackingData,
      waveform: waveform ?? this.waveform,
      thumbnails: thumbnails ?? this.thumbnails,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
      'clipType': clipType.name,
      'layerIndex': layerIndex,
      'isVisible': isVisible,
      'isLocked': isLocked,
      'trimInMs': trimIn.inMilliseconds,
      'trimOutMs': trimOut.inMilliseconds,
      'speed': speed,
      'volume': volume,
      'opacity': opacity,
      'scale': scale,
      'rotation': rotation,
      'positionX': positionX,
      'positionY': positionY,
      'anchorX': anchorX,
      'anchorY': anchorY,
      'effect': effect.name,
      'sourcePath': sourcePath,
      'stickerAssetPath': stickerAssetPath,
      'fontFamily': fontFamily,
      'textAnimationStyle': textAnimationStyle.name,
      'textStyle': textStyle.toJson(),
      'colorGrading': colorGrading.toJson(),
      'chromaKey': chromaKey.toJson(),
      'audioProperties': audioProperties.toJson(),
      'elementProperties': elementProperties.toJson(),
      'cameraProperties': cameraProperties.toJson(),
      'maskProperties': maskProperties.toJson(),
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
      'shaderEffects': shaderEffects.map((e) => e.toJson()).toList(),
      'inAnimation': inAnimation.name,
      'outAnimation': outAnimation.name,
      'loopAnimation': loopAnimation.name,
      'strokes': strokes.map((s) => s.toJson()).toList(),
      'trackingData': trackingData.toJson(),
      'waveform': waveform,
      'thumbnails': thumbnails,
    };
  }

  factory TimelineClip.fromJson(Map<String, dynamic> json) {
    return TimelineClip(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
      clipType: ClipType.values.firstWhere(
        (e) => e.name == json['clipType'],
        orElse: () => ClipType.video,
      ),
      layerIndex: json['layerIndex'] as int? ?? 0,
      isVisible: json['isVisible'] as bool? ?? true,
      isLocked: json['isLocked'] as bool? ?? false,
      trimIn: Duration(milliseconds: json['trimInMs'] as int? ?? 0),
      trimOut: Duration(milliseconds: json['trimOutMs'] as int? ?? 0),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.5,
      anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.5,
      effect: VideoEffect.values.firstWhere(
        (e) => e.name == json['effect'],
        orElse: () => VideoEffect.none,
      ),
      sourcePath: json['sourcePath'] as String?,
      stickerAssetPath: json['stickerAssetPath'] as String?,
      fontFamily: json['fontFamily'] as String? ?? 'Poppins',
      textAnimationStyle: TextAnimationStyle.values.firstWhere(
        (e) => e.name == json['textAnimationStyle'],
        orElse: () => TextAnimationStyle.none,
      ),
      textStyle: json['textStyle'] != null
          ? TextStyleProperties.fromJson(Map<String, dynamic>.from(json['textStyle'] as Map))
          : const TextStyleProperties(),
      colorGrading: json['colorGrading'] != null
          ? ColorGradingSettings.fromJson(Map<String, dynamic>.from(json['colorGrading'] as Map))
          : const ColorGradingSettings(),
      chromaKey: json['chromaKey'] != null
          ? ChromaKey.fromJson(Map<String, dynamic>.from(json['chromaKey'] as Map))
          : const ChromaKey(),
      audioProperties: json['audioProperties'] != null
          ? AudioProperties.fromJson(Map<String, dynamic>.from(json['audioProperties'] as Map))
          : const AudioProperties(),
      elementProperties: json['elementProperties'] != null
          ? ElementProperties.fromJson(Map<String, dynamic>.from(json['elementProperties'] as Map))
          : const ElementProperties(),
      cameraProperties: json['cameraProperties'] != null
          ? CameraProperties.fromJson(Map<String, dynamic>.from(json['cameraProperties'] as Map))
          : const CameraProperties(),
      maskProperties: json['maskProperties'] != null
          ? MaskProperties.fromJson(Map<String, dynamic>.from(json['maskProperties'] as Map))
          : const MaskProperties(),
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((e) => Keyframe.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <Keyframe>[],
      shaderEffects: (json['shaderEffects'] as List<dynamic>?)
              ?.map((e) => ShaderEffectClip.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <ShaderEffectClip>[],
      inAnimation: ClipAnimation.values.firstWhere(
        (e) => e.name == json['inAnimation'],
        orElse: () => ClipAnimation.none,
      ),
      outAnimation: ClipAnimation.values.firstWhere(
        (e) => e.name == json['outAnimation'],
        orElse: () => ClipAnimation.none,
      ),
      loopAnimation: ClipAnimation.values.firstWhere(
        (e) => e.name == json['loopAnimation'],
        orElse: () => ClipAnimation.none,
      ),
      strokes: (json['strokes'] as List<dynamic>?)
              ?.map((e) => DrawingStroke.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <DrawingStroke>[],
      trackingData: json['trackingData'] != null
          ? TrackingData.fromJson(Map<String, dynamic>.from(json['trackingData'] as Map))
          : const TrackingData(),
      waveform: (json['waveform'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      thumbnails: (json['thumbnails'] as List<dynamic>?)?.cast<String>(),
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'aspectRatio': aspectRatio.name,
      'resolution': resolution.name,
      'clips': clips.map((c) => c.toJson()).toList(),
      'captions': captions.map((c) => c.toJson()).toList(),
      'customFonts': customFonts,
      'thumbnail': thumbnail,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Project',
      aspectRatio: AspectRatioPreset.values.firstWhere(
        (e) => e.name == json['aspectRatio'],
        orElse: () => AspectRatioPreset.nineSixteen,
      ),
      resolution: ExportResolution.values.firstWhere(
        (e) => e.name == json['resolution'],
        orElse: () => ExportResolution.res1080p,
      ),
      clips: (json['clips'] as List<dynamic>?)
              ?.map((e) => TimelineClip.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <TimelineClip>[],
      captions: (json['captions'] as List<dynamic>?)
              ?.map((e) => CaptionCue.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <CaptionCue>[],
      customFonts: (json['customFonts'] as List<dynamic>?)?.cast<String>(),
      thumbnail: json['thumbnail'] as String? ?? 'assets/placeholder.png',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
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
