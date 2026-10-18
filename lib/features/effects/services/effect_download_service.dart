import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

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

  String sanitizePath(String input) {
    return input.replaceAll(RegExp(r'\.\.[/\\]'), '').replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
  }

  Future<ShaderEffect> downloadEffect(ShaderEffect effect, {String? mockPresetJson}) async {
    final id = sanitizePath(effect.id);
    AppLogger.info('Starting download for effect preset: ${effect.name} ($id)',
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

    final presetJson = mockPresetJson ?? _generatePresetJson(effect);
    final downloadedEffect = await ShaderDatabaseService.instance
        .saveDownloadedEffect(effect, presetJson);

    _downloadProgressMap.remove(id);
    _notifyProgress(id, 1.0, true);

    AppLogger.info('Successfully downloaded effect preset: ${effect.name}',
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

  String _generatePresetJson(ShaderEffect effect) {
    final Map<String, dynamic> presetMap = <String, dynamic>{
      'id': effect.id,
      'name': effect.name,
      'category': effect.category.name,
      'downloadedAt': DateTime.now().toIso8601String(),
      'parameters': <String, dynamic>{
        for (final p in effect.parameters) p.id: p.value is Color ? (p.value as Color).toARGB32() : p.value,
      },
    };
    return jsonEncode(presetMap);
  }

  void dispose() {
    _progressController.close();
  }
}
