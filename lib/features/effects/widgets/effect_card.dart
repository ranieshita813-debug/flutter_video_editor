import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
                          PhosphorIcon(
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
                              fontFamily: 'Ubuntu',
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
                        child: PhosphorIcon(
                          effect.isFavorite
                              ? PhosphorIconsFill.heart
                              : PhosphorIconsRegular.heart,
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
                            fontFamily: 'Ubuntu',
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
                                    child: const PhosphorIcon(
                                      PhosphorIconsRegular.download,
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
                      fontFamily: 'Ubuntu',
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
                      fontFamily: 'Ubuntu',
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

  PhosphorIconData _getCategoryIcon(ShaderEffectCategory cat) {
    switch (cat) {
      case ShaderEffectCategory.glow:
      case ShaderEffectCategory.neon:
        return PhosphorIconsRegular.lightning;
      case ShaderEffectCategory.blur:
        return PhosphorIconsRegular.funnel;
      case ShaderEffectCategory.cinematic:
        return PhosphorIconsRegular.videoCamera;
      case ShaderEffectCategory.vintage:
        return PhosphorIconsRegular.clock;
      case ShaderEffectCategory.noir:
        return PhosphorIconsRegular.moon;
      case ShaderEffectCategory.glitch:
        return PhosphorIconsRegular.sliders;
      case ShaderEffectCategory.bloom:
      case ShaderEffectCategory.lightLeak:
        return PhosphorIconsRegular.sun;
      case ShaderEffectCategory.distortion:
        return PhosphorIconsRegular.magicWand;
      case ShaderEffectCategory.colorStyle:
      case ShaderEffectCategory.all:
        return PhosphorIconsRegular.palette;
    }
  }
}
