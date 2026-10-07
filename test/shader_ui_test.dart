import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_card.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_parameter_panel.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_timeline_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testEffect = ShaderEffect(
    id: 'neon_glow',
    name: 'Neon Glow',
    description: 'Vibrant neon edges',
    category: ShaderEffectCategory.glow,
    parameters: [
      ShaderParameter(
        id: 'intensity',
        name: 'intensity',
        label: 'Intensity',
        type: ParameterType.float,
        value: 0.8,
        defaultValue: 1.0,
      ),
    ],
  );

  const testClip = ShaderEffectClip(
    id: 'clip_fx_1',
    effectId: 'neon_glow',
    name: 'Neon Glow',
    start: Duration.zero,
    end: Duration(seconds: 5),
    parameterValues: {'intensity': 0.8},
  );

  testWidgets('EffectCard renders name and description', (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectCard(
            effect: testEffect,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Neon Glow'), findsOneWidget);
    expect(find.text('Vibrant neon edges'), findsOneWidget);

    await tester.tap(find.text('Neon Glow'));
    expect(tapped, isTrue);
  });

  testWidgets('EffectParameterPanel renders parameter controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectParameterPanel(
            effect: testEffect,
            clip: testClip,
            onParameterChanged: (_, __) {},
            onAddKeyframe: (_, __, ___) {},
            onRemoveKeyframe: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.text('Neon Glow Controls'), findsOneWidget);
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('EffectTimelineChip renders name and badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectTimelineChip(
            effectClip: testClip,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Neon Glow'), findsOneWidget);
  });
}
