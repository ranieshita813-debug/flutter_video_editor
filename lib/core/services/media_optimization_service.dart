import 'dart:async';
import 'package:flutter/foundation.dart';
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

/// Metadata and cached assets generated during media import.
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

/// Handles fast metadata probing during media import.
class MediaOptimizationService {
  MediaOptimizationService({ExportService? exportService})
      : _exportService = exportService ?? ExportService();

  final ExportService _exportService;

  /// Quickly probes basic metadata for media items without heavy background processing.
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

      onProgress?.call(OptimizationProgress(
        currentIndex: i + 1,
        totalCount: total,
        fileName: fileName,
        message: 'Importing media…',
        progress: (i + 1) / total,
      ));

      int? durationMs;
      int? width;
      int? height;
      try {
        final meta = await _exportService.probe(path);
        durationMs = (meta['durationMs'] as num?)?.toInt();
        width = (meta['width'] as num?)?.toInt();
        height = (meta['height'] as num?)?.toInt();
      } catch (_) {}

      results.add(OptimizedMediaItem(
        originalPath: path,
        durationMs: durationMs,
        width: width,
        height: height,
        isOptimized: true,
      ));
    }

    return results;
  }
}
