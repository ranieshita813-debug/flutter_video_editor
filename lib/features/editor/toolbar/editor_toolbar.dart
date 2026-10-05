import 'package:flutter/material.dart';

import 'package:flutter_video_editor/features/editor/widgets/audio_tools_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_settings_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_tracking_panel.dart';
import 'package:flutter_video_editor/features/editor/widgets/color_grading_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/crop_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/effects_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/elements_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/keyframe_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/mask_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/plugins_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/stickers_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/text_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/vector_drawing_sheet.dart';

enum ToolCategory { edit, audio, textAndStickers, effects, adjust, ai }

enum EditorTool {
  audio('Audio', Icons.volume_up_outlined, ToolCategory.audio),
  text('Text', Icons.title_rounded, ToolCategory.textAndStickers),
  stickers('Stickers', Icons.emoji_emotions_rounded, ToolCategory.textAndStickers),
  filters('Filters', Icons.filter_vintage_rounded, ToolCategory.effects),
  effects('Effects', Icons.local_fire_department_outlined, ToolCategory.effects),
  adjust('Adjust', Icons.layers_outlined, ToolCategory.adjust),
  crop('Crop', Icons.crop_rounded, ToolCategory.edit),
  speed('Speed', Icons.speed_rounded, ToolCategory.edit),
  elements('Elements', Icons.shape_line_outlined, ToolCategory.textAndStickers),
  draw('Draw', Icons.brush_rounded, ToolCategory.textAndStickers),
  mask('Mask', Icons.masks_outlined, ToolCategory.edit),
  keyframes('Keyframes', Icons.diamond_outlined, ToolCategory.edit),
  camera('Camera', Icons.camera_outlined, ToolCategory.edit),
  track('Track', Icons.center_focus_strong_rounded, ToolCategory.ai),
  plugins('Plug-ins', Icons.extension_outlined, ToolCategory.ai);

  const EditorTool(this.title, this.icon, this.category);
  final String title;
  final IconData icon;
  final ToolCategory category;

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
        EditorTool.keyframes => const KeyframeSheet(),
        EditorTool.camera => const CameraSettingsSheet(),
        EditorTool.track => const CameraTrackingPanel(),
        EditorTool.plugins => const PluginsSheet(),
      };
}
