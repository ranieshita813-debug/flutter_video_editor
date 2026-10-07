import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/effects/services/shader_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('effects_test_').path;
        }
        return null;
      },
    );
  });

  group('Shader Effect Domain Models Serialization Unit Tests', () {
    test('ShaderParameter serialization and deserialization is lossless', () {
      const param = ShaderParameter(
        id: 'intensity',
        name: 'intensity',
        label: 'Intensity',
        type: ParameterType.float,
        value: 0.85,
        defaultValue: 1.0,
        min: 0.0,
        max: 2.0,
      );

      final json = param.toJson();
      final restored = ShaderParameter.fromJson(json);

      expect(restored.id, equals('intensity'));
      expect(restored.label, equals('Intensity'));
      expect(restored.type, equals(ParameterType.float));
      expect(restored.doubleValue, equals(0.85));
      expect(restored.min, equals(0.0));
      expect(restored.max, equals(2.0));
    });

    test('ShaderEffect serialization and deserialization is lossless', () {
      const effect = ShaderEffect(
        id: 'neon_glow',
        name: 'Neon Glow',
        description: 'Vibrant neon edges',
        category: ShaderEffectCategory.glow,
        type: EffectType.builtIn,
        isFavorite: true,
        isDownloaded: true,
        parameters: [
          ShaderParameter(
            id: 'glowStrength',
            name: 'glowStrength',
            label: 'Glow Strength',
            type: ParameterType.float,
            value: 1.5,
            defaultValue: 1.0,
          ),
        ],
      );

      final json = effect.toJson();
      final restored = ShaderEffect.fromJson(json);

      expect(restored.id, equals('neon_glow'));
      expect(restored.name, equals('Neon Glow'));
      expect(restored.category, equals(ShaderEffectCategory.glow));
      expect(restored.isFavorite, isTrue);
      expect(restored.parameters.length, equals(1));
      expect(restored.parameters.first.id, equals('glowStrength'));
    });
  });

  group('ShaderEffectClip Keyframe Animation & Interpolation Unit Tests', () {
    test('Interpolates scalar parameter value over time between keyframes', () {
      final clip = ShaderEffectClip(
        id: 'clip_fx_1',
        effectId: 'neon_glow',
        name: 'Neon Glow',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        parameterValues: {'intensity': 0.0},
        keyframeAnimations: [
          const KeyframeAnimation(
            id: 'anim_1',
            parameterId: 'intensity',
            keyframes: [
              ShaderKeyframe(
                id: 'kf_0',
                time: Duration.zero,
                value: 0.0,
                easing: AnimationEasing.linear,
              ),
              ShaderKeyframe(
                id: 'kf_1',
                time: Duration(seconds: 2),
                value: 1.0,
                easing: AnimationEasing.linear,
              ),
            ],
          ),
        ],
      );

      final paramsAtStart = clip.getInterpolatedParameters(Duration.zero);
      expect(paramsAtStart['intensity'], equals(0.0));

      final paramsAtMid = clip.getInterpolatedParameters(const Duration(seconds: 1));
      expect(paramsAtMid['intensity'], equals(0.5));

      final paramsAtEnd = clip.getInterpolatedParameters(const Duration(seconds: 2));
      expect(paramsAtEnd['intensity'], equals(1.0));
    });

    test('Color parameter interpolation works smoothly with lerp', () {
      final clip = ShaderEffectClip(
        id: 'clip_fx_2',
        effectId: 'warm_sunset',
        name: 'Warm Sunset',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        parameterValues: {'tintColor': const Color(0xFF000000)},
        keyframeAnimations: [
          const KeyframeAnimation(
            id: 'anim_color',
            parameterId: 'tintColor',
            keyframes: [
              ShaderKeyframe(
                id: 'kf_c1',
                time: Duration.zero,
                value: Color(0xFF000000),
                easing: AnimationEasing.linear,
              ),
              ShaderKeyframe(
                id: 'kf_c2',
                time: Duration(seconds: 2),
                value: Color(0xFFFFFFFF),
                easing: AnimationEasing.linear,
              ),
            ],
          ),
        ],
      );

      final colorAtMid = clip.getInterpolatedParameters(const Duration(seconds: 1))['tintColor'] as Color;
      expect(colorAtMid.r, greaterThan(0));
      expect(colorAtMid.g, greaterThan(0));
      expect(colorAtMid.b, greaterThan(0));
    });
  });

  group('ShaderDatabaseService Unit Tests', () {
    test('Initializes with seeds and fetches all, category, and favorites', () async {
      final db = ShaderDatabaseService.instance;
      db.resetMemoryRegistry();

      const seed1 = ShaderEffect(
        id: 'fx_1',
        name: 'Test Glow',
        description: 'Desc',
        category: ShaderEffectCategory.glow,
        isFavorite: true,
      );
      const seed2 = ShaderEffect(
        id: 'fx_2',
        name: 'Test Blur',
        description: 'Desc',
        category: ShaderEffectCategory.blur,
        isFavorite: false,
      );

      await db.initialize(seeds: [seed1, seed2]);

      final all = db.fetchAllEffects();
      expect(all.length, greaterThanOrEqualTo(2));

      final glowList = db.fetchByCategory(ShaderEffectCategory.glow);
      expect(glowList.any((e) => e.id == 'fx_1'), isTrue);

      final favorites = db.fetchFavorites();
      expect(favorites.any((e) => e.id == 'fx_1'), isTrue);

      final updated = await db.toggleFavorite('fx_2');
      expect(updated?.isFavorite, isTrue);
    });
  });

  group('EditorController Shader Effects Integration Unit Tests', () {
    test('Adds, updates, and removes ShaderEffectClips on selected TimelineClip', () {
      final controller = EditorController();
      final clip = TimelineClip(
        id: 'test_clip_1',
        label: 'Video Clip',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
      );

      controller.addClip(clip);
      controller.selectClip('test_clip_1');

      final shaderFx = ShaderEffectClip(
        id: 'shader_fx_1',
        effectId: 'neon_glow',
        name: 'Neon Glow',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        parameterValues: {'intensity': 0.5},
      );

      controller.addShaderEffectToSelectedClip(shaderFx);
      expect(controller.selectedClip?.shaderEffects.length, equals(1));
      expect(controller.selectedClip?.shaderEffects.first.name, equals('Neon Glow'));

      controller.updateShaderEffectParameters('shader_fx_1', {'intensity': 1.2});
      expect(
        controller.selectedClip?.shaderEffects.first.parameterValues['intensity'],
        equals(1.2),
      );

      controller.toggleShaderEffectEnabled('shader_fx_1');
      expect(controller.selectedClip?.shaderEffects.first.isEnabled, isFalse);

      controller.addShaderKeyframeToSelectedClip(
        'shader_fx_1',
        'intensity',
        0.8,
        AnimationEasing.easeIn,
      );
      expect(
        controller.selectedClip?.shaderEffects.first.keyframeAnimations.length,
        equals(1),
      );

      controller.removeShaderEffectFromSelectedClip('shader_fx_1');
      expect(controller.selectedClip?.shaderEffects, isEmpty);
    });
  });
}
