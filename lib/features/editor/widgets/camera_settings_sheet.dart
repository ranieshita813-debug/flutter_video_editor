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

class CameraSettingsSheet extends StatefulWidget {
  const CameraSettingsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CameraSettingsSheet(),
    );
  }

  @override
  State<CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<CameraSettingsSheet> {
  late CameraProperties camera;

  @override
  void initState() {
    super.initState();
    final clip = context.read<EditorController>().selectedClip;
    camera = clip?.cameraProperties ?? const CameraProperties();
  }

  void _apply(EditorController c, CameraProperties next) {
    setState(() => camera = next);
    c.updateCameraProperties(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
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
                  '3D Camera Settings',
                  style: TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
            _presetsRow(c),
            const SizedBox(height: 16),
            _sliderTile('Field of View (FOV)', '${camera.fov.toInt()}°',
                camera.fov, 10, 120, (v) => _apply(c, camera.copyWith(fov: v))),
            _sliderTile(
                'Focal Length',
                '${camera.focalLength.toInt()} mm',
                camera.focalLength,
                14,
                200,
                (v) => _apply(c, camera.copyWith(focalLength: v))),
            _sliderTile('ISO Speed', '${camera.iso}', camera.iso.toDouble(),
                100, 6400, (v) => _apply(c, camera.copyWith(iso: v.toInt()))),
            _sliderTile(
                'Shutter Speed',
                '1/${(1 / camera.shutterSpeed).toInt()}s',
                camera.shutterSpeed,
                0.001,
                0.1,
                (v) => _apply(c, camera.copyWith(shutterSpeed: v))),
            _sliderTile(
                'Aperture',
                'f/${camera.aperture.toStringAsFixed(1)}',
                camera.aperture,
                1.2,
                22.0,
                (v) => _apply(c, camera.copyWith(aperture: v))),
            _sliderTile(
                'White Balance',
                '${camera.whiteBalance} K',
                camera.whiteBalance.toDouble(),
                2000,
                10000,
                (v) => _apply(c, camera.copyWith(whiteBalance: v.toInt()))),
            _sliderTile(
                'Camera Zoom',
                '${camera.zoom.toStringAsFixed(2)}x',
                camera.zoom,
                0.5,
                5.0,
                (v) => _apply(c, camera.copyWith(zoom: v))),
            _sliderTile(
                'Pan (X)',
                '${camera.pan.toInt()}°',
                camera.pan,
                -180,
                180,
                (v) => _apply(c, camera.copyWith(pan: v))),
            _sliderTile(
                'Tilt (Y)',
                '${camera.tilt.toInt()}°',
                camera.tilt,
                -90,
                90,
                (v) => _apply(c, camera.copyWith(tilt: v))),
            _sliderTile(
                'Roll (Z)',
                '${camera.roll.toInt()}°',
                camera.roll,
                -180,
                180,
                (v) => _apply(c, camera.copyWith(roll: v))),
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
              child: const Text('Apply Camera Settings',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetsRow(EditorController c) {
    final presets = <(String, CameraProperties)>[
      (
        'Cinematic 35mm',
        const CameraProperties(fov: 54, focalLength: 35, aperture: 2.0, iso: 400)
      ),
      (
        'Action Cam',
        const CameraProperties(fov: 110, focalLength: 16, aperture: 2.8, iso: 800)
      ),
      (
        'Portrait 85mm',
        const CameraProperties(fov: 28, focalLength: 85, aperture: 1.4, iso: 200)
      ),
      (
        'Telephoto',
        const CameraProperties(fov: 18, focalLength: 135, aperture: 2.8, iso: 400)
      ),
    ];

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _apply(c, p.$2);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _track),
                  ),
                  child: Text(
                    p.$1,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
