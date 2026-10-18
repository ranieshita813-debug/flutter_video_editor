import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

class EditorToolbarItem {
  EditorToolbarItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String id;
  final String title;
  final PhosphorIconData icon;
  final VoidCallback onTap;
}

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.onSelectToolSheet,
    required this.onAddMedia,
    required this.onAddOverlay,
  });

  final ValueChanged<String> onSelectToolSheet;
  final VoidCallback onAddMedia;
  final VoidCallback onAddOverlay;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);

    final List<EditorToolbarItem> items = _getToolbarItems(context, editor, clip);

    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: bgToken,
        border: Border(top: BorderSide(color: EditorTokens.border, width: 1)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    item.icon,
                    color: EditorTokens.text.withValues(alpha: 0.9),
                    size: 22.0,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: EditorTokens.text.withValues(alpha: 0.9),
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Ubuntu Sans',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<EditorToolbarItem> _getToolbarItems(
    BuildContext context,
    EditorController editor,
    TimelineClip? clip,
  ) {
    if (clip == null) {
      // Common Global Tools (No clip selected)
      return [
        EditorToolbarItem(
          id: 'add_media',
          title: 'Add Media',
          icon: PhosphorIconsRegular.plus,
          onTap: onAddMedia,
        ),
        EditorToolbarItem(
          id: 'overlay',
          title: 'Overlay',
          icon: PhosphorIconsRegular.squareSplitVertical,
          onTap: onAddOverlay,
        ),
        EditorToolbarItem(
          id: 'text',
          title: 'Text',
          icon: PhosphorIconsRegular.textAa,
          onTap: () => onSelectToolSheet('text'),
        ),
        EditorToolbarItem(
          id: 'audio',
          title: 'Audio',
          icon: PhosphorIconsRegular.speakerHigh,
          onTap: () => onSelectToolSheet('audio'),
        ),
        EditorToolbarItem(
          id: 'adjust',
          title: 'Adjust',
          icon: PhosphorIconsRegular.sliders,
          onTap: () => onSelectToolSheet('adjust'),
        ),
        EditorToolbarItem(
          id: 'effects',
          title: 'Effects',
          icon: PhosphorIconsRegular.magicWand,
          onTap: () => onSelectToolSheet('effects'),
        ),
        EditorToolbarItem(
          id: 'filters',
          title: 'Filters',
          icon: PhosphorIconsRegular.funnel,
          onTap: () => onSelectToolSheet('filters'),
        ),
        EditorToolbarItem(
          id: 'crop',
          title: 'Canvas',
          icon: PhosphorIconsRegular.crop,
          onTap: () => onSelectToolSheet('crop'),
        ),
        EditorToolbarItem(
          id: 'elements',
          title: 'Elements',
          icon: PhosphorIconsRegular.shapes,
          onTap: () => onSelectToolSheet('elements'),
        ),
        EditorToolbarItem(
          id: 'stickers',
          title: 'Stickers',
          icon: PhosphorIconsRegular.smiley,
          onTap: () => onSelectToolSheet('stickers'),
        ),
        EditorToolbarItem(
          id: 'draw',
          title: 'Draw',
          icon: PhosphorIconsRegular.pencilSimple,
          onTap: () => onSelectToolSheet('draw'),
        ),
        EditorToolbarItem(
          id: 'auto_captions',
          title: 'Auto captions',
          icon: PhosphorIconsRegular.closedCaptioning,
          onTap: () => onSelectToolSheet('captions'),
        ),
        EditorToolbarItem(
          id: 'track',
          title: 'Track',
          icon: PhosphorIconsRegular.crosshair,
          onTap: () => onSelectToolSheet('track'),
        ),
        EditorToolbarItem(
          id: 'ai_generate',
          title: 'AI Generate',
          icon: PhosphorIconsFill.sparkle,
          onTap: () => onSelectToolSheet('ai'),
        ),
      ];
    }

    // Clip-Specific Tools based on selectedClip.clipType
    switch (clip.clipType) {
      case ClipType.video:
      case ClipType.image:
        final bool isOverlay = clip.layerIndex > 0;
        return [
          EditorToolbarItem(
            id: 'split',
            title: 'Split',
            icon: PhosphorIconsRegular.scissors,
            onTap: () => editor.splitSelectedClip(),
          ),
          if (isOverlay)
            EditorToolbarItem(
              id: 'chroma_key',
              title: 'Chroma Key',
              icon: PhosphorIconsRegular.eyedropper,
              onTap: () => onSelectToolSheet('chroma_key'),
            ),
          EditorToolbarItem(
            id: 'speed',
            title: 'Speed',
            icon: PhosphorIconsRegular.gauge,
            onTap: () => onSelectToolSheet('speed'),
          ),
          EditorToolbarItem(
            id: 'volume',
            title: 'Volume',
            icon: PhosphorIconsRegular.speakerHigh,
            onTap: () => onSelectToolSheet('audio'),
          ),
          EditorToolbarItem(
            id: 'crop',
            title: 'Canvas',
            icon: PhosphorIconsRegular.crop,
            onTap: () => onSelectToolSheet('crop'),
          ),
          EditorToolbarItem(
            id: 'adjust',
            title: 'Adjust',
            icon: PhosphorIconsRegular.sliders,
            onTap: () => onSelectToolSheet('adjust'),
          ),
          EditorToolbarItem(
            id: 'filters',
            title: 'Filters',
            icon: PhosphorIconsRegular.funnel,
            onTap: () => onSelectToolSheet('filters'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: PhosphorIconsRegular.magicWand,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: PhosphorIconsRegular.play,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'mask',
            title: 'Mask',
            icon: PhosphorIconsRegular.square,
            onTap: () => onSelectToolSheet('mask'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: PhosphorIconsRegular.copy,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: PhosphorIconsRegular.trash,
            onTap: () => editor.removeSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'ai_generate',
            title: 'AI Generate',
            icon: PhosphorIconsFill.sparkle,
            onTap: () => onSelectToolSheet('ai'),
          ),
        ];

      case ClipType.caption:
        return [
          EditorToolbarItem(
            id: 'edit_caption',
            title: 'Edit Caption',
            icon: PhosphorIconsRegular.pencilSimple,
            onTap: () => onSelectToolSheet('text'),
          ),
          EditorToolbarItem(
            id: 'translate_captions',
            title: 'Translate',
            icon: PhosphorIconsRegular.translate,
            onTap: () => onSelectToolSheet('caption_translate'),
          ),
          EditorToolbarItem(
            id: 'caption_highlight',
            title: 'Highlight',
            icon: PhosphorIconsRegular.highlighterCircle,
            onTap: () => onSelectToolSheet('captions_style'),
          ),
          EditorToolbarItem(
            id: 'split',
            title: 'Split',
            icon: PhosphorIconsRegular.scissors,
            onTap: () => editor.splitSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'auto_captions',
            title: 'Auto captions',
            icon: PhosphorIconsRegular.closedCaptioning,
            onTap: () => onSelectToolSheet('captions'),
          ),
          EditorToolbarItem(
            id: 'text_style',
            title: 'Text Style',
            icon: PhosphorIconsRegular.textAa,
            onTap: () => onSelectToolSheet('text_style'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: PhosphorIconsRegular.magicWand,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: PhosphorIconsRegular.play,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: PhosphorIconsRegular.copy,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: PhosphorIconsRegular.trash,
            onTap: () => editor.removeSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'ai_generate',
            title: 'AI Generate',
            icon: PhosphorIconsFill.sparkle,
            onTap: () => onSelectToolSheet('ai'),
          ),
        ];

      case ClipType.text:
        return [
          EditorToolbarItem(
            id: 'text_style',
            title: 'Text Style',
            icon: PhosphorIconsRegular.textAa,
            onTap: () => onSelectToolSheet('text_style'),
          ),
          EditorToolbarItem(
            id: 'edit_text',
            title: 'Edit Text',
            icon: PhosphorIconsRegular.pencilSimple,
            onTap: () => onSelectToolSheet('text'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: PhosphorIconsRegular.magicWand,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: PhosphorIconsRegular.play,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: PhosphorIconsRegular.copy,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: PhosphorIconsRegular.trash,
            onTap: () => editor.removeSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'ai_generate',
            title: 'AI Generate',
            icon: PhosphorIconsFill.sparkle,
            onTap: () => onSelectToolSheet('ai'),
          ),
        ];

      case ClipType.audio:
        return [
          EditorToolbarItem(
            id: 'split',
            title: 'Split',
            icon: PhosphorIconsRegular.scissors,
            onTap: () => editor.splitSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'volume',
            title: 'Volume',
            icon: PhosphorIconsRegular.speakerHigh,
            onTap: () => onSelectToolSheet('audio'),
          ),
          EditorToolbarItem(
            id: 'speed',
            title: 'Speed',
            icon: PhosphorIconsRegular.gauge,
            onTap: () => onSelectToolSheet('speed'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: PhosphorIconsRegular.magicWand,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: PhosphorIconsRegular.copy,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: PhosphorIconsRegular.trash,
            onTap: () => editor.removeSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'ai_generate',
            title: 'AI Generate',
            icon: PhosphorIconsFill.sparkle,
            onTap: () => onSelectToolSheet('ai'),
          ),
        ];

      default:
        return [
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: PhosphorIconsRegular.magicWand,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: PhosphorIconsRegular.play,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: PhosphorIconsRegular.copy,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: PhosphorIconsRegular.trash,
            onTap: () => editor.removeSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'ai_generate',
            title: 'AI Generate',
            icon: PhosphorIconsFill.sparkle,
            onTap: () => onSelectToolSheet('ai'),
          ),
        ];
    }
  }
}
