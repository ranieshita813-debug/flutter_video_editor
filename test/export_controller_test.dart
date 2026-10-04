import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimelineDto Unit Tests', () {
    test('Serializes Project and TimelineClip to versioned JSON', () {
      final project = Project(
        id: 'p1',
        name: 'Test Project',
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c1',
            label: 'Video Clip 1',
            start: Duration.zero,
            end: const Duration(seconds: 5),
            clipType: ClipType.video,
            sourcePath: '/path/to/video.mp4',
            volume: 0.8,
            speed: 1.2,
          ),
        ],
      );

      const settings = ExportSettings(
        resolution: ExportResolution.res1080p,
        fps: 30,
        quality: ExportQuality.high,
        format: ExportFormat.mp4,
        codec: 'h264',
      );

      final dto = TimelineDto.fromProject(project, settings);
      final json = dto.toJson();

      expect(json['version'], equals(1));
      expect(json['projectName'], equals('Test Project'));
      expect(json['durationMs'], equals(5000));
      expect(json['settings']['width'], equals(1920));
      expect(json['settings']['height'], equals(1080));
      expect(json['settings']['codec'], equals('h264'));

      final clipsJson = json['clips'] as List<dynamic>;
      expect(clipsJson.length, equals(1));

      final c1 = clipsJson[0] as Map<String, dynamic>;
      expect(c1['id'], equals('c1'));
      expect(c1['clipType'], equals('video'));
      expect(c1['sourcePath'], equals('/path/to/video.mp4'));
      expect(c1['volume'], equals(0.8));
      expect(c1['speed'], equals(1.2));

      // Roundtrip verification
      final reconstructed = TimelineDto.fromJson(json);
      expect(reconstructed.version, equals(1));
      expect(reconstructed.clips.length, equals(1));
      expect(reconstructed.clips.first.id, equals('c1'));
    });
  });

  group('ExportController Unit Tests', () {
    test('Initial status is idle and can start and complete export', () async {
      final controller = ExportController();
      expect(controller.status, equals(ExportStatus.idle));
      expect(controller.isExporting, isFalse);

      final project = Project(
        id: 'p2',
        name: 'Export Test',
        clips: <TimelineClip>[],
      );

      final future = controller.startExport(project);
      expect(controller.isExporting, isTrue);

      final path = await future;
      expect(path, isNotNull);
      expect(controller.status, equals(ExportStatus.done));
      expect(controller.progress, equals(1.0));

      controller.dispose();
    });
  });
}
