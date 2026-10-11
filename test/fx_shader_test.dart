import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/features/editor/widgets/fx_shader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FxShaders Unit and Widget Tests', () {
    test('FxShaders.all contains definitions for all expected shaders', () {
      expect(FxShaders.all.isNotEmpty, isTrue);
      expect(FxShaders.byId.containsKey('chromatic_aberration'), isTrue);
      expect(FxShaders.byId.containsKey('digital_glitch'), isTrue);
      expect(FxShaders.byId.containsKey('vhs_tape'), isTrue);
      expect(FxShaders.byId.containsKey('film_grain'), isTrue);
      expect(FxShaders.byId.containsKey('cinematic_vignette'), isTrue);
      expect(FxShaders.byId.containsKey('dream_bloom'), isTrue);
      expect(FxShaders.byId.containsKey('mosaic_pixelate'), isTrue);
      expect(FxShaders.byId.containsKey('liquid_wave'), isTrue);
      expect(FxShaders.byId.containsKey('cinematic_grade'), isTrue);
      expect(FxShaders.byId.containsKey('crisp_sharpen'), isTrue);
      expect(FxShaders.byId.containsKey('lens_distortion'), isTrue);
      expect(FxShaders.byId.containsKey('speed_zoom_blur'), isTrue);
      expect(FxShaders.byId.containsKey('light_leak'), isTrue);
      expect(FxShaders.byId.containsKey('text_gold_foil'), isTrue);
      expect(FxShaders.byId.containsKey('text_holographic'), isTrue);
      expect(FxShaders.byId.containsKey('text_glass_shine'), isTrue);
    });

    test('FxDef asset paths match expected assets/shaders directory structure', () {
      for (final def in FxShaders.all) {
        expect(def.asset, equals('assets/shaders/${def.id}.frag'));
      }
    });

    testWidgets('FxShaders.applyVideo handles "blur" effect correctly without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FxShaders.applyVideo(
                child: const Text('Test Video'),
                effectId: 'blur',
                params: const {'blurAmount': 0.5},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Video'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('FxShaders.applyVideo returns child when effect program is uninitialized', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FxShaders.applyVideo(
                child: const Text('Unloaded Effect'),
                effectId: 'digital_glitch',
                params: const {'amount': 0.8},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Unloaded Effect'), findsOneWidget);
    });

    testWidgets('FxShaders.applyText returns child when effect program is uninitialized', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FxShaders.applyText(
                child: const Text('Gold Text'),
                effectId: 'text_gold_foil',
                intensity: 0.8,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Gold Text'), findsOneWidget);
    });
  });
}
