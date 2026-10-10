import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final bool hasAudio = clip != null &&
        (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final double volume = clip?.volume ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.audio,
                      allowMultiple: false,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      final file = result.files.single;
                      if (file.path != null) {
                        editor.addAudioTrack(file.path!, trackName: file.name);
                      }
                    }
                  } catch (_) {}
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
                        AudioProperties(volume: val, speed: clip.speed),
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
