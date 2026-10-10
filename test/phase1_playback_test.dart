import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/transport.dart';

void main() {
  testWidgets('Playback ticking updates transport timecode without pausing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final editor = EditorController();
    editor.addClip(TimelineClip(
      id: 'c1',
      label: 'Video 1',
      start: Duration.zero,
      end: const Duration(seconds: 10),
      clipType: ClipType.video,
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: editor,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 800,
                height: 60,
                child: TransportBar(editor: editor),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('00:00:00:00'), findsOneWidget);

    await tester.runAsync(() async {
      editor.togglePlayback();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(editor.isPlaying, isTrue);
    expect(find.text('00:00:00:00'), findsNothing);
    expect(editor.playhead > Duration.zero, isTrue);

    editor.togglePlayback();
    editor.dispose();
  });
}
