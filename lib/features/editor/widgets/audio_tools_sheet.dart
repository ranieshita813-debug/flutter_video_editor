import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);

class AudioToolsSheet extends StatefulWidget {
  const AudioToolsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
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
  late double noiseReduction;
  late String voiceEffect;

  final List<String> eqPresets = const <String>[
    'Flat',
    'Bass Boost',
    'Vocal Booster',
    'Pop',
    'Rock',
    'Electronic',
  ];

  final List<String> voiceEffects = const <String>[
    'Normal',
    'Deep',
    'Chipmunk',
    'Robot',
    'Echo',
    'Megaphone',
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
    noiseReduction = props.noiseReduction;
    voiceEffect = props.voiceEffect;
  }

  void _update(EditorController controller) {
    controller.updateAudioProperties(
      AudioProperties(
        volume: volume,
        speed: speed,
        pitch: pitch,
        equalizerPreset: equalizerPreset,
        noiseReduction: noiseReduction,
        voiceEffect: voiceEffect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text(
                  'Audio Studio & Multi-Track',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _track),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedMusic01, size: 18),
                    label: const Text('Add Track'),
                    onPressed: () {
                      controller.addAudioTrack(
                        'Track ${controller.clips.where((c) => c.clipType == ClipType.audio).length + 1}',
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedText, size: 18),
                    label: const Text('Auto Captions'),
                    onPressed: () {
                      controller.generateAutoCaptions();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sliderTile('Volume', '${(volume * 100).round()}%', volume, 0.0,
                2.0, (val) {
              setState(() => volume = val);
              _update(controller);
            }),
            _sliderTile('Speed', '${speed.toStringAsFixed(2)}x', speed, 0.25,
                3.0, (val) {
              setState(() => speed = val);
              _update(controller);
            }),
            _sliderTile('Pitch', '${pitch.toStringAsFixed(2)}x', pitch, 0.5,
                2.0, (val) {
              setState(() => pitch = val);
              _update(controller);
            }),
            _sliderTile('Noise Reduction', '${(noiseReduction * 100).round()}%',
                noiseReduction, 0.0, 1.0, (val) {
              setState(() => noiseReduction = val);
              _update(controller);
            }),
            const SizedBox(height: 12),
            const Text('Equalizer Preset',
                style: TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: eqPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final preset = eqPresets[index];
                  final isSelected = equalizerPreset == preset;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => equalizerPreset = preset);
                      _update(controller);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _track),
                      ),
                      child: Text(
                        preset,
                        style: TextStyle(
                          color: isSelected ? Colors.black : _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('Voice FX Changer',
                style: TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: voiceEffects.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final fx = voiceEffects[index];
                  final isSelected = voiceEffect == fx;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => voiceEffect = fx);
                      _update(controller);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _track),
                      ),
                      child: Text(
                        fx,
                        style: TextStyle(
                          color: isSelected ? Colors.black : _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile(
    String label,
    String valueText,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: const TextStyle(color: _text, fontSize: 13)),
              const Spacer(),
              Text(valueText,
                  style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: _track,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
