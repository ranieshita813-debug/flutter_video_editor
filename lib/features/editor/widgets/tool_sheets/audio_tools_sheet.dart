import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/audio_waveform.dart';

class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  Widget _styleOption(
    BuildContext context, {
    required WaveStyle style,
    required String label,
    required dynamic icon,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          waveStyle.value = style;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? EditorTokens.text : EditorTokens.elevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? EditorTokens.text : EditorTokens.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: icon,
                color: isSelected ? EditorTokens.bg : EditorTokens.text,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? EditorTokens.bg : EditorTokens.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    final bool hasAudio = clip != null &&
        (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final double volume = clip?.volume ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Waveform Style',
          style: TextStyle(
            color: EditorTokens.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<WaveStyle>(
          valueListenable: waveStyle,
          builder: (context, currentStyle, _) {
            return Row(
              children: [
                _styleOption(
                  context,
                  style: WaveStyle.peakRms,
                  label: 'Peak + RMS',
                  icon: HugeIcons.strokeRoundedAudioWave01,
                  isSelected: currentStyle == WaveStyle.peakRms,
                ),
                const SizedBox(width: 8),
                _styleOption(
                  context,
                  style: WaveStyle.classic,
                  label: 'Classic',
                  icon: HugeIcons.strokeRoundedAudioLines,
                  isSelected: currentStyle == WaveStyle.classic,
                ),
                const SizedBox(width: 8),
                _styleOption(
                  context,
                  style: WaveStyle.bars,
                  label: 'Bars',
                  icon: HugeIcons.strokeRoundedAudioWave02,
                  isSelected: currentStyle == WaveStyle.bars,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EditorTokens.elevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: EditorTokens.border),
          ),
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedMusicNote01,
                color: EditorTokens.text,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Audio Track',
                      style: TextStyle(
                        color: EditorTokens.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Insert soundtrack clip to timeline',
                      style: TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 11,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTokens.text,
                  foregroundColor: EditorTokens.bg,
                ),
                onPressed: () {
                  editor.addAudioTrack(
                    'Track ${editor.clips.where((c) => c.clipType == ClipType.audio).length + 1}',
                  );
                },
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: EditorTokens.bg,
                  size: 16,
                ),
                label: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                ),
              ),
            ],
          ),
        ),
        if (hasAudio) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EditorTokens.elevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: EditorTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Volume',
                      style: TextStyle(
                        color: EditorTokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      '${(volume * 100).round()}%',
                      style: const TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: EditorTokens.text,
                    inactiveTrackColor: EditorTokens.border,
                    thumbColor: EditorTokens.text,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: volume.clamp(0.0, 2.0),
                    min: 0.0,
                    max: 2.0,
                    onChanged: (val) {
                      editor.updateAudioProperties(
                        AudioProperties(
                          volume: val,
                          speed: clip.speed,
                          fadeIn: clip.audioProperties.fadeIn,
                          fadeOut: clip.audioProperties.fadeOut,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
