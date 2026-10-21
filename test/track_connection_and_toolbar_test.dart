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
    testWidgets('Adjustment track selection shows Adjust and Delete tools', (tester) async {
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

      expect(find.text('Adjust'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Chroma Key track selection shows Chroma Key and Delete tools', (tester) async {
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

      expect(find.text('Chroma Key'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Effect track selection shows Effects, Filters and Delete tools', (tester) async {
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

      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
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
  });
}
