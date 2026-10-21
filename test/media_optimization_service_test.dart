import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/services/media_optimization_service.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

class MockExportService extends ExportService {
  @override
  Future<Map<String, dynamic>> probe(String path) async {
    if (path.contains('error')) {
      throw PlatformException(code: 'PROBE_FAILED', message: 'Failed');
    }
    return {
      'durationMs': 5000,
      'width': 1920,
      'height': 1080,
    };
  }

  @override
  Future<List<double>> waveform(String path, int buckets) async {
    if (path.contains('nowaveform')) {
      throw PlatformException(code: 'WAVEFORM_FAILED', message: 'Failed');
    }
    return List<double>.filled(buckets, 0.5);
  }

  @override
  Future<Uint8List?> frameAt(String path, int timeMs, {int maxHeight = 96, int quality = 80}) async {
    if (path.contains('noframe')) {
      return null;
    }
    return Uint8List.fromList([0, 1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaOptimizationService Unit Tests', () {
    late MediaOptimizationService service;

    setUp(() {
      service = MediaOptimizationService(exportService: MockExportService());
    });

    test('optimizeMedia emits granular progress updates for files', () async {
      final progressUpdates = <OptimizationProgress>[];
      final files = ['sample_video.mp4', 'sample_audio.mp3'];

      final results = await service.optimizeMedia(
        files,
        onProgress: (p) => progressUpdates.add(p),
      );

      expect(results.length, equals(2));
      expect(results[0].originalPath, equals('sample_video.mp4'));
      expect(results[0].durationMs, equals(5000));
      expect(results[0].width, equals(1920));
      expect(results[0].height, equals(1080));
      expect(results[0].waveform, isNotNull);
      expect(results[0].waveform!.length, equals(60));
      expect(results[0].thumbnailBytes, isNotNull);

      expect(results[1].originalPath, equals('sample_audio.mp3'));
      expect(results[1].durationMs, equals(5000));
      expect(results[1].thumbnailBytes, isNull); // Audio files skip video frame caching

      expect(progressUpdates.isNotEmpty, isTrue);
      expect(progressUpdates.first.currentIndex, equals(1));
      expect(progressUpdates.last.progress, equals(1.0));
    });

    test('optimizeMedia handles individual step failures gracefully', () async {
      final files = ['error_nowaveform_noframe.mp4'];

      final results = await service.optimizeMedia(files);

      expect(results.length, equals(1));
      expect(results[0].originalPath, equals('error_nowaveform_noframe.mp4'));
      expect(results[0].durationMs, isNull);
      expect(results[0].waveform, isNull);
      expect(results[0].thumbnailBytes, isNull);
      expect(results[0].isOptimized, isTrue);
    });

    test('optimizeMedia returns empty list for empty input', () async {
      final results = await service.optimizeMedia([]);
      expect(results, isEmpty);
    });
  });
}
