import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/effects/services/shader_effect_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Animations and Shader Effects Unit Tests', () {
    test('All TextAnimationStyle enum values serialize and deserialize losslessly in TimelineClip', () {
      for (final animStyle in TextAnimationStyle.values) {
        final clip = TimelineClip(
          id: 'test_text_clip_${animStyle.name}',
          label: 'Test Text',
          start: Duration.zero,
          end: const Duration(seconds: 5),
          clipType: ClipType.text,
          textAnimationStyle: animStyle,
        );

        final json = clip.toJson();
        final restored = TimelineClip.fromJson(json);

        expect(restored.textAnimationStyle, equals(animStyle));
        expect(restored.textAnimationStyle.name, equals(animStyle.name));
      }
    });

    test('All ClipAnimation enum values serialize and deserialize losslessly in TimelineClip', () {
      for (final clipAnim in ClipAnimation.values) {
        final clip = TimelineClip(
          id: 'test_anim_clip_${clipAnim.name}',
          label: 'Test Clip',
          start: Duration.zero,
          end: const Duration(seconds: 5),
          clipType: ClipType.video,
          inAnimation: clipAnim,
          outAnimation: clipAnim,
        );

        final json = clip.toJson();
        final restored = TimelineClip.fromJson(json);

        expect(restored.inAnimation, equals(clipAnim));
        expect(restored.outAnimation, equals(clipAnim));
        expect(restored.inAnimation.name, equals(clipAnim.name));
      }
    });

    test('ShaderEffectService seed collection contains expanded built-in shaders', () async {
      final service = ShaderEffectService();
      // Allow async seed initialization to settle
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final effects = service.filteredEffects;

      expect(effects.length, greaterThanOrEqualTo(15));
      expect(effects.any((e) => e.id == 'chromatic_aberration'), isTrue);
      expect(effects.any((e) => e.id == 'kaleidoscope_prism'), isTrue);
      expect(effects.any((e) => e.id == 'pixelate_retro'), isTrue);
      expect(effects.any((e) => e.id == 'thermal_vision'), isTrue);
      expect(effects.any((e) => e.id == 'radial_zoom_blur'), isTrue);
      expect(effects.any((e) => e.id == 'halftone_dots'), isTrue);
      expect(effects.any((e) => e.id == 'duotone_pop'), isTrue);
      expect(effects.any((e) => e.id == 'oil_painting'), isTrue);
    });
  });
}
