import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class CameraTrackingPanel extends StatefulWidget {
  const CameraTrackingPanel({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CameraTrackingPanel(),
    );
  }

  @override
  State<CameraTrackingPanel> createState() => _CameraTrackingPanelState();
}

class _CameraTrackingPanelState extends State<CameraTrackingPanel> {
  late bool isTrackingEnabled;
  late String targetName;
  late double smoothness;

  final List<String> targets = const <String>['Face', 'Hand', 'Body', 'Object', 'Custom Point'];

  @override
  void initState() {
    super.initState();
    final controller = context.read<EditorController>();
    final clip = controller.selectedClip;
    final tracking = clip?.trackingData ?? const TrackingData();
    isTrackingEnabled = tracking.isEnabled;
    targetName = tracking.targetName;
    smoothness = tracking.smoothness;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return Padding(
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
                'Camera Feed & Motion Tracking',
                style: TextStyle(
                  fontSize: 20,
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
          SwitchListTile(
            title: const Text('Live Camera Preview Overlay', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Render live camera feed onto video canvas', style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: controller.isCameraActive,
            activeTrackColor: const Color(0xFF8B5CF6),
            onChanged: (val) {
              controller.toggleCameraActive();
            },
          ),
          const Divider(color: Color(0xFF1F2937)),
          SwitchListTile(
            title: const Text('Enable AI Object Tracking', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Track target motion automatically across frames', style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: isTrackingEnabled,
            activeTrackColor: const Color(0xFF8B5CF6),
            onChanged: (val) {
              setState(() => isTrackingEnabled = val);
              _update(controller);
            },
          ),
          if (isTrackingEnabled) ...<Widget>[
            const SizedBox(height: 12),
            const Text('Tracking Target Type', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: targets.map((t) {
                final isSelected = targetName == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: isSelected,
                  selectedColor: const Color(0xFF8B5CF6),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => targetName = t);
                      _update(controller);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const SizedBox(width: 100, child: Text('Smoothness', style: TextStyle(color: Colors.white70))),
                Expanded(
                  child: Slider(
                    value: smoothness,
                    min: 0.1,
                    max: 1.0,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      setState(() => smoothness = val);
                      _update(controller);
                    },
                  ),
                ),
                Text('${(smoothness * 100).round()}%', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _update(EditorController controller) {
    controller.updateTrackingData(
      TrackingData(
        isEnabled: isTrackingEnabled,
        targetName: targetName,
        smoothness: smoothness,
      ),
    );
  }
}
