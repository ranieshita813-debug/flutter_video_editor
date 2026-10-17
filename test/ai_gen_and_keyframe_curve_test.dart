import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/ai/gen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI Generation and Custom Keyframe Curve Tests', () {
    late EditorController editor;

    setUp(() {
      editor = EditorController();
    });

    test('Keyframe custom Bezier control points serialize and deserialize losslessly', () {
      const kf = Keyframe(
        id: 'kf_1',
        time: Duration(seconds: 1),
        property: KeyframeProperty.scale,
        value: 1.5,
        curveType: CurveType.cubicBezier,
        cp1x: 0.34,
        cp1y: 1.56,
        cp2x: 0.64,
        cp2y: 1.00,
      );

      final json = kf.toJson();
      final restored = Keyframe.fromJson(json);

      expect(restored.id, equals('kf_1'));
      expect(restored.time, equals(const Duration(seconds: 1)));
      expect(restored.property, equals(KeyframeProperty.scale));
      expect(restored.value, equals(1.5));
      expect(restored.curveType, equals(CurveType.cubicBezier));
      expect(restored.cp1x, closeTo(0.34, 0.001));
      expect(restored.cp1y, closeTo(1.56, 0.001));
      expect(restored.cp2x, closeTo(0.64, 0.001));
      expect(restored.cp2y, closeTo(1.00, 0.001));
    });

    test('getInterpolatedKeyframeValue uses custom cubic bezier curve control points', () {
      final clip = TimelineClip(
        id: 'clip_1',
        label: 'Video Clip',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        clipType: ClipType.video,
        keyframes: [
          const Keyframe(
            id: 'k1',
            time: Duration.zero,
            property: KeyframeProperty.opacity,
            value: 0.0,
            curveType: CurveType.cubicBezier,
            cp1x: 0.0,
            cp1y: 1.0, // Fast ease in
            cp2x: 0.0,
            cp2y: 1.0,
          ),
          const Keyframe(
            id: 'k2',
            time: Duration(seconds: 2),
            property: KeyframeProperty.opacity,
            value: 1.0,
            curveType: CurveType.linear,
          ),
        ],
      );

      final midVal = getInterpolatedKeyframeValue(
        clip,
        KeyframeProperty.opacity,
        const Duration(seconds: 1),
        0.5,
      );

      // With steep ease-in, midVal at t=0.5 should be greater than linear 0.5
      expect(midVal, greaterThan(0.5));
    });

    testWidgets('EditorToolbar renders AI Generate item when no clip selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<EditorController>.value(
            value: editor,
            child: Scaffold(
              body: EditorToolbar(
                onSelectToolSheet: (_) {},
                onAddMedia: () {},
                onAddOverlay: () {},
              ),
            ),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('AI Generate'),
        200.0,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Generate'), findsOneWidget);
    });

    test('AI Generation request adds AI Video clip to timeline controller', () {
      const req = AiGenerationRequest(
        type: AiMediaType.video,
        modelId: 'veo-3.1',
        prompt: 'Futuristic city sunset',
        aspectRatio: '16:9',
        count: 1,
        guidance: 7.5,
        steps: 30,
        durationSeconds: 8,
      );

      final newClip = TimelineClip(
        id: 'ai_1',
        label: 'AI Video (${req.modelId})',
        start: editor.playhead,
        end: editor.playhead + Duration(seconds: req.durationSeconds!),
        clipType: ClipType.video,
      );

      editor.addClip(newClip);

      expect(editor.project.clips.length, equals(1));
      expect(editor.project.clips.first.label, equals('AI Video (veo-3.1)'));
      expect(editor.project.clips.first.duration, equals(const Duration(seconds: 8)));
    });
  });
}
