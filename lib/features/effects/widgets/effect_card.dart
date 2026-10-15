import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class EffectCard extends StatelessWidget {
  const EffectCard({
    super.key,
    required this.effect,
    required this.onTap,
    this.isSelected = false,
    this.onToggleFavorite,
    this.onDownload,
    this.downloadProgress,
  });

  final ShaderEffect effect;
  final VoidCallback onTap;
  final bool isSelected;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onDownload;
  final double? downloadProgress;

  @override
  Widget build(BuildContext context) {
    final bool isDownloading = downloadProgress != null && downloadProgress! > 0 && downloadProgress! < 1;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? EditorTokens.elevated : EditorTokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? EditorTokens.text : EditorTokens.border,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: EditorTokens.text.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: EditorTokens.elevated,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(
                            _getCategoryIcon(effect.category),
                            color: isSelected ? EditorTokens.text : EditorTokens.muted,
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            effect.category.displayName,
                            style: const TextStyle(
                              color: EditorTokens.faint,
                              fontSize: 9,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onToggleFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: EditorTokens.bg,
                          shape: BoxShape.circle,
                        ),
                        child: FaIcon(
                          effect.isFavorite
                              ? FontAwesomeIcons.solidHeart
                              : FontAwesomeIcons.heart,
                          color: effect.isFavorite ? Colors.redAccent : EditorTokens.muted,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                  if (effect.type != EffectType.builtIn)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EditorTokens.bg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: EditorTokens.border, width: 0.5),
                        ),
                        child: Text(
                          effect.type == EffectType.downloadable ? 'STORE' : 'CUSTOM',
                          style: const TextStyle(
                            color: EditorTokens.accent,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  if (!effect.isDownloaded)
                    Positioned.fill(
                      child: Container(
                        color: EditorTokens.bg.withValues(alpha: 0.6),
                        child: Center(
                          child: isDownloading
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    value: downloadProgress,
                                    strokeWidth: 2,
                                    color: EditorTokens.text,
                                  ),
                                )
                              : GestureDetector(
                                  onTap: onDownload,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: EditorTokens.text,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const FaIcon(
                                      FontAwesomeIcons.download,
                                      color: EditorTokens.bg,
                                      size: 14,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    effect.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? EditorTokens.text : EditorTokens.text.withValues(alpha: 0.87),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    effect.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 9,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  FaIconData _getCategoryIcon(ShaderEffectCategory cat) {
    switch (cat) {
      case ShaderEffectCategory.glow:
      case ShaderEffectCategory.neon:
        return FontAwesomeIcons.bolt;
      case ShaderEffectCategory.blur:
        return FontAwesomeIcons.filter;
      case ShaderEffectCategory.cinematic:
        return FontAwesomeIcons.video;
      case ShaderEffectCategory.vintage:
        return FontAwesomeIcons.clock;
      case ShaderEffectCategory.noir:
        return FontAwesomeIcons.moon;
      case ShaderEffectCategory.glitch:
        return FontAwesomeIcons.sliders;
      case ShaderEffectCategory.bloom:
      case ShaderEffectCategory.lightLeak:
        return FontAwesomeIcons.sun;
      case ShaderEffectCategory.distortion:
        return FontAwesomeIcons.wandMagicSparkles;
      case ShaderEffectCategory.colorStyle:
      case ShaderEffectCategory.all:
        return FontAwesomeIcons.palette;
    }
  }
}
