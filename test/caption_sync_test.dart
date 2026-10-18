import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Caption Bulk Synchronization Tests', () {
    late EditorController controller;
    late TimelineClip caption1;
    late TimelineClip caption2;

    setUp(() {
      controller = EditorController();
      caption1 = TimelineClip(
        id: 'caption_1',
        label: 'First Caption',
        start: Duration.zero,
        end: const Duration(seconds: 3),
        clipType: ClipType.caption,
        positionX: 0.0,
        positionY: 0.0,
      );
      caption2 = TimelineClip(
        id: 'caption_2',
        label: 'Second Caption',
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 6),
        clipType: ClipType.caption,
        positionX: 0.0,
        positionY: 0.0,
      );
      controller.addClip(caption1);
      controller.addClip(caption2);
    });

    test('Updating translation on one caption applies translation to ALL captions', () {
      controller.selectClip('caption_1');
      controller.updateTranslation(
        positionX: 15.0,
        positionY: -20.0,
        scale: 1.2,
      );

      final c1 = controller.clips.firstWhere((c) => c.id == 'caption_1');
      final c2 = controller.clips.firstWhere((c) => c.id == 'caption_2');

      expect(c1.positionX, equals(15.0));
      expect(c1.positionY, equals(-20.0));
      expect(c1.scale, equals(1.2));

      expect(c2.positionX, equals(15.0));
      expect(c2.positionY, equals(-20.0));
      expect(c2.scale, equals(1.2));
    });

    test('Updating text style on one caption applies style to ALL captions', () {
      controller.selectClip('caption_1');
      const newStyle = TextStyleProperties(
        fontSize: 32.0,
        textColor: Colors.yellow,
        highlightStyle: 'badge',
      );
      controller.updateSelectedClipTextStyle(newStyle);

      final c1 = controller.clips.firstWhere((c) => c.id == 'caption_1');
      final c2 = controller.clips.firstWhere((c) => c.id == 'caption_2');

      expect(c1.textStyle.fontSize, equals(32.0));
      expect(c1.textStyle.textColor, equals(Colors.yellow));
      expect(c1.textStyle.highlightStyle, equals('badge'));

      expect(c2.textStyle.fontSize, equals(32.0));
      expect(c2.textStyle.textColor, equals(Colors.yellow));
      expect(c2.textStyle.highlightStyle, equals('badge'));
    });

    test('Applying video effect or animation to one caption syncs to ALL captions', () {
      controller.selectClip('caption_1');
      controller.applyEffect(VideoEffect.glitch);
      controller.updateAnimations(
        inAnimation: ClipAnimation.fadeIn,
        outAnimation: ClipAnimation.fadeOut,
      );

      final c1 = controller.clips.firstWhere((c) => c.id == 'caption_1');
      final c2 = controller.clips.firstWhere((c) => c.id == 'caption_2');

      expect(c1.effect, equals(VideoEffect.glitch));
      expect(c1.inAnimation, equals(ClipAnimation.fadeIn));
      expect(c1.outAnimation, equals(ClipAnimation.fadeOut));

      expect(c2.effect, equals(VideoEffect.glitch));
      expect(c2.inAnimation, equals(ClipAnimation.fadeIn));
      expect(c2.outAnimation, equals(ClipAnimation.fadeOut));
    });

    test('Adding and removing shader effects on a caption syncs to ALL captions', () {
      controller.selectClip('caption_1');
      const shaderFx = ShaderEffectClip(
        id: 'glow_fx',
        effectId: 'glow',
        name: 'Glow Effect',
      );

      controller.addShaderEffectToSelectedClip(shaderFx);

      final c1 = controller.clips.firstWhere((c) => c.id == 'caption_1');
      final c2 = controller.clips.firstWhere((c) => c.id == 'caption_2');

      expect(c1.shaderEffects.length, equals(1));
      expect(c2.shaderEffects.length, equals(1));
      expect(c1.shaderEffects.first.id, equals('glow_fx'));
      expect(c2.shaderEffects.first.id, equals('glow_fx'));

      controller.removeShaderEffectFromSelectedClip('glow_fx');

      final c1After = controller.clips.firstWhere((c) => c.id == 'caption_1');
      final c2After = controller.clips.firstWhere((c) => c.id == 'caption_2');

      expect(c1After.shaderEffects, isEmpty);
      expect(c2After.shaderEffects, isEmpty);
    });
  });
}
