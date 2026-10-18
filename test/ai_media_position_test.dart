import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI Generated Media Placement Tests', () {
    test('getEndOfExistingMediaClips returns max end timestamp of video/image clips', () {
      final editor = EditorController();

      final video1 = TimelineClip(
        id: 'v1',
        label: 'Video 1',
        start: Duration.zero,
        end: const Duration(seconds: 10),
        clipType: ClipType.video,
      );

      final video2 = TimelineClip(
        id: 'v2',
        label: 'Video 2',
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 25),
        clipType: ClipType.video,
      );

      final audio = TimelineClip(
        id: 'a1',
        label: 'Audio 1',
        start: Duration.zero,
        end: const Duration(seconds: 40),
        clipType: ClipType.audio,
      );

      editor.addClip(video1);
      editor.addClip(video2);
      editor.addClip(audio);

      expect(editor.getEndOfExistingMediaClips(), equals(const Duration(seconds: 25)));
    });
  });
}
