import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Timeline Export Serialization Tests', () {
    test('TimelineDto.fromProject losslessly serializes all clip effects, animations, and properties', () {
      final clip = TimelineClip(
        id: 'test_clip_1',
        label: 'Video Clip 1',
        start: Duration.zero,
        end: const Duration(seconds: 5),
        clipType: ClipType.video,
        layerIndex: 0,
        speed: 1.25,
        volume: 0.8,
        opacity: 0.9,
        scale: 1.1,
        rotation: 45.0,
        positionX: 10.0,
        positionY: -15.0,
        anchorX: 0.25,
        anchorY: 0.75,
        effect: VideoEffect.cinematic,
        effectParameters: const <String, double>{'intensity': 0.75, 'blurAmount': 2.5},
        inAnimation: ClipAnimation.fadeIn,
        outAnimation: ClipAnimation.fadeOut,
        loopAnimation: ClipAnimation.bounce,
        textAnimationStyle: TextAnimationStyle.typewriter,
        fontFamily: 'Roboto',
        textStyle: const TextStyleProperties(fontSize: 36.0, textColor: Colors.red),
        colorGrading: const ColorGradingSettings(brightness: 0.2, contrast: 1.1),
        chromaKey: const ChromaKey(enabled: true),
        cameraProperties: const CameraProperties(focalLength: 50.0),
        maskProperties: const MaskProperties(type: MaskType.circle, feather: 12.0),
        keyframes: const <Keyframe>[
          Keyframe(
            id: 'kf1',
            time: Duration(seconds: 1),
            property: KeyframeProperty.scale,
            value: 1.5,
          ),
        ],
        shaderEffects: const <ShaderEffectClip>[
          ShaderEffectClip(
            id: 'shader1',
            effectId: 'glow',
            name: 'Glow Effect',
            parameterValues: <String, dynamic>{'intensity': 0.8, 'radius': 12.0},
            keyframeAnimations: <KeyframeAnimation>[
              KeyframeAnimation(
                id: 'ka1',
                parameterId: 'intensity',
                keyframes: <ShaderKeyframe>[
                  ShaderKeyframe(id: 'skf1', time: Duration.zero, value: 0.2),
                  ShaderKeyframe(id: 'skf2', time: Duration(seconds: 2), value: 0.8),
                ],
              ),
            ],
          ),
        ],
        words: const <CaptionWord>[
          CaptionWord(word: 'Hello', start: Duration.zero, end: Duration(seconds: 1)),
        ],
      );

      final project = Project(
        id: 'p1',
        name: 'Export Test Project',
        clips: [clip],
      );

      const settings = ExportSettings(fps: 60);
      final dto = TimelineDto.fromProject(project, settings);
      final json = dto.toJson();
      final restored = TimelineDto.fromJson(json);

      expect(restored.projectName, equals('Export Test Project'));
      expect(restored.clips.length, equals(1));

      final restoredClip = restored.clips.first;
      expect(restoredClip.id, equals('test_clip_1'));
      expect(restoredClip.anchorX, equals(0.25));
      expect(restoredClip.anchorY, equals(0.75));
      expect(restoredClip.effect, equals('cinematic'));
      expect(restoredClip.effectParameters['intensity'], equals(0.75));
      expect(restoredClip.effectParameters['blurAmount'], equals(2.5));
      expect(restoredClip.inAnimation, equals('fadeIn'));
      expect(restoredClip.outAnimation, equals('fadeOut'));
      expect(restoredClip.loopAnimation, equals('bounce'));
      expect(restoredClip.cameraProperties['focalLength'], equals(50.0));
      expect(restoredClip.maskProperties['type'], equals('circle'));
      expect(restoredClip.keyframes.length, equals(1));
      expect(restoredClip.shaderEffects.length, equals(1));

      final shaderFx = restoredClip.shaderEffects.first;
      expect(shaderFx['effectId'], equals('glow'));
      expect(shaderFx['parameterValues']['intensity'], equals(0.8));
      expect(shaderFx['parameterValues']['radius'], equals(12.0));
      expect((shaderFx['keyframeAnimations'] as List).length, equals(1));

      expect(restoredClip.words.length, equals(1));
    });
  });
}
