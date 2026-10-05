import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class AudioToolsSheet extends StatefulWidget {
  const AudioToolsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AudioToolsSheet(),
    );
  }

  @override
  State<AudioToolsSheet> createState() => _AudioToolsSheetState();
}

class _AudioToolsSheetState extends State<AudioToolsSheet> {
  late double volume;
  late double speed;
  late double pitch;
  late String equalizerPreset;

  final List<String> eqPresets = const <String>[
    'Flat',
    'Bass Boost',
    'Vocal Booster',
    'Pop',
    'Rock',
    'Electronic',
  ];

  @override
  void initState() {
    super.initState();
    final controller = context.read<EditorController>();
    final clip = controller.selectedClip;
    final props = clip?.audioProperties ?? const AudioProperties();
    volume = props.volume;
    speed = props.speed;
    pitch = props.pitch;
    equalizerPreset = props.equalizerPreset;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Audio Studio & Multi-Track',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                OutlinedButton.icon(
                  icon: const Icon(Icons.music_note, color: Colors.greenAccent),
                  label: const Text('Add Audio Track', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    controller.addAudioTrack('Soundtrack Track ${controller.clips.where((c) => c.clipType == ClipType.audio).length + 1}');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Audio track added to timeline!'), backgroundColor: Colors.green),
                    );
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.subtitles, size: 18),
                  label: const Text('Auto Captions Generator'),
                  onPressed: () {
                    controller.generateAutoCaptions();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Auto Captions generated and synced to timeline!'),
                        backgroundColor: Color(0xFF8B5CF6),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Audio Controls', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Volume', style: TextStyle(color: Colors.white70))),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 2.0,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) {
                      setState(() => volume = val);
                      _update(controller);
                    },
                  ),
                ),
                Text('${(volume * 100).round()}%', style: const TextStyle(color: Colors.white)),
              ],
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Speed', style: TextStyle(color: Colors.white70))),
                Expanded(
                  child: Slider(
                    value: speed,
                    min: 0.25,
                    max: 3.0,
                    activeColor: Colors.lightBlueAccent,
                    onChanged: (val) {
                      setState(() => speed = val);
                      _update(controller);
                    },
                  ),
                ),
                Text('${speed.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white)),
              ],
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Pitch', style: TextStyle(color: Colors.white70))),
                Expanded(
                  child: Slider(
                    value: pitch,
                    min: 0.5,
                    max: 2.0,
                    activeColor: Colors.amberAccent,
                    onChanged: (val) {
                      setState(() => pitch = val);
                      _update(controller);
                    },
                  ),
                ),
                Text('${pitch.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Equalizer Preset', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: eqPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final preset = eqPresets[index];
                  final isSelected = equalizerPreset == preset;
                  return ChoiceChip(
                    label: Text(preset),
                    selected: isSelected,
                    selectedColor: Colors.greenAccent.shade700,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          equalizerPreset = preset;
                        });
                        _update(controller);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _update(EditorController controller) {
    controller.updateAudioProperties(
      AudioProperties(
        volume: volume,
        speed: speed,
        pitch: pitch,
        equalizerPreset: equalizerPreset,
      ),
    );
  }
}
