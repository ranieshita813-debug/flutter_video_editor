import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('editor/export'), (call) async {
      if (call.method == 'export') {
        return '/tmp/mock_export.mp4';
      }
      return null;
    });
  });

  group('TimelineDto Unit Tests', () {
    test('Serializes Project and TimelineClip to versioned JSON', () {
      final project = Project(
        id: 'p1',
        name: 'Test Project',
        aspectRatio: AspectRatioPreset.sixteenNine,
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

    test('Serializes all clip types including caption words and shader effects', () {
      final project = Project(
        id: 'p_all',
        name: 'All Clips Project',
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c_caption',
            label: 'Bengali Caption',
            start: Duration.zero,
            end: const Duration(seconds: 3),
            clipType: ClipType.caption,
            words: const [
              CaptionWord(word: 'হ্যালো', start: Duration.zero, end: Duration(seconds: 1)),
              CaptionWord(word: 'বিশ্ব', start: Duration(seconds: 1), end: Duration(seconds: 3)),
            ],
          ),
          TimelineClip(
            id: 'c_elem',
            label: 'Star Shape',
            start: Duration.zero,
            end: const Duration(seconds: 5),
            clipType: ClipType.element,
            elementProperties: const ElementProperties(shape: ElementShape.star),
          ),
          TimelineClip(
            id: 'c_audio',
            label: 'Bg Music',
            start: Duration.zero,
            end: const Duration(seconds: 10),
            clipType: ClipType.audio,
            sourcePath: '/path/music.mp3',
          ),
        ],
      );

      final dto = TimelineDto.fromProject(project, const ExportSettings());
      final json = dto.toJson();
      final reconstructed = TimelineDto.fromJson(json);

      expect(reconstructed.clips.length, equals(3));
      final cap = reconstructed.clips.firstWhere((c) => c.id == 'c_caption');
      expect(cap.label, equals('Bengali Caption'));
      expect(cap.words.length, equals(2));
      expect(cap.words.first['word'], equals('হ্যালো'));

      final elem = reconstructed.clips.firstWhere((c) => c.id == 'c_elem');
      expect(elem.elementProperties['shape'], equals('star'));
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
