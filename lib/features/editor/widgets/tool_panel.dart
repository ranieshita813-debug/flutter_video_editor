import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/order_tool_view.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/clip_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/text_style_sheet.dart';

// ----------------------------------------------------------------------------
// Inline tools enum
// ----------------------------------------------------------------------------
enum EditorTool {
  audio('Audio', HugeIcons.strokeRoundedVolumeHigh),
  text('Text', HugeIcons.strokeRoundedTextFont),
  stickers('Stickers', HugeIcons.strokeRoundedSmile),
  filters('Filters', HugeIcons.strokeRoundedFilter),
  effects('Effects', HugeIcons.strokeRoundedMagicWand01),
  adjust('Adjust', HugeIcons.strokeRoundedLayers01),
  crop('Canvas', HugeIcons.strokeRoundedCrop),
  speed('Speed', HugeIcons.strokeRoundedTime01),
  elements('Elements', HugeIcons.strokeRoundedShapes),
  draw('Draw', HugeIcons.strokeRoundedPencilEdit02),
  mask('Mask', HugeIcons.strokeRoundedSquare),
  camera('Camera', HugeIcons.strokeRoundedCamera01),
  track('Track', HugeIcons.strokeRoundedTarget01),
  plugins('Plug-ins', HugeIcons.strokeRoundedGridView),
  textStyle('Text Style', HugeIcons.strokeRoundedTextFont),
  animation('Animation', HugeIcons.strokeRoundedPlay),
  order('Order', HugeIcons.strokeRoundedArrowUpDown);

  const EditorTool(this.title, this.icon);
  final String title;
  final dynamic icon;

  Widget get body => switch (this) {
        EditorTool.audio => const AudioToolsSheet(),
        EditorTool.text => const TextAnimationSheet(),
        EditorTool.stickers => const StickersSheet(),
        EditorTool.filters => const EffectsSheet(isFilterMode: true),
        EditorTool.effects => const EffectsSheet(isFilterMode: false),
        EditorTool.adjust => const ColorGradingSheet(),
        EditorTool.crop => const CropSheet(),
        EditorTool.speed => const SpeedSheet(),
        EditorTool.elements => const ElementsSheet(),
        EditorTool.draw => const VectorDrawingSheet(),
        EditorTool.mask => const MaskSheet(),
        EditorTool.camera => const CameraSettingsSheet(),
        EditorTool.track => const CameraTrackingPanel(),
        EditorTool.plugins => const PluginsSheet(),
        EditorTool.textStyle => const TextStyleSheet(),
        EditorTool.animation => const ClipAnimationSheet(),
        EditorTool.order => const OrderToolView(),
      };
}

class ToolPanel extends StatelessWidget {
  const ToolPanel({
    super.key,
    required this.tool,
    required this.onClose,
    this.height,
    this.docked = false,
    this.onResize,
    this.onDrag,
  });
  final EditorTool tool;
  final double? height;
  final bool docked;
  final VoidCallback onClose;
  final ValueChanged<double>? onResize;
  final ValueChanged<bool>? onDrag;

  Widget _header() => Row(
        children: <Widget>[
          const SizedBox(width: 16),
          HugeIcon(icon: tool.icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Done',
            icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedTick01, color: Colors.white, size: 22),
            onPressed: () {
              tapFeedback();
              onClose();
            },
          ),
          const SizedBox(width: 4),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final Widget body = Expanded(
      child: ClipRect(
        child: Material(type: MaterialType.transparency, child: tool.body),
      ),
    );

    if (docked) {
      return Container(
        decoration: const BoxDecoration(
          color: surfaceToken,
          border: Border(left: BorderSide(color: dividerToken)),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: <Widget>[
              SizedBox(height: 52, child: _header()),
              const Divider(height: 1, thickness: 0.5, color: dividerToken),
              body,
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: surfaceToken,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: dividerToken)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onDrag?.call(true),
                onVerticalDragUpdate: (d) => onResize?.call(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag?.call(false),
                onVerticalDragCancel: () => onDrag?.call(false),
                child: SizedBox(
                  height: 52,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      Expanded(child: _header()),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: dividerToken),
              body,
            ],
          ),
        ),
      ),
    );
  }
}