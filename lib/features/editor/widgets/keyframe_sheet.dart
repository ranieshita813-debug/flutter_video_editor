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

class KeyframeSheet extends StatefulWidget {
  const KeyframeSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const KeyframeSheet(),
    );
  }

  @override
  State<KeyframeSheet> createState() => _KeyframeSheetState();
}

class _KeyframeSheetState extends State<KeyframeSheet> {
  KeyframeProperty selectedProperty = KeyframeProperty.scale;
  CurveType selectedCurve = CurveType.linear;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final clip = c.selectedClip;
    final playhead = c.playhead;

    if (clip == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Select a clip on the timeline to edit keyframes.',
              style: TextStyle(color: _muted)),
        ),
      );
    }

    final keyframes = clip.keyframes;

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
                  'Keyframes & Curve Editor',
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
            _propertySelector(),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 18),
                  label: const Text('Add Keyframe'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    final kf = Keyframe(
                      id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
                      time: playhead,
                      property: selectedProperty,
                      value: _currentValueFor(clip, selectedProperty),
                      curveType: selectedCurve,
                    );
                    c.addKeyframe(kf);
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  'At ${(playhead.inMilliseconds / 1000.0).toStringAsFixed(2)}s',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Interpolation Curve',
              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _curveSelector(),
            const SizedBox(height: 16),
            const Text(
              'Clip Keyframes',
              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (keyframes.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No keyframes added yet for this clip.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              )
            else
              Column(
                children: <Widget>[
                  for (final kf in keyframes)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: <Widget>[
                          const HugeIcon(icon: HugeIcons.strokeRoundedDiamond,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 10),
                          Text(
                            '${kf.property.name.toUpperCase()}  ·  ${(kf.time.inMilliseconds / 1000.0).toStringAsFixed(2)}s',
                            style: const TextStyle(
                                color: _text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01,
                                color: Colors.white70, size: 18),
                            onPressed: () => c.removeKeyframe(kf.id),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  double _currentValueFor(TimelineClip clip, KeyframeProperty p) {
    return switch (p) {
      KeyframeProperty.positionX => clip.positionX,
      KeyframeProperty.positionY => clip.positionY,
      KeyframeProperty.scale => clip.scale,
      KeyframeProperty.rotation => clip.rotation,
      KeyframeProperty.opacity => clip.opacity,
      KeyframeProperty.volume => clip.volume,
    };
  }

  Widget _propertySelector() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (final p in KeyframeProperty.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => selectedProperty = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedProperty == p ? Colors.white : _card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    p.name,
                    style: TextStyle(
                      color: selectedProperty == p ? Colors.black : _text,
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

  Widget _curveSelector() {
    return Row(
      children: <Widget>[
        for (final c in CurveType.values)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => selectedCurve = c),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectedCurve == c ? Colors.white : _card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: selectedCurve == c ? Colors.black : _text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
