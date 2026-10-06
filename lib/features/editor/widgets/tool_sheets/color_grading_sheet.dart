import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class ColorGradingSheet extends StatelessWidget {
  const ColorGradingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final cg = editor.selectedClip?.colorGrading;
    final double b = cg?.brightness ?? 0.0;
    final double c = cg?.contrast ?? 1.0;
    final double s = cg?.saturation ?? 1.0;

    void push(double nb, double nc, double ns) => editor.updateColorGrading(
        ColorGradingSettings(brightness: nb, contrast: nc, saturation: ns));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderRow(
          context,
          label: 'Brightness',
          value: b,
          min: -0.5,
          max: 0.5,
          onChanged: (v) => push(v, c, s),
        ),
        const SizedBox(height: 12),
        _buildSliderRow(
          context,
          label: 'Contrast',
          value: c,
          min: 0.5,
          max: 2.0,
          onChanged: (v) => push(b, v, s),
        ),
        const SizedBox(height: 12),
        _buildSliderRow(
          context,
          label: 'Saturation',
          value: s,
          min: 0.0,
          max: 2.0,
          onChanged: (v) => push(b, c, v),
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
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
              Text(
                label,
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              Text(
                value.toStringAsFixed(2),
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
