import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/effects/services/effect_preview_service.dart';

class EffectPreviewWidget extends StatelessWidget {
  const EffectPreviewWidget({
    super.key,
    required this.effect,
    required this.clip,
    this.playheadTime = Duration.zero,
    this.width = double.infinity,
    this.height = 200,
    this.child,
  });

  final ShaderEffect effect;
  final ShaderEffectClip clip;
  final Duration playheadTime;
  final double width;
  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final clipRelativeTime = playheadTime - clip.start;
    final activeParameters = clip.getInterpolatedParameters(clipRelativeTime);

    final Widget previewBase = child ??
        Container(
          color: EditorTokens.elevated,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/placeholder.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF1E2028),
                  child: const Center(
                    child: Text(
                      'PREVIEW FRAME',
                      style: TextStyle(
                        color: EditorTokens.faint,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EditorTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EditorTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FlutterShaderPreviewRenderer.applyShaderEffect(
            child: previewBase,
            clip: clip,
            parameters: activeParameters,
            playheadTime: playheadTime,
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EditorTokens.bg.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EditorTokens.border, width: 0.5),
              ),
              child: Text(
                effect.name.toUpperCase(),
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
