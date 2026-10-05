import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

class CropSheet extends StatefulWidget {
  const CropSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CropSheet(),
    );
  }

  @override
  State<CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<CropSheet> {
  AspectRatioPreset selectedRatio = AspectRatioPreset.nineSixteen;

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectsController>();

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
                  'Crop & Aspect Ratio',
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
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AspectRatioPreset.values.map((ratio) {
                final isSel = selectedRatio == ratio;
                return ChoiceChip(
                  label: Text(ratio.label),
                  selected: isSel,
                  selectedColor: const Color(0xFF7C5CFF),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => selectedRatio = ratio);
                      if (projects.projects.isNotEmpty) {
                        final curr = projects.projects.first;
                        projects.saveProject(curr.copyWith(aspectRatio: ratio));
                      }
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
