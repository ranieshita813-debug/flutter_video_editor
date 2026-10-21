import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/widgets/timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Selection and Toolbar Filtering Tests', () {
    testWidgets('Adjustment track selection shows Split, Adjust and Delete tools', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_1',
        label: 'Video 1',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        colorGrading: const ColorGradingSettings(brightness: 0.2),
      );
      controller.addClip(clip);
      controller.selectClip('clip_1_adj');

      await tester.pumpWidget(
        ChangeNotifierProvider<EditorController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Adjust'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Chroma Key track selection shows Split, Chroma Key and Delete tools', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_2',
        label: 'Video 2',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        chromaKey: const ChromaKey(enabled: true),
      );
      controller.addClip(clip);
      controller.selectClip('clip_2_ck');

      await tester.pumpWidget(
        ChangeNotifierProvider<EditorController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Chroma Key'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Effect track selection shows Split, Effects, Filters and Delete tools', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_3',
        label: 'Video 3',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        effect: VideoEffect.vibrant,
      );
      controller.addClip(clip);
      controller.selectClip('clip_3_fx');

      await tester.pumpWidget(
        ChangeNotifierProvider<EditorController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Caption track selection does NOT show Text to Speech tool', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'caption_1',
        label: 'Caption text',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        clipType: ClipType.caption,
      );
      controller.addClip(clip);
      controller.selectClip('caption_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<EditorController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Text to Speech'), findsNothing);
      expect(find.text('Edit Caption'), findsOneWidget);
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Highlight'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Splitting modifier track clip splits clip and retains modifier selection suffix', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_split_mod',
        label: 'Video Split Mod',
        start: Duration.zero,
        end: const Duration(seconds: 10),
        clipType: ClipType.video,
        colorGrading: const ColorGradingSettings(brightness: 0.3),
      );
      controller.addClip(clip);
      controller.selectClip('clip_split_mod_adj');
      controller.setPlayhead(const Duration(seconds: 4));

      controller.splitSelectedClip();

      expect(controller.project.clips.length, equals(2));
      expect(controller.selectedClipId, equals('clip_split_mod_part2_adj'));
      expect(controller.project.clips[0].end, equals(const Duration(seconds: 4)));
      expect(controller.project.clips[1].start, equals(const Duration(seconds: 4)));

      // Deleting selected adjustment on right part resets colorGrading on right part only
      controller.deleteSelectedClip();
      expect(controller.project.clips[0].colorGrading.brightness, equals(0.3));
      expect(controller.project.clips[1].colorGrading.brightness, equals(0.0));
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Deleting synthetic adjustment track clip resets color grading', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_4',
        label: 'Video 4',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        colorGrading: const ColorGradingSettings(brightness: 0.5),
      );
      controller.addClip(clip);
      controller.selectClip('clip_4_adj');

      controller.deleteSelectedClip();

      expect(controller.project.clips.length, equals(1));
      expect(controller.project.clips.first.colorGrading.brightness, equals(0.0));
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('TimelineWidget renders tracks and connection lines without errors', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_5',
        label: 'Video 5',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        colorGrading: const ColorGradingSettings(brightness: 0.5),
        chromaKey: const ChromaKey(enabled: true),
        effect: VideoEffect.warm,
      );
      controller.addClip(clip);

      final multiOn = ValueNotifier<bool>(false);
      final multi = ValueNotifier<Set<String>>(<String>{});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineWidget(
              editor: controller,
              multiOn: multiOn,
              multi: multi,
              onClearMulti: () {},
            ),
          ),
        ),
      );

      expect(find.text('Adjustment'), findsOneWidget);
      expect(find.text('Chroma Key'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Connection line is rendered only when modifier track clip is selected', (tester) async {
      final controller = EditorController();
      addTearDown(controller.dispose);
      final clip = TimelineClip(
        id: 'clip_6',
        label: 'Video 6',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        colorGrading: const ColorGradingSettings(brightness: 0.5),
      );
      controller.addClip(clip);

      final multiOn = ValueNotifier<bool>(false);
      final multi = ValueNotifier<Set<String>>(<String>{});

      // Initially no modifier clip selected
      controller.clearSelection();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineWidget(
              editor: controller,
              multiOn: multiOn,
              multi: multi,
              onClearMulti: () {},
            ),
          ),
        ),
      );

      // Select modifier clip
      controller.selectClip('clip_6_adj');
      await tester.pumpAndSettle();

      expect(controller.selectedClipId, equals('clip_6_adj'));
      expect(find.text('Adjustment'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
    });
  });
}
