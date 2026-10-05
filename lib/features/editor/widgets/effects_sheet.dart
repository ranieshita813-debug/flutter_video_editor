import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class EffectsSheet extends StatelessWidget {
  const EffectsSheet({super.key, this.isFilterMode = false});

  final bool isFilterMode;

  static void show(BuildContext context, {bool isFilterMode = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EffectsSheet(isFilterMode: isFilterMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final clip = controller.selectedClip;
    final currentEffect = clip?.effect ?? VideoEffect.none;

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
                Text(
                  isFilterMode ? 'Video Filters' : 'Video Effects',
                  style: const TextStyle(
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
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VideoEffect.values.map((fx) {
                final isSel = currentEffect == fx;
                return ChoiceChip(
                  label: Text(fx.name.toUpperCase()),
                  selected: isSel,
                  selectedColor: const Color(0xFF7C5CFF),
                  onSelected: (selected) {
                    if (selected) {
                      controller.applyEffect(fx);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
