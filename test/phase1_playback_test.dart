import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/controllers/playback_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/transport.dart';

class TestStopwatch implements Stopwatch {
  Duration customElapsed = Duration.zero;
  bool _running = false;

  @override
  Duration get elapsed => customElapsed;

  @override
  int get elapsedMilliseconds => customElapsed.inMilliseconds;

  @override
  int get elapsedMicroseconds => customElapsed.inMicroseconds;

  @override
  int get elapsedTicks => customElapsed.inMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => _running;

  @override
  void reset() {
    customElapsed = Duration.zero;
  }

  @override
  void start() {
    _running = true;
  }

  @override
  void stop() {
    _running = false;
  }
}

void main() {
  testWidgets('Playback ticker updates timecode in TransportBar without pausing',
      (WidgetTester tester) async {
    late EditorController editor;
    final testStopwatch = TestStopwatch();

    editor = EditorController(
      playbackController: PlaybackController(
        onTimeUpdate: () => editor.notifyListeners(),
        clock: testStopwatch,
      ),
    );

    // Add a clip so totalDuration is positive
    final clip = TimelineClip(
      id: 'clip_1',
      label: 'Test Clip',
      start: Duration.zero,
      end: const Duration(seconds: 10),
      clipType: ClipType.video,
    );
    editor.addClip(clip);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<EditorController>.value(
            value: editor,
            child: TransportBar(editor: editor),
          ),
        ),
      ),
    );

    // Initially at zero: formatTimecode(0) -> "00:00:00:00"
    expect(find.text('00:00:00:00'), findsOneWidget);
    expect(editor.isPlaying, false);

    // Toggle playback
    editor.togglePlayback();
    expect(editor.isPlaying, true);

    // Advance test clock and pump
    testStopwatch.customElapsed = const Duration(milliseconds: 200);
    await tester.pump(const Duration(milliseconds: 33));

    // Timecode should have updated from 00:00:00:00
    expect(find.text('00:00:00:00'), findsNothing);
    expect(editor.isPlaying, true);

    // Clean up
    editor.reset();
    editor.dispose();
  });
}
