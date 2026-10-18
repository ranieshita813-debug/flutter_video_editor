import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Canvas Ratio Detection Tests', () {
    test('detectCanvasRatio correctly maps dimensions to closest preset', () {
      expect(detectCanvasRatio(1920, 1080), equals(CanvasRatio.r16x9));
      expect(detectCanvasRatio(1080, 1920), equals(CanvasRatio.r9x16));
      expect(detectCanvasRatio(1080, 1080), equals(CanvasRatio.r1x1));
      expect(detectCanvasRatio(1080, 1350), equals(CanvasRatio.r4x5));
      expect(detectCanvasRatio(2560, 1080), equals(CanvasRatio.r21x9));
    });

    test('canvasRatioNotifier updates value correctly when ratio is set', () {
      canvasRatioNotifier.value = CanvasRatio.r16x9;
      expect(canvasRatioNotifier.value, equals(CanvasRatio.r16x9));

      final detected = detectCanvasRatio(1080, 1920);
      canvasRatioNotifier.value = detected;
      expect(canvasRatioNotifier.value, equals(CanvasRatio.r9x16));
    });
  });
}
