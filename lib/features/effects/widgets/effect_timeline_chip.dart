import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class EffectTimelineChip extends StatelessWidget {
  const EffectTimelineChip({
    super.key,
    required this.effectClip,
    required this.onTap,
    this.isSelected = false,
    this.onToggleEnabled,
    this.onRemove,
  });

  final ShaderEffectClip effectClip;
  final VoidCallback onTap;
  final bool isSelected;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? EditorTokens.elevated : EditorTokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? EditorTokens.text : EditorTokens.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onToggleEnabled,
              child: HugeIcon(
                icon: effectClip.isEnabled
                    ? HugeIcons.strokeRoundedMagicWand01
                    : HugeIcons.strokeRoundedViewOff,
                color: effectClip.isEnabled ? EditorTokens.accent : EditorTokens.muted,
                size: 14,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              effectClip.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effectClip.isEnabled
                    ? EditorTokens.text
                    : EditorTokens.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            if (effectClip.keyframeAnimations.isNotEmpty) ...[
              const SizedBox(width: 6),
              const HugeIcon(
                icon: HugeIcons.strokeRoundedBookmark02,
                color: EditorTokens.accent,
                size: 12,
              ),
            ],
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: EditorTokens.muted,
                  size: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
