import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/export/models/export_settings.dart';

class TimelineDto {
  TimelineDto({
    required this.version,
    required this.projectName,
    required this.durationMs,
    required this.settings,
    required this.clips,
  });

  final int version;
  final String projectName;
  final int durationMs;
  final ExportSettings settings;
  final List<ClipDto> clips;

  factory TimelineDto.fromProject(Project project, ExportSettings settings) {
    return TimelineDto(
      version: 1,
      projectName: project.projectName,
      durationMs: project.totalDuration.inMilliseconds,
      settings: settings,
      clips: project.clips.map((c) => ClipDto.fromTimelineClip(c)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'projectName': projectName,
      'durationMs': durationMs,
      'settings': settings.toJson(),
      'clips': clips.map((c) => c.toJson()).toList(),
    };
  }

  factory TimelineDto.fromJson(Map<String, dynamic> json) {
    return TimelineDto(
      version: json['version'] as int? ?? 1,
      projectName: json['projectName'] as String? ?? 'Untitled',
      durationMs: json['durationMs'] as int? ?? 0,
      settings: json['settings'] != null
          ? ExportSettings.fromJson(json['settings'] as Map<String, dynamic>)
          : const ExportSettings(),
      clips: (json['clips'] as List<dynamic>?)
              ?.map((e) => ClipDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <ClipDto>[],
    );
  }
}

class ClipDto {
  ClipDto({
    required this.id,
    required this.label,
    required this.clipType,
    required this.sourcePath,
    required this.sourceInMs,
    required this.sourceOutMs,
    required this.timelineStartMs,
    required this.timelineDurationMs,
    required this.layerIndex,
    required this.isVisible,
    required this.volume,
    required this.speed,
    required this.opacity,
    required this.scale,
    required this.rotation,
    required this.positionX,
    required this.positionY,
    required this.colorGrading,
    required this.audioProperties,
    required this.chromaKey,
    required this.fontFamily,
    required this.textAnimationStyle,
    required this.textStyle,
    required this.inAnimation,
    required this.outAnimation,
    required this.strokes,
    required this.stickerAssetPath,
    required this.effect,
    this.svgPath,
  });

  final String id;
  final String label;
  final String clipType;
  final String? sourcePath;
  final int sourceInMs;
  final int sourceOutMs;
  final int timelineStartMs;
  final int timelineDurationMs;
  final int layerIndex;
  final bool isVisible;
  final double volume;
  final double speed;
  final double opacity;
  final double scale;
  final double rotation;
  final double positionX;
  final double positionY;
  final Map<String, dynamic> colorGrading;
  final Map<String, dynamic> audioProperties;
  final Map<String, dynamic> chromaKey;
  final String fontFamily;
  final String textAnimationStyle;
  final Map<String, dynamic> textStyle;
  final String inAnimation;
  final String outAnimation;
  final List<Map<String, dynamic>> strokes;
  final String? stickerAssetPath;
  final String effect;
  final String? svgPath;

  factory ClipDto.fromTimelineClip(TimelineClip clip) {
    return ClipDto(
      id: clip.id,
      label: clip.label,
      clipType: clip.clipType.name,
      sourcePath: clip.sourcePath,
      sourceInMs: clip.trimIn.inMilliseconds,
      sourceOutMs: clip.trimOut.inMilliseconds,
      timelineStartMs: clip.start.inMilliseconds,
      timelineDurationMs: clip.duration.inMilliseconds,
      layerIndex: clip.layerIndex,
      isVisible: clip.isVisible,
      volume: clip.volume,
      speed: clip.speed,
      opacity: clip.opacity,
      scale: clip.scale,
      rotation: clip.rotation,
      positionX: clip.positionX,
      positionY: clip.positionY,
      colorGrading: <String, dynamic>{
        'brightness': clip.colorGrading.brightness,
        'contrast': clip.colorGrading.contrast,
        'saturation': clip.colorGrading.saturation,
        'temperature': clip.colorGrading.temperature,
        'tint': clip.colorGrading.tint,
        'exposure': clip.colorGrading.exposure,
        'vignette': clip.colorGrading.vignette,
      },
      audioProperties: <String, dynamic>{
        'volume': clip.audioProperties.volume,
        'speed': clip.audioProperties.speed,
        'pitch': clip.audioProperties.pitch,
        'fadeInMs': clip.audioProperties.fadeIn.inMilliseconds,
        'fadeOutMs': clip.audioProperties.fadeOut.inMilliseconds,
        'equalizerPreset': clip.audioProperties.equalizerPreset,
      },
      chromaKey: <String, dynamic>{
        'enabled': clip.chromaKey.enabled,
        'keyColor': clip.chromaKey.keyColor.toARGB32(),
        'similarity': clip.chromaKey.similarity,
        'smoothness': clip.chromaKey.smoothness,
        'spill': clip.chromaKey.spill,
        'output': clip.chromaKey.output.name,
      },
      fontFamily: clip.fontFamily,
      textAnimationStyle: clip.textAnimationStyle.name,
      textStyle: <String, dynamic>{
        'fontSize': clip.textStyle.fontSize,
        'lineHeight': clip.textStyle.lineHeight,
        'textColor': clip.textStyle.textColor.toARGB32(),
        'textEffect': clip.textStyle.textEffect,
        'strokeColor': clip.textStyle.strokeColor.toARGB32(),
        'strokeWidth': clip.textStyle.strokeWidth,
        'shadowColor': clip.textStyle.shadowColor.toARGB32(),
        'shadowBlurRadius': clip.textStyle.shadowBlurRadius,
        'shadowOffsetX': clip.textStyle.shadowOffsetX,
        'shadowOffsetY': clip.textStyle.shadowOffsetY,
        'backgroundColor': clip.textStyle.backgroundColor.toARGB32(),
        'backgroundPadding': clip.textStyle.backgroundPadding,
        'textAlign': clip.textStyle.textAlign.name,
      },
      inAnimation: clip.inAnimation.name,
      outAnimation: clip.outAnimation.name,
      strokes: clip.strokes
          .map((stroke) => <String, dynamic>{
                'id': stroke.id,
                'color': stroke.color.toARGB32(),
                'strokeWidth': stroke.strokeWidth,
                'points': stroke.points
                    .map((pt) => <String, double>{
                          'x': pt.dx,
                          'y': pt.dy,
                        })
                    .toList(),
              })
          .toList(),
      stickerAssetPath: clip.stickerAssetPath,
      effect: clip.effect.name,
      svgPath: clip.elementProperties.svgPath ?? clip.sourcePath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'clipType': clipType,
      'sourcePath': sourcePath,
      'sourceInMs': sourceInMs,
      'sourceOutMs': sourceOutMs,
      'timelineStartMs': timelineStartMs,
      'timelineDurationMs': timelineDurationMs,
      'layerIndex': layerIndex,
      'isVisible': isVisible,
      'volume': volume,
      'speed': speed,
      'opacity': opacity,
      'scale': scale,
      'rotation': rotation,
      'positionX': positionX,
      'positionY': positionY,
      'colorGrading': colorGrading,
      'audioProperties': audioProperties,
      'chromaKey': chromaKey,
      'fontFamily': fontFamily,
      'textAnimationStyle': textAnimationStyle,
      'textStyle': textStyle,
      'inAnimation': inAnimation,
      'outAnimation': outAnimation,
      'strokes': strokes,
      'stickerAssetPath': stickerAssetPath,
      'effect': effect,
      'svgPath': svgPath,
    };
  }

  factory ClipDto.fromJson(Map<String, dynamic> json) {
    return ClipDto(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      clipType: json['clipType'] as String? ?? 'video',
      sourcePath: json['sourcePath'] as String?,
      sourceInMs: json['sourceInMs'] as int? ?? 0,
      sourceOutMs: json['sourceOutMs'] as int? ?? 0,
      timelineStartMs: json['timelineStartMs'] as int? ?? 0,
      timelineDurationMs: json['timelineDurationMs'] as int? ?? 0,
      layerIndex: json['layerIndex'] as int? ?? 0,
      isVisible: json['isVisible'] as bool? ?? true,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      colorGrading: json['colorGrading'] as Map<String, dynamic>? ?? <String, dynamic>{},
      audioProperties: json['audioProperties'] as Map<String, dynamic>? ?? <String, dynamic>{},
      chromaKey: json['chromaKey'] as Map<String, dynamic>? ?? <String, dynamic>{},
      fontFamily: json['fontFamily'] as String? ?? 'Poppins',
      textAnimationStyle: json['textAnimationStyle'] as String? ?? 'none',
      textStyle: json['textStyle'] as Map<String, dynamic>? ?? <String, dynamic>{},
      inAnimation: json['inAnimation'] as String? ?? 'none',
      outAnimation: json['outAnimation'] as String? ?? 'none',
      strokes: (json['strokes'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[],
      stickerAssetPath: json['stickerAssetPath'] as String?,
      effect: json['effect'] as String? ?? 'none',
      svgPath: json['svgPath'] as String?,
    );
  }
}
