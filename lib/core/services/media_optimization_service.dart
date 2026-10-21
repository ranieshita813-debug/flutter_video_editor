import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

/// Progress information emitted during media import optimization.
class OptimizationProgress {
  const OptimizationProgress({
    required this.currentIndex,
    required this.totalCount,
    required this.fileName,
    required this.message,
    required this.progress,
  });

  final int currentIndex;
  final int totalCount;
  final String fileName;
  final String message;
  final double progress; // 0.0 to 1.0
}

/// Metadata and cached assets generated during media optimization.
class OptimizedMediaItem {
  const OptimizedMediaItem({
    required this.originalPath,
    this.durationMs,
    this.width,
    this.height,
    this.waveform,
    this.thumbnailBytes,
    this.isOptimized = true,
  });

  final String originalPath;
  final int? durationMs;
  final int? width;
  final int? height;
  final List<double>? waveform;
  final Uint8List? thumbnailBytes;
  final bool isOptimized;
}

/// Handles post-import media optimization (probing metadata, pre-generating
/// waveform caches, and frame index caching) to ensure smooth editing playback.
class MediaOptimizationService {
  MediaOptimizationService({ExportService? exportService})
      : _exportService = exportService ?? ExportService();

  final ExportService _exportService;

  /// Optimizes a list of media file paths and reports granular progress via [onProgress].
  Future<List<OptimizedMediaItem>> optimizeMedia(
    List<String> filePaths, {
    void Function(OptimizationProgress)? onProgress,
  }) async {
    final results = <OptimizedMediaItem>[];
    final total = filePaths.length;
    if (total == 0) return results;

    for (int i = 0; i < total; i++) {
      final path = filePaths[i];
      final fileName = path.split(RegExp(r'[\\/]')).last;

      void report(double fileStepProgress, String stageMessage) {
        final overallProgress = (i + fileStepProgress) / total;
        onProgress?.call(OptimizationProgress(
          currentIndex: i + 1,
          totalCount: total,
          fileName: fileName,
          message: stageMessage,
          progress: overallProgress.clamp(0.0, 1.0),
        ));
      }

      report(0.1, 'Analyzing media format…');
      int? durationMs;
      int? width;
      int? height;
      try {
        final meta = await _exportService.probe(path);
        durationMs = (meta['durationMs'] as num?)?.toInt();
        width = (meta['width'] as num?)?.toInt();
        height = (meta['height'] as num?)?.toInt();
      } catch (e) {
        AppLogger.warning('Media probe skipped for $path: $e', tag: 'MediaOptimizationService');
      }

      report(0.4, 'Pre-calculating audio waveform…');
      List<double>? waveform;
      final lower = path.toLowerCase();
      final isAudioOrVideo = lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.m4v') ||
          lower.endsWith('.3gp') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.flac') ||
          lower.endsWith('.ogg');

      if (isAudioOrVideo) {
        try {
          waveform = await _exportService.waveform(path, 60);
        } catch (e) {
          AppLogger.warning('Waveform cache generation skipped for $path: $e', tag: 'MediaOptimizationService');
        }
      }

      report(0.7, 'Generating video frame cache…');
      Uint8List? thumbnailBytes;
      final isAudioOnly = lower.endsWith('.mp3') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.flac') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.ogg');

      if (isAudioOrVideo && !isAudioOnly) {
        try {
          thumbnailBytes = await _exportService.frameAt(path, 0, maxHeight: 180, quality: 85);
        } catch (e) {
          AppLogger.warning('Frame cache generation skipped for $path: $e', tag: 'MediaOptimizationService');
        }
      }

      report(1.0, 'Optimization complete');

      results.add(OptimizedMediaItem(
        originalPath: path,
        durationMs: durationMs,
        width: width,
        height: height,
        waveform: waveform,
        thumbnailBytes: thumbnailBytes,
        isOptimized: true,
      ));
    }

    return results;
  }
}
