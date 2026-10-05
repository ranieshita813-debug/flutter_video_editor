import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class ColorGradingSheet extends StatefulWidget {
  const ColorGradingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ColorGradingSheet(),
    );
  }

  @override
  State<ColorGradingSheet> createState() => _ColorGradingSheetState();
}

class _ColorGradingSheetState extends State<ColorGradingSheet> {
  late double brightness;
  late double contrast;
  late double saturation;
  late double temperature;
  late double vignette;
  late VideoEffect currentEffect;

  @override
  void initState() {
    super.initState();
    final controller = context.read<EditorController>();
    final clip = controller.selectedClip;
    final colorSettings = clip?.colorGrading ?? const ColorGradingSettings();
    brightness = colorSettings.brightness;
    contrast = colorSettings.contrast;
    saturation = colorSettings.saturation;
    temperature = colorSettings.temperature;
    vignette = colorSettings.vignette;
    currentEffect = clip?.effect ?? VideoEffect.none;
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
                  'Color Grading & Visual Effects',
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
            const Text('Presets & LUTs', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: VideoEffect.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final fx = VideoEffect.values[index];
                  final isSelected = currentEffect == fx;
                  return ChoiceChip(
                    label: Text(fx.name.toUpperCase()),
                    selected: isSelected,
                    selectedColor: const Color(0xFF8B5CF6),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          currentEffect = fx;
                        });
                        controller.applyEffect(fx);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('Adjustments', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _AdjustmentSlider(
              label: 'Brightness',
              value: brightness,
              min: -1.0,
              max: 1.0,
              onChanged: (val) {
                setState(() => brightness = val);
                _update(controller);
              },
            ),
            _AdjustmentSlider(
              label: 'Contrast',
              value: contrast,
              min: 0.0,
              max: 2.0,
              onChanged: (val) {
                setState(() => contrast = val);
                _update(controller);
              },
            ),
            _AdjustmentSlider(
              label: 'Saturation',
              value: saturation,
              min: 0.0,
              max: 2.0,
              onChanged: (val) {
                setState(() => saturation = val);
                _update(controller);
              },
            ),
            _AdjustmentSlider(
              label: 'Temperature',
              value: temperature,
              min: -1.0,
              max: 1.0,
              onChanged: (val) {
                setState(() => temperature = val);
                _update(controller);
              },
            ),
            _AdjustmentSlider(
              label: 'Vignette',
              value: vignette,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                setState(() => vignette = val);
                _update(controller);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _update(EditorController controller) {
    controller.updateColorGrading(
      ColorGradingSettings(
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
        temperature: temperature,
        vignette: vignette,
      ),
    );
  }
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: const Color(0xFF8B5CF6),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
