import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _bg = Color(0xFF101014);
const Color _chip = Color(0xFF1C1C21);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);
const Color _accent = Color(0xFF5B8CFF);

/// The camera parameters shown in the inline panel, grouped like a real camera:
/// lens, exposure, orientation.
enum _Cam {
  fov('FOV', Icons.panorama_wide_angle_outlined, 10, 120),
  focal('Focal', Icons.center_focus_strong_outlined, 14, 200),
  zoom('Zoom', Icons.zoom_in_rounded, 0.5, 5),
  iso('ISO', Icons.grain_rounded, 100, 6400),
  shutter('Shutter', Icons.shutter_speed_rounded, 0.001, 0.1),
  aperture('Aperture', Icons.lens_blur_rounded, 1.2, 22),
  wb('White bal.', Icons.wb_sunny_outlined, 2000, 10000),
  pan('Pan', Icons.swap_horiz_rounded, -180, 180),
  tilt('Tilt', Icons.swap_vert_rounded, -90, 90),
  roll('Roll', Icons.rotate_right_rounded, -180, 180);

  const _Cam(this.label, this.icon, this.min, this.max);
  final String label;
  final IconData icon;
  final double min;
  final double max;

  /// Index after which a thin divider separates the groups.
  bool get endsGroup => this == _Cam.zoom || this == _Cam.wb;

  double read(CameraProperties c) => switch (this) {
        _Cam.fov => c.fov,
        _Cam.focal => c.focalLength,
        _Cam.zoom => c.zoom,
        _Cam.iso => c.iso.toDouble(),
        _Cam.shutter => c.shutterSpeed,
        _Cam.aperture => c.aperture,
        _Cam.wb => c.whiteBalance.toDouble(),
        _Cam.pan => c.pan,
        _Cam.tilt => c.tilt,
        _Cam.roll => c.roll,
      };

  CameraProperties write(CameraProperties c, double v) => switch (this) {
        _Cam.fov => c.copyWith(fov: v),
        _Cam.focal => c.copyWith(focalLength: v),
        _Cam.zoom => c.copyWith(zoom: v),
        _Cam.iso => c.copyWith(iso: v.round()),
        _Cam.shutter => c.copyWith(shutterSpeed: v),
        _Cam.aperture => c.copyWith(aperture: v),
        _Cam.wb => c.copyWith(whiteBalance: v.round()),
        _Cam.pan => c.copyWith(pan: v),
        _Cam.tilt => c.copyWith(tilt: v),
        _Cam.roll => c.copyWith(roll: v),
      };

  String format(CameraProperties c) => switch (this) {
        _Cam.fov => '${c.fov.round()}°',
        _Cam.focal => '${c.focalLength.round()} mm',
        _Cam.zoom => '${c.zoom.toStringAsFixed(2)}x',
        _Cam.iso => '${c.iso}',
        _Cam.shutter => '1/${(1 / c.shutterSpeed).round()}s',
        _Cam.aperture => 'f/${c.aperture.toStringAsFixed(1)}',
        _Cam.wb => '${c.whiteBalance} K',
        _Cam.pan => '${c.pan.round()}°',
        _Cam.tilt => '${c.tilt.round()}°',
        _Cam.roll => '${c.roll.round()}°',
      };
}

/// Inline camera panel (CapCut style). It has no handle, title, close or apply
/// button: the editor's tool panel provides the header and the ✓ button, and
/// every change is applied live to the selected clip.
class CameraSettingsSheet extends StatefulWidget {
  const CameraSettingsSheet({super.key});

  /// Kept so old call sites still compile. Prefer embedding the widget inline.
  @Deprecated('Embed CameraSettingsSheet inline in the editor tool panel.')
  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      builder: (_) => const SizedBox(height: 280, child: CameraSettingsSheet()),
    );
  }

  @override
  State<CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<CameraSettingsSheet> {
  static const List<(String, CameraProperties)> _presets = <(String, CameraProperties)>[
    ('Cinematic 35mm', CameraProperties(fov: 54, focalLength: 35, aperture: 2.0, iso: 400)),
    ('Action cam', CameraProperties(fov: 110, focalLength: 16, aperture: 2.8, iso: 800)),
    ('Portrait 85mm', CameraProperties(fov: 28, focalLength: 85, aperture: 1.4, iso: 200)),
    ('Telephoto', CameraProperties(fov: 18, focalLength: 135, aperture: 2.8, iso: 400)),
  ];

  CameraProperties _camera = const CameraProperties();
  String? _clipId;
  _Cam _selected = _Cam.fov;

  void _apply(EditorController c, CameraProperties next) {
    setState(() => _camera = next);
    c.updateCameraProperties(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final clip = c.selectedClip;

    // Re-sync when the user selects a different clip while the panel is open.
    if (c.selectedClipId != _clipId) {
      _clipId = c.selectedClipId;
      _camera = clip?.cameraProperties ?? const CameraProperties();
    }

    if (clip == null) return const _EmptyState();

    return Container(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _presetsRow(c),
            const SizedBox(height: 12),
            _paramRow(),
            const SizedBox(height: 6),
            _valueSlider(c),
          ],
        ),
      ),
    );
  }

  Widget _presetsRow(EditorController c) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: <Widget>[
          _pill(Icons.restart_alt_rounded, 'Reset', () => _apply(c, const CameraProperties())),
          for (final p in _presets) _pill(null, p.$1, () => _apply(c, p.$2)),
        ],
      ),
    );
  }

  Widget _pill(IconData? icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _chip,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _track, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: _muted),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: const TextStyle(
                        color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  Widget _paramRow() {
    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: <Widget>[
          for (final p in _Cam.values) ...<Widget>[
            _paramItem(p),
            if (p.endsGroup)
              Container(
                width: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                color: _track,
              ),
          ],
        ],
      ),
    );
  }

  Widget _paramItem(_Cam p) {
    final bool on = p == _selected;
    final bool changed = p.read(_camera) != p.read(const CameraProperties());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selected = p);
      },
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 38,
                  height: 32,
                  decoration: BoxDecoration(
                    color: on ? _text : _chip,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(p.icon, size: 19, color: on ? Colors.black : _text),
                ),
                if (changed)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: on ? _text : _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _valueSlider(EditorController c) {
    final p = _selected;
    final double v = p.read(_camera).clamp(p.min, p.max).toDouble();
    final double def = p.read(const CameraProperties());

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 10, 0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(p.label, style: const TextStyle(color: _muted, fontSize: 12)),
              const Spacer(),
              Text(p.format(_camera),
                  style: const TextStyle(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              IconButton(
                tooltip: 'Reset ${p.label}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, color: _muted, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _apply(c, p.write(_camera, def));
                },
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _text,
              inactiveTrackColor: _track,
              thumbColor: _text,
              overlayColor: Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Slider(
                value: v,
                min: p.min,
                max: p.max,
                onChanged: (x) => _apply(c, p.write(_camera, x)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.touch_app_outlined, color: Colors.white38, size: 30),
          SizedBox(height: 8),
          Text('Select a clip to adjust its camera',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    );
  }
}