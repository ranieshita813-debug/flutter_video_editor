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

class CameraTrackingPanel extends StatefulWidget {
  const CameraTrackingPanel({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
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

  void _update(EditorController controller) {
    controller.updateTrackingData(
      TrackingData(
        isEnabled: isTrackingEnabled,
        targetName: targetName,
        smoothness: smoothness,
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
                  'Camera Feed & Motion Tracking',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Live Camera Preview Overlay',
                  style: TextStyle(color: _text, fontSize: 14)),
              subtitle: const Text('Render live camera feed onto video canvas',
                  style: TextStyle(color: _muted, fontSize: 11)),
              value: controller.isCameraActive,
              activeThumbColor: Colors.black,
              activeTrackColor: Colors.white,
              inactiveThumbColor: _muted,
              inactiveTrackColor: _track,
              onChanged: (val) {
                controller.toggleCameraActive();
              },
            ),
            const Divider(color: _track),
            SwitchListTile(
              title: const Text('Enable AI Object Tracking',
                  style: TextStyle(color: _text, fontSize: 14)),
              subtitle: const Text('Track target motion automatically across frames',
                  style: TextStyle(color: _muted, fontSize: 11)),
              value: isTrackingEnabled,
              activeThumbColor: Colors.black,
              activeTrackColor: Colors.white,
              inactiveThumbColor: _muted,
              inactiveTrackColor: _track,
              onChanged: (val) {
                setState(() => isTrackingEnabled = val);
                _update(controller);
              },
            ),
            if (isTrackingEnabled) ...<Widget>[
              const SizedBox(height: 12),
              const Text('Tracking Target Type',
                  style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: targets.map((t) {
                  final isSelected = targetName == t;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => targetName = t);
                      _update(controller);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _track),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          color: isSelected ? Colors.black : _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('Smoothness', style: TextStyle(color: _text, fontSize: 13)),
                  const Spacer(),
                  Text('${(smoothness * 100).round()}%',
                      style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
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
                  value: smoothness,
                  min: 0.1,
                  max: 1.0,
                  onChanged: (val) {
                    setState(() => smoothness = val);
                    _update(controller);
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
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
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
