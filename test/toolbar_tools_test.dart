import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildEditorApp(EditorController controller) {
    return ChangeNotifierProvider<EditorController>.value(
      value: controller,
      child: const MaterialApp(
        home: EditorPage(),
      ),
    );
  }

  group('Toolbar Tools Integration Tests', () {
    testWidgets('EditorPage renders toolbar and opens global tools', (WidgetTester tester) async {
      final controller = EditorController();
      await tester.pumpWidget(buildEditorApp(controller));
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.byType(EditorPage), findsOneWidget);

      expect(find.text('Add Media'), findsOneWidget);
      expect(find.text('Overlay'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('EditorPage toolbar shows clip tools for Video clip', (WidgetTester tester) async {
      final controller = EditorController();
      final videoClip = TimelineClip(
        id: 'v1',
        label: 'Sample Video',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
      );
      controller.addClip(videoClip);
      controller.selectClip('v1');

      await tester.pumpWidget(buildEditorApp(controller));
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Canvas'), findsOneWidget);
      expect(find.text('Adjust'), findsOneWidget);
    });

    testWidgets('EditorPage toolbar shows clip tools for Caption clip', (WidgetTester tester) async {
      final controller = EditorController();
      final captionClip = TimelineClip(
        id: 'c1',
        label: 'Sample Caption',
        start: Duration.zero,
        end: const Duration(seconds: 3),
        clipType: ClipType.caption,
      );
      controller.addClip(captionClip);
      controller.selectClip('c1');

      await tester.pumpWidget(buildEditorApp(controller));
      await tester.pumpAndSettle(const Duration(milliseconds: 700));

      expect(find.text('Edit Caption'), findsOneWidget);
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Auto captions'), findsOneWidget);
    });
  });
}
