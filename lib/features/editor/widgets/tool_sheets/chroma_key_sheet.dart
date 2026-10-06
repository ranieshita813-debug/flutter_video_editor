import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class ChromaKeySheet extends StatelessWidget {
  const ChromaKeySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    final chromaKey = clip?.chromaKey ?? const ChromaKeySettings();

    void update(ChromaKeySettings next) {
      editor.updateChromaKeySettings(next);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: EditorTokens.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedFilter,
                color: EditorTokens.text,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enable Chroma Key',
                  style: TextStyle(
                    color: EditorTokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              Switch(
                value: chromaKey.enabled,
                activeTrackColor: EditorTokens.border,
                onChanged: (val) {
                  update(chromaKey.copyWith(enabled: val));
                },
              ),
            ],
          ),
        ),
        if (chromaKey.enabled) ...[
          const SizedBox(height: 16),
          const Text(
            'Key Color',
            style: TextStyle(
              color: EditorTokens.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _colorOption(
                label: 'Green',
                color: const Color(0xFF00FF00),
                selected: chromaKey.color.toARGB32() == const Color(0xFF00FF00).toARGB32(),
                onTap: () => update(chromaKey.copyWith(color: const Color(0xFF00FF00))),
              ),
              const SizedBox(width: 10),
              _colorOption(
                label: 'Blue',
                color: const Color(0xFF0000FF),
                selected: chromaKey.color.toARGB32() == const Color(0xFF0000FF).toARGB32(),
                onTap: () => update(chromaKey.copyWith(color: const Color(0xFF0000FF))),
              ),
              const SizedBox(width: 10),
              _colorOption(
                label: 'Red',
                color: const Color(0xFFFF0000),
                selected: chromaKey.color.toARGB32() == const Color(0xFFFF0000).toARGB32(),
                onTap: () => update(chromaKey.copyWith(color: const Color(0xFFFF0000))),
              ),
              const SizedBox(width: 10),
              _colorOption(
                label: 'Magenta',
                color: const Color(0xFFFF00FF),
                selected: chromaKey.color.toARGB32() == const Color(0xFFFF00FF).toARGB32(),
                onTap: () => update(chromaKey.copyWith(color: const Color(0xFFFF00FF))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sliderCard(
            label: 'Intensity (Distance)',
            value: chromaKey.distance,
            min: 0.0,
            max: 1.0,
            display: '${(chromaKey.distance * 100).round()}%',
            onChanged: (val) => update(chromaKey.copyWith(distance: val)),
          ),
          const SizedBox(height: 12),
          _sliderCard(
            label: 'Shadow / Softness',
            value: chromaKey.softness,
            min: 0.0,
            max: 1.0,
            display: '${(chromaKey.softness * 100).round()}%',
            onChanged: (val) => update(chromaKey.copyWith(softness: val)),
          ),
        ],
      ],
    );
  }

  Widget _colorOption({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? EditorTokens.elevated : EditorTokens.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? EditorTokens.text : EditorTokens.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? EditorTokens.text : EditorTokens.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderCard({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? display,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      decoration: BoxDecoration(
        color: EditorTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const Spacer(),
              Text(
                display ?? value.toStringAsFixed(2),
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: EditorTokens.text,
            inactiveColor: EditorTokens.border,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
