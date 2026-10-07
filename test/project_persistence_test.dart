import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Project Data Model and Serialization Unit Tests', () {
    test('Project serialization to and from JSON is lossless', () {
      final clip = TimelineClip(
        id: 'c1',
        label: 'Video Clip 1',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        volume: 0.8,
        speed: 1.2,
        textStyle: const TextStyleProperties(
          fontSize: 32,
          textColor: Colors.cyan,
          textAlign: TextAlign.left,
        ),
        colorGrading: const ColorGradingSettings(
          brightness: 0.1,
          contrast: 1.1,
          saturation: 1.2,
        ),
      );

      final project = Project(
        id: 'p1',
        name: 'Test Project',
        aspectRatio: AspectRatioPreset.sixteenNine,
        resolution: ExportResolution.res1080p,
        clips: [clip],
        captions: [
          CaptionCue(
            id: 'cap1',
            start: Duration.zero,
            end: const Duration(seconds: 5),
            text: 'Hello World',
          ),
        ],
      );

      final json = project.toJson();
      final restored = Project.fromJson(json);

      expect(restored.id, equals(project.id));
      expect(restored.name, equals(project.name));
      expect(restored.aspectRatio, equals(project.aspectRatio));
      expect(restored.resolution, equals(project.resolution));
      expect(restored.clips.length, equals(1));

      final restoredClip = restored.clips.first;
      expect(restoredClip.id, equals(clip.id));
      expect(restoredClip.label, equals(clip.label));
      expect(restoredClip.volume, equals(0.8));
      expect(restoredClip.speed, equals(1.2));
      expect(restoredClip.textStyle.fontSize, equals(32));
      expect(restoredClip.colorGrading.brightness, equals(0.1));
      expect(restored.captions.length, equals(1));
      expect(restored.captions.first.text, equals('Hello World'));
    });
  });
}
