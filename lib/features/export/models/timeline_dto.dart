import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart' show canvasRatioNotifier;
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
    final effectiveRatio = (project.aspectRatio.ratio > 0)
        ? project.aspectRatio.ratio
        : canvasRatioNotifier.value.value;
    final updatedSettings = settings.copyWith(
      aspectRatioValue: settings.aspectRatioValue ?? effectiveRatio,
    );
    return TimelineDto(
      version: 1,
      projectName: project.projectName,
      durationMs: project.totalDuration.inMilliseconds,
      settings: updatedSettings,
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
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    required this.colorGrading,
    required this.audioProperties,
    required this.chromaKey,
    this.elementProperties = const <String, dynamic>{},
    this.cameraProperties = const <String, dynamic>{},
    this.maskProperties = const <String, dynamic>{},
    this.effectParameters = const <String, double>{},
    required this.fontFamily,
    required this.textAnimationStyle,
    required this.textStyle,
    required this.inAnimation,
    required this.outAnimation,
    this.loopAnimation = 'none',
    this.transitionType = 'none',
    this.transitionDurationMs = 500,
    required this.strokes,
    required this.stickerAssetPath,
    required this.effect,
    this.svgPath,
    this.keyframes = const <Map<String, dynamic>>[],
    this.words = const <Map<String, dynamic>>[],
    this.shaderEffects = const <Map<String, dynamic>>[],
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
  final double anchorX;
  final double anchorY;
  final Map<String, dynamic> colorGrading;
  final Map<String, dynamic> audioProperties;
  final Map<String, dynamic> chromaKey;
  final Map<String, dynamic> elementProperties;
  final Map<String, dynamic> cameraProperties;
  final Map<String, dynamic> maskProperties;
  final Map<String, double> effectParameters;
  final String fontFamily;
  final String textAnimationStyle;
  final Map<String, dynamic> textStyle;
  final String inAnimation;
  final String outAnimation;
  final String loopAnimation;
  final String transitionType;
  final int transitionDurationMs;
  final List<Map<String, dynamic>> strokes;
  final String? stickerAssetPath;
  final String effect;
  final String? svgPath;
  final List<Map<String, dynamic>> keyframes;
  final List<Map<String, dynamic>> words;
  final List<Map<String, dynamic>> shaderEffects;

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
      anchorX: clip.anchorX,
      anchorY: clip.anchorY,
      colorGrading: clip.colorGrading.toJson(),
      audioProperties: clip.audioProperties.toJson(),
      chromaKey: clip.chromaKey.toJson(),
      elementProperties: clip.elementProperties.toJson(),
      cameraProperties: clip.cameraProperties.toJson(),
      maskProperties: clip.maskProperties.toJson(),
      effectParameters: clip.effectParameters,
      fontFamily: clip.fontFamily,
      textAnimationStyle: clip.textAnimationStyle.name,
      textStyle: clip.textStyle.toJson(),
      inAnimation: clip.inAnimation.name,
      outAnimation: clip.outAnimation.name,
      loopAnimation: clip.loopAnimation.name,
      transitionType: clip.transitionType,
      transitionDurationMs: clip.transitionDurationMs,
      strokes: clip.strokes.map((s) => s.toJson()).toList(),
      stickerAssetPath: clip.stickerAssetPath,
      effect: clip.effect.name,
      svgPath: clip.elementProperties.svgPath ?? clip.sourcePath,
      keyframes: clip.keyframes.map((k) => k.toJson()).toList(),
      words: clip.words.map((w) => w.toJson()).toList(),
      shaderEffects: clip.shaderEffects.map((e) => e.toJson()).toList(),
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
      'anchorX': anchorX,
      'anchorY': anchorY,
      'colorGrading': colorGrading,
      'audioProperties': audioProperties,
      'chromaKey': chromaKey,
      'elementProperties': elementProperties,
      'cameraProperties': cameraProperties,
      'maskProperties': maskProperties,
      'effectParameters': effectParameters,
      'fontFamily': fontFamily,
      'textAnimationStyle': textAnimationStyle,
      'textStyle': textStyle,
      'inAnimation': inAnimation,
      'outAnimation': outAnimation,
      'loopAnimation': loopAnimation,
      'transitionType': transitionType,
      'transitionDurationMs': transitionDurationMs,
      'strokes': strokes,
      'stickerAssetPath': stickerAssetPath,
      'effect': effect,
      'svgPath': svgPath,
      'keyframes': keyframes,
      'words': words,
      'shaderEffects': shaderEffects,
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
      anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.5,
      anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.5,
      colorGrading: json['colorGrading'] as Map<String, dynamic>? ?? <String, dynamic>{},
      audioProperties: json['audioProperties'] as Map<String, dynamic>? ?? <String, dynamic>{},
      chromaKey: json['chromaKey'] as Map<String, dynamic>? ?? <String, dynamic>{},
      elementProperties: json['elementProperties'] as Map<String, dynamic>? ?? <String, dynamic>{},
      cameraProperties: json['cameraProperties'] as Map<String, dynamic>? ?? <String, dynamic>{},
      maskProperties: json['maskProperties'] as Map<String, dynamic>? ?? <String, dynamic>{},
      effectParameters: (json['effectParameters'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const <String, double>{},
      fontFamily: json['fontFamily'] as String? ?? 'Ubuntu Sans',
      textAnimationStyle: json['textAnimationStyle'] as String? ?? 'none',
      textStyle: json['textStyle'] as Map<String, dynamic>? ?? <String, dynamic>{},
      inAnimation: json['inAnimation'] as String? ?? 'none',
      outAnimation: json['outAnimation'] as String? ?? 'none',
      loopAnimation: json['loopAnimation'] as String? ?? 'none',
      transitionType: json['transitionType'] as String? ?? 'none',
      transitionDurationMs: json['transitionDurationMs'] as int? ?? 500,
      strokes: (json['strokes'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[],
      stickerAssetPath: json['stickerAssetPath'] as String?,
      effect: json['effect'] as String? ?? 'none',
      svgPath: json['svgPath'] as String?,
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[],
      words: (json['words'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[],
      shaderEffects: (json['shaderEffects'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[],
    );
  }
}
