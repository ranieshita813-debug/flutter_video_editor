import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

void main() {
  group('EditorController Unit Tests', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
    });

    test('Initial controller state starts with empty project clips', () {
      expect(controller.clips.isEmpty, isTrue);
      expect(controller.selectedClipId, isNull);
      expect(controller.isPlaying, isFalse);
    });

    test('Playback toggling works correctly', () {
      expect(controller.isPlaying, isFalse);
      controller.togglePlayback();
      expect(controller.isPlaying, isTrue);
      controller.togglePlayback();
      expect(controller.isPlaying, isFalse);
    });

    test('Zoom and Playhead setting', () {
      controller.setZoom(2.0);
      expect(controller.zoom, equals(2.0));

      controller.setPlayhead(const Duration(seconds: 4));
      expect(controller.playhead, equals(const Duration(seconds: 4)));
    });

    test('Clip splitting creates two clips', () {
      controller.addClip(
        TimelineClip(
          id: 'c1',
          label: 'Test Clip',
          start: Duration.zero,
          end: const Duration(seconds: 10),
          clipType: ClipType.video,
        ),
      );

      final initialCount = controller.clips.length;
      controller.setPlayhead(const Duration(seconds: 3));
      controller.splitSelectedClip();

      expect(controller.clips.length, equals(initialCount + 1));
    });

    test('Undo and Redo functionality', () {
      final initialCount = controller.clips.length;
      controller.addTextOverlay('New Title');
      expect(controller.clips.length, equals(initialCount + 1));
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.clips.length, equals(initialCount));
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.clips.length, equals(initialCount + 1));
    });

    test('Vector drawing adding and saving as clip', () {
      controller.setDrawingColor(Colors.red);
      controller.setStrokeWidth(6.0);
      controller.addStrokeToActiveDrawing(
        DrawingStroke(
          id: 's1',
          points: const <Offset>[Offset(10, 10), Offset(50, 50)],
          color: Colors.red,
          strokeWidth: 6.0,
        ),
      );

      expect(controller.activeDrawingStrokes.length, equals(1));
      controller.saveVectorDrawingAsClip();

      expect(controller.activeDrawingStrokes.isEmpty, isTrue);
      expect(controller.clips.any((c) => c.clipType == ClipType.drawing), isTrue);
    });

    test('Color grading update on selected clip', () {
      controller.addClip(
        TimelineClip(
          id: 'c1',
          label: 'Video Shot',
          start: Duration.zero,
          end: const Duration(seconds: 5),
          clipType: ClipType.video,
        ),
      );

      const grading = ColorGradingSettings(
        brightness: 0.2,
        contrast: 1.3,
        saturation: 1.5,
      );

      controller.updateColorGrading(grading);
      expect(controller.selectedClip?.colorGrading.brightness, equals(0.2));
      expect(controller.selectedClip?.colorGrading.contrast, equals(1.3));
    });

    test('Audio track adding and properties update', () {
      controller.addAudioTrack('Voiceover Stream');
      expect(controller.selectedClip?.clipType, equals(ClipType.audio));

      controller.updateAudioProperties(
        const AudioProperties(volume: 1.5, pitch: 1.2, equalizerPreset: 'Rock'),
      );

      expect(controller.selectedClip?.audioProperties.volume, equals(1.5));
      expect(controller.selectedClip?.audioProperties.equalizerPreset, equals('Rock'));
    });

    test('Auto Captions generation adds caption clips', () {
      controller.addClip(
        TimelineClip(
          id: 'c1',
          label: 'Audio Scene',
          start: Duration.zero,
          end: const Duration(seconds: 8),
          clipType: ClipType.audio,
        ),
      );

      controller.generateAutoCaptions();
      expect(controller.project.captions.isNotEmpty, isTrue);
      expect(controller.clips.any((c) => c.clipType == ClipType.caption), isTrue);
    });

    test('Custom Font Uploading', () {
      controller.uploadCustomFont('Futura');
      expect(controller.project.customFonts.contains('Futura'), isTrue);
    });

    test('Fast Export simulation pipeline', () async {
      expect(controller.isExporting, isFalse);

      bool completed = false;
      final exportFuture = controller.startExport(onComplete: () {
        completed = true;
      });

      expect(controller.isExporting, isTrue);
      await exportFuture;

      expect(controller.isExporting, isFalse);
      expect(controller.exportProgress, equals(1.0));
      expect(completed, isTrue);
    });
  });
}
