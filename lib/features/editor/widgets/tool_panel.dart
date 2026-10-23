import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/widgets/chroma_key_sheet.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/captions_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/order_tool_view.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/elements_sheet.dart';

import 'package:flutter_video_editor/features/editor/widgets/adjustments_sheet.dart';

import 'package:flutter_video_editor/core/services/ai_generation_service.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/ai/gen.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/ai/captions_style.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/clip_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/object_tracking_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/text_style_sheet.dart';

// ----------------------------------------------------------------------------
// Inline tools enum
// ----------------------------------------------------------------------------
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/text_to_speech_sheet.dart';

enum EditorTool {
  audio('Audio', PhosphorIconsRegular.speakerHigh),
  text('Text', PhosphorIconsRegular.textAa),
  textToSpeech('Text to Speech', PhosphorIconsRegular.waveSquare),
  stickers('Stickers', PhosphorIconsRegular.smiley),
  filters('Filters', PhosphorIconsRegular.funnel),
  effects('Effects', PhosphorIconsRegular.magicWand),
  adjust('Adjust', PhosphorIconsRegular.sliders),
  crop('Canvas', PhosphorIconsRegular.crop),
  speed('Speed', PhosphorIconsRegular.gauge),
  elements('Elements', PhosphorIconsRegular.shapes),
  draw('Draw', PhosphorIconsRegular.pencilSimple),
  mask('Mask', PhosphorIconsRegular.square),
  camera('Camera', PhosphorIconsRegular.camera),
  track('Track', PhosphorIconsRegular.crosshair),
  textStyle('Text Style', PhosphorIconsRegular.textAa),
  animation('Animation', PhosphorIconsRegular.play),
  order('Order', PhosphorIconsRegular.sortAscending),
  chromaKey('Chroma Key', PhosphorIconsRegular.eyedropper),
  captions('Captions', PhosphorIconsRegular.closedCaptioning),
  captionsTranslate('Translate', PhosphorIconsRegular.translate),
  captionsStyle('Highlight Style', PhosphorIconsRegular.paintBucket),
  ai('AI Generate', PhosphorIconsFill.sparkle);

  const EditorTool(this.title, this.icon);
  final String title;
  final PhosphorIconData icon;

  Widget get body => switch (this) {
        EditorTool.audio => const AudioToolsSheet(),
        EditorTool.text => const TextAnimationSheet(),
        EditorTool.textToSpeech => const TextToSpeechSheet(),
        EditorTool.stickers => const StickersSheet(),
        EditorTool.filters => const EffectsSheet(isFilterMode: true),
        EditorTool.effects => const EffectsSheet(isFilterMode: false),
        EditorTool.adjust => Builder(
            builder: (ctx) {
              final editor = ctx.read<EditorController>();
              final clip = ctx.select<EditorController, TimelineClip?>((e) => e.selectedClip);
              final initialAdj = clip != null
                  ? AdjustSettings.fromColorGrading(clip.colorGrading)
                  : AdjustSettings.identity;

              return AdjustSheet(
                initial: initialAdj,
                onChanged: (settings) {
                  editor.updateColorGrading(settings.toColorGrading());
                },
                onApply: (settings) {
                  editor.updateColorGrading(settings.toColorGrading());
                },
                onClose: () {},
              );
            },
          ),
        EditorTool.crop => const CropSheet(),
        EditorTool.speed => const SpeedSheet(),
        EditorTool.elements => const ElementsSheet(),
        EditorTool.draw => const VectorDrawingSheet(),
        EditorTool.mask => const MaskSheet(),
        EditorTool.camera => const CameraSettingsSheet(),
        EditorTool.track => const ObjectTrackingSheet(),
        EditorTool.textStyle => const TextStyleSheet(),
        EditorTool.animation => const ClipAnimationSheet(),
        EditorTool.order => const OrderToolView(),
        EditorTool.chromaKey => Builder(
            builder: (ctx) {
              final editor = ctx.read<EditorController>();
              final clip = ctx.select<EditorController, TimelineClip?>((e) => e.selectedClip);
              return ChromaKeySheet(
                value: clip?.chromaKey ?? const ChromaKey(),
                onPickColor: () => editor.pickColorFromFrame(),
                onChanged: (k) {
                  if (clip != null) {
                    editor.setChromaKey(clip.id, k);
                  }
                },
              );
            },
          ),
        EditorTool.captions => const CaptionsSheet(),
        EditorTool.captionsTranslate => const CaptionTranslationSheet(),
        EditorTool.captionsStyle => const CaptionStyleSheet(),
        EditorTool.ai => Builder(
            builder: (ctx) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () {
                      final editor = ctx.read<EditorController>();
                      final aiService = AiGenerationService();
                      showAiGenerateSheet(
                        ctx,
                        onGenerate: (AiGenerationRequest request) async {
                          String generatedFilePath;
                          try {
                            generatedFilePath = await aiService.generateMedia(request);
                          } catch (_) {
                            generatedFilePath = request.referenceImagePath ?? 'assets/placeholder.png';
                          }

                          final String id = 'ai_${DateTime.now().millisecondsSinceEpoch}';
                          final bool isVideo = request.type == AiMediaType.video;
                          final int durationSec = request.durationSeconds ?? (isVideo ? 5 : 4);
                          final Duration duration = Duration(seconds: durationSec);
                          final Duration start = editor.getEndOfExistingMediaClips();

                          final TimelineClip newClip = TimelineClip(
                            id: id,
                            label: isVideo ? 'AI Video (${request.modelId})' : 'AI Image (${request.modelId})',
                            start: start,
                            end: start + duration,
                            clipType: isVideo ? ClipType.video : ClipType.image,
                            sourcePath: generatedFilePath,
                          );

                          editor.addClip(newClip);
                          editor.selectClip(newClip.id);
                        },
                      );
                    },
                    icon: const PhosphorIcon(PhosphorIconsFill.sparkle, size: 20),
                    label: const Text(
                      'Open AI Generator',
                      style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Ubuntu Sans'),
                    ),
                  ),
                ),
              );
            },
          ),
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
          tool == EditorTool.textToSpeech
              ? SvgPicture.asset(
                  'assets/icons/text_to_speech.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
                )
              : PhosphorIcon(tool.icon, color: Colors.white70, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Ubuntu Sans')),
          ),
          const SizedBox(width: 16),
        ],
      );

  Widget _buildFooter() => Container(
        height: 56,
        decoration: const BoxDecoration(
          color: bgToken,
          border: Border(top: BorderSide(color: dividerToken)),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Cancel',
              icon: const PhosphorIcon(PhosphorIconsRegular.x, color: Colors.white, size: 22),
              onPressed: () {
                tapFeedback();
                onClose();
              },
            ),
            const Spacer(),
            Text(
              tool.title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Ubuntu Sans'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Apply',
              icon: const PhosphorIcon(PhosphorIconsRegular.check, color: accentToken, size: 24),
              onPressed: () {
                tapFeedback();
                onClose();
              },
            ),
          ],
        ),
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
          color: bgToken,
          border: Border(left: BorderSide(color: dividerToken)),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: <Widget>[
              SizedBox(height: 52, child: _header()),
              const Divider(height: 1, thickness: 0.5, color: dividerToken),
              body,
              _buildFooter(),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: bgToken,
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
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }
}