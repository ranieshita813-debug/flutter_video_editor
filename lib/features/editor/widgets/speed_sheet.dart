import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class SpeedSheet extends StatefulWidget {
  const SpeedSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SpeedSheet(),
    );
  }

  @override
  State<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<SpeedSheet> {
  late double speed;

  final List<double> presets = const <double>[0.25, 0.5, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  @override
  void initState() {
    super.initState();
    final clip = context.read<EditorController>().selectedClip;
    speed = clip?.speed ?? 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Playback Speed',
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${speed.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF22D3EE),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: speed,
              min: 0.25,
              max: 4.0,
              activeColor: const Color(0xFF7C5CFF),
              onChanged: (val) {
                setState(() => speed = val);
                controller.updateAudioProperties(
                  controller.selectedClip?.audioProperties.copyWith(speed: speed) ??
                      const AudioProperties(),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: presets.map((p) {
                final isSel = (p - speed).abs() < 0.05;
                return ChoiceChip(
                  label: Text('${p}x'),
                  selected: isSel,
                  selectedColor: const Color(0xFF7C5CFF),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => speed = p);
                      controller.updateAudioProperties(
                        controller.selectedClip?.audioProperties.copyWith(speed: speed) ??
                            const AudioProperties(),
                      );
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
