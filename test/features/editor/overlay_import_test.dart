import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Overlay Import Tests', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('addOverlayClip creates image overlay clip on layerIndex > 0', () {
      expect(controller.clips, isEmpty);

      controller.addOverlayClip('test_overlay.png');

      expect(controller.clips.length, equals(1));
      final clip = controller.clips.first;
      expect(clip.clipType, equals(ClipType.image));
      expect(clip.layerIndex, greaterThan(0));
      expect(clip.sourcePath, equals('test_overlay.png'));
      expect(controller.selectedClipId, equals(clip.id));
    });

    test('addOverlayClip creates video overlay clip on layerIndex > 0', () {
      controller.addOverlayClip('test_overlay.mp4');

      expect(controller.clips.length, equals(1));
      final clip = controller.clips.first;
      expect(clip.clipType, equals(ClipType.video));
      expect(clip.layerIndex, greaterThan(0));
      expect(clip.sourcePath, equals('test_overlay.mp4'));
      expect(controller.selectedClipId, equals(clip.id));
    });

    test('multiple overlay clips get unique layerIndex when overlapping', () {
      controller.addOverlayClip('overlay1.png');
      controller.addOverlayClip('overlay2.mp4');

      expect(controller.clips.length, equals(2));
      final clip1 = controller.clips[0];
      final clip2 = controller.clips[1];

      expect(clip1.layerIndex, equals(1));
      expect(clip2.layerIndex, equals(2));
      expect(clip1.layerIndex, isNot(equals(clip2.layerIndex)));
    });

    testWidgets('EditorToolbar renders Overlay toolbar item when no clip selected',
        (WidgetTester tester) async {
      bool overlayTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<EditorController>.value(
              value: controller,
              child: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {
                  overlayTapped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Overlay'), findsOneWidget);

      await tester.tap(find.text('Overlay'));
      await tester.pumpAndSettle();

      expect(overlayTapped, isTrue);
    });
  });
}
