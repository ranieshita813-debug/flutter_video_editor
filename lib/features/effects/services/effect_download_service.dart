import 'dart:async';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/effects/services/shader_database_service.dart';

class EffectDownloadProgress {
  const EffectDownloadProgress({
    required this.effectId,
    required this.progress, // 0.0 to 1.0
    required this.isCompleted,
    this.error,
  });

  final String effectId;
  final double progress;
  final bool isCompleted;
  final String? error;
}

class EffectDownloadService {
  EffectDownloadService._internal();
  static final EffectDownloadService instance = EffectDownloadService._internal();

  final Map<String, double> _downloadProgressMap = <String, double>{};
  final StreamController<EffectDownloadProgress> _progressController =
      StreamController<EffectDownloadProgress>.broadcast();

  Stream<EffectDownloadProgress> get progressStream => _progressController.stream;

  double getDownloadProgress(String effectId) {
    return _downloadProgressMap[effectId] ?? 0.0;
  }

  bool isDownloading(String effectId) {
    final p = _downloadProgressMap[effectId];
    return p != null && p > 0.0 && p < 1.0;
  }

  Future<ShaderEffect> downloadEffect(ShaderEffect effect, {String? mockShaderCode}) async {
    final id = effect.id;
    AppLogger.info('Starting download for effect: ${effect.name} ($id)',
        tag: 'EffectDownloadService');

    _downloadProgressMap[id] = 0.0;
    _notifyProgress(id, 0.0, false);

    const steps = 10;
    for (int i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final p = i / steps;
      _downloadProgressMap[id] = p;
      _notifyProgress(id, p, false);
    }

    final shaderCode = mockShaderCode ?? _generateDefaultShaderCode(effect);
    final downloadedEffect = await ShaderDatabaseService.instance
        .saveDownloadedEffect(effect, shaderCode);

    _downloadProgressMap.remove(id);
    _notifyProgress(id, 1.0, true);

    AppLogger.info('Successfully downloaded effect: ${effect.name}',
        tag: 'EffectDownloadService');
    return downloadedEffect;
  }

  void _notifyProgress(String effectId, double progress, bool isCompleted, [String? error]) {
    _progressController.add(EffectDownloadProgress(
      effectId: effectId,
      progress: progress,
      isCompleted: isCompleted,
      error: error,
    ));
  }

  String _generateDefaultShaderCode(ShaderEffect effect) {
    return '''
// Shader Code: ${effect.name}
// Category: ${effect.category.displayName}
// Author: ${effect.author}

#version 300 es
precision mediump float;

in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_intensity;

void main() {
    vec4 color = texture(u_texture, v_texCoord);
    // Custom shader effect transformation for ${effect.id}
    fragColor = mix(color, vec4(color.rgb * u_intensity, color.a), 0.5);
}
''';
  }

  void dispose() {
    _progressController.close();
  }
}
