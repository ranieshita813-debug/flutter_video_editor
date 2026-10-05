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

class MaskSheet extends StatefulWidget {
  const MaskSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const MaskSheet(),
    );
  }

  @override
  State<MaskSheet> createState() => _MaskSheetState();
}

class _MaskSheetState extends State<MaskSheet> {
  late MaskProperties mask;

  @override
  void initState() {
    super.initState();
    final clip = context.read<EditorController>().selectedClip;
    mask = clip?.maskProperties ?? const MaskProperties();
  }

  void _apply(EditorController c, MaskProperties next) {
    setState(() => mask = next);
    c.updateMaskProperties(next);
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
                  'Video Masking',
                  style: TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
            _maskTypeSelector(c),
            if (mask.type != MaskType.none) ...<Widget>[
              const SizedBox(height: 16),
              _slider('Feather', '${mask.feather.toInt()} px', mask.feather, 0,
                  50, (v) => _apply(c, mask.copyWith(feather: v))),
              _slider('Width', '${mask.width.toInt()} %', mask.width, 10, 200,
                  (v) => _apply(c, mask.copyWith(width: v))),
              _slider('Height', '${mask.height.toInt()} %', mask.height, 10,
                  200, (v) => _apply(c, mask.copyWith(height: v))),
              _slider('Rotation', '${mask.rotation.toInt()}°', mask.rotation,
                  -180, 180, (v) => _apply(c, mask.copyWith(rotation: v))),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Text('Invert Mask',
                      style: TextStyle(color: _text, fontSize: 14)),
                  const Spacer(),
                  Switch(
                    value: mask.isInverted,
                    onChanged: (v) => _apply(c, mask.copyWith(isInverted: v)),
                    activeThumbColor: Colors.black,
                    activeTrackColor: Colors.white,
                    inactiveThumbColor: _muted,
                    inactiveTrackColor: _track,
                  ),
                ],
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

  Widget _maskTypeSelector(EditorController c) {
    final types = <(MaskType, String, List<List<dynamic>>)>[
      (MaskType.none, 'None', HugeIcons.strokeRoundedCancelCircle),
      (MaskType.rectangle, 'Rectangle', HugeIcons.strokeRoundedSquare),
      (MaskType.circle, 'Circle', HugeIcons.strokeRoundedCircle),
      (MaskType.linear, 'Linear', HugeIcons.strokeRoundedGrid),
      (MaskType.mirror, 'Mirror', HugeIcons.strokeRoundedArrowLeftRight),
      (MaskType.star, 'Star', HugeIcons.strokeRoundedStar),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final t in types)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _apply(c, mask.copyWith(type: t.$1));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mask.type == t.$1 ? Colors.white : _card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  HugeIcon(icon: t.$3,
                      size: 16,
                      color: mask.type == t.$1 ? Colors.black : _text),
                  const SizedBox(width: 6),
                  Text(
                    t.$2,
                    style: TextStyle(
                      color: mask.type == t.$1 ? Colors.black : _text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _slider(
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
