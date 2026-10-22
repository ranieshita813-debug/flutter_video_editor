import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/face_tracking_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/face_tracking_sheet.dart';

void main() {
  group('Face Tracking Models Unit Tests', () {
    test('FaceKeyframe serialization and lerp in FaceTrack.rectAt', () {
      final kf1 = FaceKeyframe(timeMs: 0, rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
      final kf2 = FaceKeyframe(timeMs: 300, rect: const Rect.fromLTWH(0.3, 0.3, 0.2, 0.2));

      final jsonMap = kf1.toJson();
      final deserialized = FaceKeyframe.fromJson(jsonMap);
      expect(deserialized.timeMs, equals(0));
      expect(deserialized.rect, equals(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)));

      final track = FaceTrack(id: 'track1', frames: [kf1, kf2]);

      // Midpoint lerp check at 150ms
      final midRect = track.rectAt(150);
      expect(midRect, isNotNull);
      expect(midRect!.left, closeTo(0.2, 0.001));
      expect(midRect.top, closeTo(0.2, 0.001));

      // Gap threshold check exceeding 400ms max gap
      final gapTrack = FaceTrack(
        id: 'gapTrack',
        frames: [
          FaceKeyframe(timeMs: 0, rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)),
          FaceKeyframe(timeMs: 1000, rect: const Rect.fromLTWH(0.3, 0.3, 0.2, 0.2)),
        ],
      );
      // 500ms is > 400ms from both 0ms and 1000ms
      expect(gapTrack.rectAt(500, maxGapMs: 400), isNull);
    });

    test('Person.rectAt applies safety privacy margin', () {
      final kf = FaceKeyframe(timeMs: 0, rect: const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4));
      final track = FaceTrack(id: 't1', frames: [kf]);
      final person = Person(id: 'p1', name: 'Person 1', tracks: [track]);

      final rawRect = person.rectAt(0, margin: 0.0);
      expect(rawRect, equals(const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4)));

      final expandedRect = person.rectAt(0, margin: 0.25);
      expect(expandedRect, isNotNull);
      expect(expandedRect!.left, lessThan(0.2));
      expect(expandedRect.right, greaterThan(0.6));
    });

    test('FaceTrackingData serialization and deserialization', () {
      final kf = FaceKeyframe(timeMs: 0, rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
      final track = FaceTrack(id: 't1', frames: [kf]);
      final effect = const PersonEffect(type: PersonEffectType.blur, intensity: 12.0);
      final person = Person(id: 'p1', name: 'Person 1', tracks: [track], effects: [effect]);
      final data = FaceTrackingData(isProcessed: true, persons: [person]);

      final jsonMap = data.toJson();
      final deserialized = FaceTrackingData.fromJson(jsonMap);

      expect(deserialized.isProcessed, isTrue);
      expect(deserialized.persons.length, equals(1));
      expect(deserialized.persons.first.name, equals('Person 1'));
      expect(deserialized.persons.first.effects.first.type, equals(PersonEffectType.blur));
    });
  });

  group('FaceTrackingService Pipeline & Operations', () {
    final service = FaceTrackingService();

    test('computeIoU calculates intersection over union accurately', () {
      const rectA = Rect.fromLTWH(0.0, 0.0, 2.0, 2.0); // Area = 4
      const rectB = Rect.fromLTWH(1.0, 0.0, 2.0, 2.0); // Area = 4, Intersection = 1*2 = 2
      final iou = FaceTrackingService.computeIoU(rectA, rectB);
      expect(iou, closeTo(2.0 / 6.0, 0.01)); // 2 / (4+4-2) = 0.333
    });

    test('cosineSimilarity computes vector dot product similarity', () {
      final vecA = [1.0, 0.0, 0.0];
      final vecB = [1.0, 0.0, 0.0];
      final vecC = [0.0, 1.0, 0.0];

      expect(FaceTrackingService.cosineSimilarity(vecA, vecB), closeTo(1.0, 0.001));
      expect(FaceTrackingService.cosineSimilarity(vecA, vecC), closeTo(0.0, 0.001));
    });

    test('processClip runs full 5-step face tracking pipeline', () async {
      final clip = TimelineClip(
        id: 'c1',
        label: 'Test Clip',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        clipType: ClipType.video,
      );

      final result = await service.processClip(clip);
      expect(result.isProcessed, isTrue);
      expect(result.persons, isNotEmpty);
      expect(result.persons.first.tracks, isNotEmpty);
    });

    test('mergePersons combines multiple person tracks', () {
      final p1 = Person(
        id: 'p1',
        name: 'Person 1',
        tracks: [FaceTrack(id: 't1', frames: [])],
      );
      final p2 = Person(
        id: 'p2',
        name: 'Person 2',
        tracks: [FaceTrack(id: 't2', frames: [])],
      );
      final data = FaceTrackingData(isProcessed: true, persons: [p1, p2]);

      final merged = service.mergePersons(data, ['p1', 'p2']);
      expect(merged.persons.length, equals(1));
      expect(merged.persons.first.tracks.length, equals(2));
    });

    test('splitPersonTrack splits track out into new person', () {
      final p1 = Person(
        id: 'p1',
        name: 'Person 1',
        tracks: [
          FaceTrack(id: 't1', frames: []),
          FaceTrack(id: 't2', frames: []),
        ],
      );
      final data = FaceTrackingData(isProcessed: true, persons: [p1]);

      final splitData = service.splitPersonTrack(data, 'p1', 't2');
      expect(splitData.persons.length, equals(2));
      expect(splitData.persons.first.tracks.length, equals(1));
      expect(splitData.persons.last.tracks.length, equals(1));
    });
  });

  group('EditorController & FaceTrackingSheet Widget Tests', () {
    testWidgets('FaceTrackingSheet renders initial scan button and processes clip', (tester) async {
      final editor = EditorController();
      final clip = TimelineClip(
        id: 'clip_video',
        label: 'Video',
        start: Duration.zero,
        end: const Duration(seconds: 3),
        clipType: ClipType.video,
      );
      editor.addClip(clip);
      editor.selectClip(clip.id);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<EditorController>.value(
            value: editor,
            child: const Scaffold(
              body: FaceTrackingSheet(),
            ),
          ),
        ),
      );

      expect(find.text('Auto Face Detection & Tracking'), findsOneWidget);
      expect(find.text('Scan & Detect Faces'), findsOneWidget);

      await tester.tap(find.text('Scan & Detect Faces'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('Persons Found'), findsOneWidget);
      expect(find.text('Person 1 Effect'), findsOneWidget);
      expect(find.text('Blur'), findsOneWidget);
      expect(find.text('Mosaic'), findsOneWidget);
    });
  });
}
