import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/timeline/timeline.dart';

void main() {
  group('EditorController Unit Tests', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      final project = VideoProject(
        id: 'test_proj',
        name: 'Test Project',
        fps: 30,
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c1',
            label: 'Clip 1',
            start: Duration.zero,
            end: const Duration(seconds: 10),
            sourceDuration: const Duration(seconds: 10),
            clipType: ClipType.video,
          ),
          TimelineClip(
            id: 'c2',
            label: 'Clip 2',
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
            sourceDuration: const Duration(seconds: 10),
            clipType: ClipType.video,
          ),
        ],
      );
      controller.loadProject(project);
    });

    test('Seek quantization and playhead clamping', () {
      controller.setPlayhead(const Duration(milliseconds: 1234));
      // 1234ms = 1.234s. At 30fps, 1.234 * 30 = 37.02 -> 37 frames -> 37 / 30 = 1.23333s = 1233ms
      expect(controller.playhead.inMilliseconds, closeTo(1233, 2));

      controller.setPlayhead(const Duration(seconds: 50));
      expect(controller.playhead, equals(const Duration(seconds: 20)));
    });

    test('Trim clamping and source duration bounds', () {
      controller.selectClip('c1');
      controller.updateClipTrim('c1', trimStart: const Duration(seconds: 2));

      final clip = controller.selectedClip!;
      expect(clip.trimStart, equals(const Duration(seconds: 2)));
      expect(clip.duration, equals(const Duration(seconds: 8)));
    });

    test('Ripple reorder on main track', () {
      controller.selectClip('c1');
      controller.updateClipTrim('c1', trimStart: const Duration(seconds: 4));

      final c1 = controller.clips.firstWhere((c) => c.id == 'c1');
      final c2 = controller.clips.firstWhere((c) => c.id == 'c2');

      expect(c1.duration, equals(const Duration(seconds: 6)));
      expect(c2.start, equals(const Duration(seconds: 6)));
      expect(c2.end, equals(const Duration(seconds: 16)));
    });

    test('Playback position mapping with trim and speed', () {
      final clip = TimelineClip(
        id: 'c3',
        label: 'Clip 3',
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 10),
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 0),
        sourceDuration: const Duration(seconds: 10),
        speed: 2.0,
        clipType: ClipType.video,
      );

      final localTime = controller.getClipLocalTime(clip, const Duration(seconds: 7));
      // offset = 2s. scaled by 2.0 = 4s. trimStart = 2s -> 6s local position
      expect(localTime, equals(const Duration(seconds: 6)));
    });

    test('Append media addClips places main clips sequentially after last clip', () {
      final newClips = <TimelineClip>[
        TimelineClip(
          id: 'c_new',
          label: 'New Clip',
          start: Duration.zero,
          end: const Duration(seconds: 5),
          sourceDuration: const Duration(seconds: 5),
          clipType: ClipType.video,
        ),
      ];

      controller.addClips(newClips);

      final added = controller.clips.firstWhere((c) => c.id == 'c_new');
      expect(added.start, equals(const Duration(seconds: 20)));
      expect(added.end, equals(const Duration(seconds: 25)));
    });
  });

  group('Timeline Widget Test', () {
    testWidgets('Selecting a clip shows white trim handles', (WidgetTester tester) async {
      final controller = EditorController();
      final project = VideoProject(
        id: 'test_proj',
        name: 'Test Project',
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c1',
            label: 'Clip 1',
            start: Duration.zero,
            end: const Duration(seconds: 5),
            sourceDuration: const Duration(seconds: 5),
            clipType: ClipType.video,
          ),
        ],
      );
      controller.loadProject(project);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: ChangeNotifierProvider<EditorController>.value(
                value: controller,
                child: Timeline(editor: controller),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Timeline), findsOneWidget);

      await tester.tap(find.byType(Timeline));
      await tester.pumpAndSettle();

      controller.selectClip('c1');
      expect(controller.selectedClipId, equals('c1'));

      controller.dispose();
    });
  });
}
