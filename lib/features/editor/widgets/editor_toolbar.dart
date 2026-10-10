import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class EditorToolbarItem {
  const EditorToolbarItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String id;
  final String title;
  final dynamic icon;
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
      height: 64,
      decoration: const BoxDecoration(
        color: EditorTokens.bg,
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
                  HugeIcon(
                    icon: item.icon,
                    color: EditorTokens.text,
                    size: 20.0,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: EditorTokens.text,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
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
          icon: HugeIcons.strokeRoundedAdd01,
          onTap: onAddMedia,
        ),
        EditorToolbarItem(
          id: 'overlay',
          title: 'Overlay',
          icon: HugeIcons.strokeRoundedLayers01,
          onTap: onAddOverlay,
        ),
        EditorToolbarItem(
          id: 'text',
          title: 'Text',
          icon: HugeIcons.strokeRoundedTextFont,
          onTap: () => onSelectToolSheet('text'),
        ),
        EditorToolbarItem(
          id: 'audio',
          title: 'Audio',
          icon: HugeIcons.strokeRoundedVolumeHigh,
          onTap: () => onSelectToolSheet('audio'),
        ),
        EditorToolbarItem(
          id: 'adjust',
          title: 'Adjust',
          icon: HugeIcons.strokeRoundedLayers01,
          onTap: () => onSelectToolSheet('adjust'),
        ),
        EditorToolbarItem(
          id: 'effects',
          title: 'Effects',
          icon: HugeIcons.strokeRoundedMagicWand01,
          onTap: () => onSelectToolSheet('effects'),
        ),
        EditorToolbarItem(
          id: 'filters',
          title: 'Filters',
          icon: HugeIcons.strokeRoundedFilter,
          onTap: () => onSelectToolSheet('filters'),
        ),
        EditorToolbarItem(
          id: 'crop',
          title: 'Canvas',
          icon: HugeIcons.strokeRoundedCrop,
          onTap: () => onSelectToolSheet('crop'),
        ),
        EditorToolbarItem(
          id: 'elements',
          title: 'Elements',
          icon: HugeIcons.strokeRoundedShapes,
          onTap: () => onSelectToolSheet('elements'),
        ),
        EditorToolbarItem(
          id: 'stickers',
          title: 'Stickers',
          icon: HugeIcons.strokeRoundedSmile,
          onTap: () => onSelectToolSheet('stickers'),
        ),
        EditorToolbarItem(
          id: 'draw',
          title: 'Draw',
          icon: HugeIcons.strokeRoundedPencilEdit02,
          onTap: () => onSelectToolSheet('draw'),
        ),
        EditorToolbarItem(
          id: 'auto_captions',
          title: 'Auto captions',
          icon: HugeIcons.strokeRoundedTextFont,
          onTap: () => editor.generateAutoCaptions(),
        ),
        EditorToolbarItem(
          id: 'track',
          title: 'Track',
          icon: HugeIcons.strokeRoundedTarget01,
          onTap: () => onSelectToolSheet('track'),
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
            icon: HugeIcons.strokeRoundedScissors,
            onTap: () => editor.splitSelectedClip(),
          ),
          if (isOverlay)
            EditorToolbarItem(
              id: 'chroma_key',
              title: 'Chroma Key',
              icon: HugeIcons.strokeRoundedFilter,
              onTap: () => onSelectToolSheet('chroma_key'),
            ),
          EditorToolbarItem(
            id: 'speed',
            title: 'Speed',
            icon: HugeIcons.strokeRoundedTime01,
            onTap: () => onSelectToolSheet('speed'),
          ),
          EditorToolbarItem(
            id: 'volume',
            title: 'Volume',
            icon: HugeIcons.strokeRoundedVolumeHigh,
            onTap: () => onSelectToolSheet('audio'),
          ),
          EditorToolbarItem(
            id: 'crop',
            title: 'Canvas',
            icon: HugeIcons.strokeRoundedCrop,
            onTap: () => onSelectToolSheet('crop'),
          ),
          EditorToolbarItem(
            id: 'adjust',
            title: 'Adjust',
            icon: HugeIcons.strokeRoundedLayers01,
            onTap: () => onSelectToolSheet('adjust'),
          ),
          EditorToolbarItem(
            id: 'filters',
            title: 'Filters',
            icon: HugeIcons.strokeRoundedFilter,
            onTap: () => onSelectToolSheet('filters'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: HugeIcons.strokeRoundedMagicWand01,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: HugeIcons.strokeRoundedPlay,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'mask',
            title: 'Mask',
            icon: HugeIcons.strokeRoundedSquare,
            onTap: () => onSelectToolSheet('mask'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: HugeIcons.strokeRoundedCopy01,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: HugeIcons.strokeRoundedDelete02,
            onTap: () => editor.removeSelectedClip(),
          ),
        ];

      case ClipType.text:
      case ClipType.caption:
        return [
          EditorToolbarItem(
            id: 'text_style',
            title: 'Text Style',
            icon: HugeIcons.strokeRoundedTextFont,
            onTap: () => onSelectToolSheet('text_style'),
          ),
          EditorToolbarItem(
            id: 'edit_text',
            title: 'Edit Text',
            icon: HugeIcons.strokeRoundedPencilEdit02,
            onTap: () => onSelectToolSheet('text'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: HugeIcons.strokeRoundedMagicWand01,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: HugeIcons.strokeRoundedPlay,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: HugeIcons.strokeRoundedCopy01,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: HugeIcons.strokeRoundedDelete02,
            onTap: () => editor.removeSelectedClip(),
          ),
        ];

      case ClipType.audio:
        return [
          EditorToolbarItem(
            id: 'split',
            title: 'Split',
            icon: HugeIcons.strokeRoundedScissors,
            onTap: () => editor.splitSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'volume',
            title: 'Volume',
            icon: HugeIcons.strokeRoundedVolumeHigh,
            onTap: () => onSelectToolSheet('audio'),
          ),
          EditorToolbarItem(
            id: 'speed',
            title: 'Speed',
            icon: HugeIcons.strokeRoundedTime01,
            onTap: () => onSelectToolSheet('speed'),
          ),
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: HugeIcons.strokeRoundedMagicWand01,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: HugeIcons.strokeRoundedCopy01,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: HugeIcons.strokeRoundedDelete02,
            onTap: () => editor.removeSelectedClip(),
          ),
        ];

      default:
        return [
          EditorToolbarItem(
            id: 'effects',
            title: 'Effects',
            icon: HugeIcons.strokeRoundedMagicWand01,
            onTap: () => onSelectToolSheet('effects'),
          ),
          EditorToolbarItem(
            id: 'animation',
            title: 'Animation',
            icon: HugeIcons.strokeRoundedPlay,
            onTap: () => onSelectToolSheet('animation'),
          ),
          EditorToolbarItem(
            id: 'duplicate',
            title: 'Duplicate',
            icon: HugeIcons.strokeRoundedCopy01,
            onTap: () => editor.duplicateSelectedClip(),
          ),
          EditorToolbarItem(
            id: 'delete',
            title: 'Delete',
            icon: HugeIcons.strokeRoundedDelete02,
            onTap: () => editor.removeSelectedClip(),
          ),
        ];
    }
  }
}
