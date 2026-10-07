import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/skeleton_grid.dart';

// ----------------------------------------------------------------------------
// Transition picker
// ----------------------------------------------------------------------------
enum TransitionType { none, fade, slide, zoom, blur }

void showTransitionSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: surfaceToken,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Transition',
                style: TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (final t in TransitionType.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        tapFeedback();
                        Navigator.of(context).pop();
                      },
                      child: Column(
                        children: <Widget>[
                          Container(
                            height: 48,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26262C),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                                switch (t) {
                                  TransitionType.none => Icons.block_rounded,
                                  TransitionType.fade => Icons.blur_on_rounded,
                                  TransitionType.slide => Icons.swipe_rounded,
                                  TransitionType.zoom => Icons.zoom_in_rounded,
                                  TransitionType.blur => Icons.blur_circular_rounded,
                                },
                                color: Colors.white70,
                                size: 20),
                          ),
                          const SizedBox(height: 6),
                          Text(t.name,
                              style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ----------------------------------------------------------------------------
// Shared sheet widgets
// ----------------------------------------------------------------------------
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration:
            BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(12)),
        child: child,
      );
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? display;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(display ?? value.toStringAsFixed(2),
                  style: const TextStyle(color: accentToken, fontSize: 12)),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: accentToken,
            inactiveColor: dividerToken,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

Widget _primaryBtn(dynamic icon, String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentToken,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                tapFeedback();
                onPressed();
              },
        icon: HugeIcon(icon: icon, color: Colors.black, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );

class _ResponsiveGrid extends StatefulWidget {
  const _ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minTile = 100,
    this.aspect = 1,
    this.fakeLoad = false,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minTile;
  final double aspect;
  final bool fakeLoad;

  @override
  State<_ResponsiveGrid> createState() => _ResponsiveGridState();
}

class _ResponsiveGridState extends State<_ResponsiveGrid> {
  late bool _loading = widget.fakeLoad;

  @override
  void initState() {
    super.initState();
    if (_loading) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final int cols = colsCount(c.maxWidth - 24, widget.minTile);
      if (_loading) {
        return SkeletonGrid(
            itemCount: math.min(widget.itemCount, cols * 2),
            crossAxisCount: cols,
            childAspectRatio: widget.aspect);
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: widget.aspect,
        ),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    });
  }
}

Widget _tile({
  required Widget child,
  required VoidCallback onTap,
  bool selected = false,
}) =>
    InkWell(
      onTap: () {
        tapFeedback();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? accentToken.withValues(alpha: 0.2) : cardToken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? accentToken : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );

// ----------------------------------------------------------------------------
// Tool Sheet Implementations
// ----------------------------------------------------------------------------

class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    final bool hasAudio = clip != null &&
        (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final double volume = clip?.volume ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Card(
          child: Row(
            children: <Widget>[
              const HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: accentToken, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Add Audio Track',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Insert soundtrack clip to timeline',
                        style: TextStyle(color: mutedToken, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: accentToken, foregroundColor: Colors.black),
                onPressed: () {
                  tapFeedback();
                  editor.addAudioTrack(
                      'Track ${editor.clips.where((c) => c.clipType == ClipType.audio).length + 1}');
                },
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: Colors.black, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (hasAudio) ...<Widget>[
          const SizedBox(height: 12),
          _SliderCard(
            label: 'Volume',
            value: volume,
            min: 0,
            max: 2,
            display: '${(volume * 100).round()}%',
            onChanged: (val) =>
                editor.updateAudioProperties(AudioProperties(volume: val, speed: clip.speed)),
          ),
        ],
      ],
    );
  }
}

class TextAnimationSheet extends StatefulWidget {
  const TextAnimationSheet({super.key});

  @override
  State<TextAnimationSheet> createState() => _TextAnimationSheetState();
}

class _TextAnimationSheetState extends State<TextAnimationSheet> {
  final TextEditingController _ctrl = TextEditingController(text: 'Sample Text');
  String _selectedFont = 'Poppins';
  final TextAnimationStyle _anim = TextAnimationStyle.fadeIn;

  static const List<String> _fonts = <String>[
    'Poppins', 'Unbounded', 'Roboto', 'Arial', 'Montserrat', 'Inter'
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final bool editing = editor.selectedClip?.clipType == ClipType.text;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Text Content',
              labelStyle: const TextStyle(color: mutedToken),
              filled: true,
              fillColor: cardToken,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _ResponsiveGrid(
            fakeLoad: true,
            itemCount: _fonts.length,
            minTile: 110,
            aspect: 2.2,
            itemBuilder: (context, i) {
              final font = _fonts[i];
              final bool selected = font == _selectedFont;
              return _tile(
                selected: selected,
                onTap: () => setState(() => _selectedFont = font),
                child: Text(
                  font,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? accentToken : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _primaryBtn(
            HugeIcons.strokeRoundedAdd01,
            editing ? 'Update Selected Text' : 'Add Text Clip',
            () {
              if (editing) {
                editor.updateSelectedTextProperties(
                    text: _ctrl.text, fontFamily: _selectedFont, textAnimationStyle: _anim);
              } else {
                editor.addTextOverlay(_ctrl.text.isEmpty ? 'Text' : _ctrl.text,
                    fontFamily: _selectedFont, animationStyle: _anim);
              }
            },
          ),
        ),
      ],
    );
  }
}

class StickersSheet extends StatelessWidget {
  const StickersSheet({super.key});

  static const List<String> _emojis = <String>[
    '🔥', '✨', '⚡', '🎉', '❤️', '🌟', '🎬', '👏', '🚀', '💯', '💥', '⭐', '🎈', '🏆', '💎'
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: _emojis.length,
      minTile: 64,
      itemBuilder: (context, i) => _tile(
        onTap: () => editor.addTextOverlay(_emojis[i], fontFamily: 'Poppins'),
        child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

class EffectsSheet extends StatelessWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final currentEffect = editor.selectedClip?.effect ?? VideoEffect.none;

    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: VideoEffect.values.length,
      minTile: 104,
      aspect: 1.8,
      itemBuilder: (context, i) {
        final fx = VideoEffect.values[i];
        final bool selected = fx == currentEffect;
        return _tile(
          selected: selected,
          onTap: () => editor.applyEffect(fx),
          child: Text(
            fx.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? accentToken : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

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
      children: <Widget>[
        _SliderCard(label: 'Brightness', value: b, min: -0.5, max: 0.5,
            onChanged: (v) => push(v, c, s)),
        const SizedBox(height: 10),
        _SliderCard(label: 'Contrast', value: c, min: 0.5, max: 2.0,
            onChanged: (v) => push(b, v, s)),
        const SizedBox(height: 10),
        _SliderCard(label: 'Saturation', value: s, min: 0.0, max: 2.0,
            onChanged: (v) => push(b, c, v)),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: dividerToken),
              minimumSize: const Size.fromHeight(42)),
          onPressed: () {
            tapFeedback();
            push(0.0, 1.0, 1.0);
          },
          child: const Text('Reset', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

enum CanvasRatio {
  r16x9('16:9', 16 / 9),
  r9x16('9:16', 9 / 16),
  r1x1('1:1', 1),
  r4x5('4:5', 4 / 5),
  r21x9('21:9', 21 / 9);

  const CanvasRatio(this.label, this.value);
  final String label;
  final double value;
}

final ValueNotifier<CanvasRatio> canvasRatioNotifier =
    ValueNotifier<CanvasRatio>(CanvasRatio.r16x9);

class CropSheet extends StatelessWidget {
  const CropSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final double scale = editor.selectedClip?.scale ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('Canvas ratio',
            style: TextStyle(color: mutedToken, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ValueListenableBuilder<CanvasRatio>(
          valueListenable: canvasRatioNotifier,
          builder: (_, cur, __) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final r in CanvasRatio.values)
                InkWell(
                  onTap: () {
                    tapFeedback();
                    canvasRatioNotifier.value = r;
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 68,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: r == cur ? accentToken.withValues(alpha: 0.2) : cardToken,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: r == cur ? accentToken : Colors.transparent),
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                            color: r == cur ? accentToken : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SliderCard(
          label: 'Clip zoom',
          value: scale,
          min: 0.5,
          max: 3.0,
          display: '${(scale * 100).round()}%',
          onChanged: editor.selectedClip == null
              ? (_) {}
              : (v) => editor.updateTranslation(scale: v),
        ),
      ],
    );
  }
}

class ElementsSheet extends StatelessWidget {
  const ElementsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: ElementShape.values.length,
      minTile: 80,
      itemBuilder: (context, i) {
        final shape = ElementShape.values[i];
        return _tile(
          onTap: () =>
              editor.addElementClip(shape, label: shape.name, color: Colors.cyanAccent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const HugeIcon(icon: HugeIcons.strokeRoundedShapes, color: accentToken, size: 22),
              const SizedBox(height: 4),
              Text(shape.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}

class VectorDrawingSheet extends StatefulWidget {
  const VectorDrawingSheet({super.key});

  @override
  State<VectorDrawingSheet> createState() => _VectorDrawingSheetState();
}

class _VectorDrawingSheetState extends State<VectorDrawingSheet> {
  Color _color = Colors.cyanAccent;
  double _width = 4.0;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SliderCard(
          label: 'Stroke width',
          value: _width,
          min: 1,
          max: 20,
          display: _width.toStringAsFixed(0),
          onChanged: (v) {
            setState(() => _width = v);
            editor.setStrokeWidth(v);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 12,
          runSpacing: 8,
          children: <Color>[
            Colors.cyanAccent,
            Colors.redAccent,
            Colors.greenAccent,
            Colors.yellowAccent,
            Colors.white
          ]
              .map((c) => GestureDetector(
                    onTap: () {
                      setState(() => _color = c);
                      editor.setDrawingColor(c);
                    },
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 16,
                      child: _color == c
                          ? const HugeIcon(
                              icon: HugeIcons.strokeRoundedTick01, size: 14, color: Colors.black)
                          : null,
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: dividerToken),
                    minimumSize: const Size.fromHeight(44)),
                onPressed: () {
                  tapFeedback();
                  editor.clearActiveDrawing();
                },
                child: const Text('Clear', style: TextStyle(color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: accentToken,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(44)),
                onPressed: () {
                  tapFeedback();
                  editor.saveVectorDrawingAsClip();
                },
                child: const Text('Save Clip'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MaskSheet extends StatelessWidget {
  const MaskSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      itemCount: MaskType.values.length,
      minTile: 104,
      aspect: 2.2,
      itemBuilder: (context, i) {
        final type = MaskType.values[i];
        return _tile(
          onTap: () =>
              editor.updateMaskProperties(MaskProperties(type: type, feather: 10.0)),
          child: Text(type.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class KeyframeSheet extends StatelessWidget {
  const KeyframeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final keyframes = editor.selectedClip?.keyframes ?? <Keyframe>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _primaryBtn(
          HugeIcons.strokeRoundedAdd01,
          'Add Keyframe at Playhead',
          editor.selectedClip == null
              ? null
              : () => editor.addKeyframe(Keyframe(
                    id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
                    time: editor.playhead,
                    property: KeyframeProperty.scale,
                    value: 1.0,
                  )),
        ),
        const SizedBox(height: 12),
        if (keyframes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('No keyframes yet',
                  style: TextStyle(color: mutedToken, fontSize: 12)),
            ),
          ),
        ...keyframes.map((kf) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration:
                  BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                dense: true,
                title: Text(
                    '${'${kf.property}'.split('.').last} @ ${secondsOf(kf.time).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                trailing: IconButton(
                  tooltip: 'Remove keyframe',
                  icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      color: Colors.redAccent,
                      size: 18),
                  onPressed: () => editor.removeKeyframe(kf.id),
                ),
              ),
            )),
      ],
    );
  }
}

class CameraSettingsSheet extends StatelessWidget {
  const CameraSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final props = editor.selectedClip?.cameraProperties ?? const CameraProperties();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SliderCard(
          label: 'Focal length',
          value: props.focalLength,
          min: 10,
          max: 200,
          display: '${props.focalLength.round()} mm',
          onChanged: (v) => editor.updateCameraProperties(props.copyWith(focalLength: v)),
        ),
      ],
    );
  }
}

class CameraTrackingPanel extends StatelessWidget {
  const CameraTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final tracking = editor.selectedClip?.trackingData;
    final bool active = tracking?.isEnabled == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Card(
          child: Row(
            children: <Widget>[
              Icon(Icons.circle, size: 10, color: active ? Colors.greenAccent : Colors.white24),
              const SizedBox(width: 8),
              Text('Tracking status: ${active ? "Active" : "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _primaryBtn(
          HugeIcons.strokeRoundedTarget01,
          active ? 'Stop Tracking' : 'Start Auto-Tracking',
          editor.selectedClip == null
              ? null
              : () => editor.updateTrackingData(TrackingData(
                    isEnabled: !active,
                    targetName: 'Subject',
                    rect: const Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
                  )),
        ),
      ],
    );
  }
}

class PluginsSheet extends StatelessWidget {
  const PluginsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = PluginManager().activePlugins;

    if (plugins.isEmpty) {
      return const Center(
        child: Text('No active plug-ins', style: TextStyle(color: mutedToken, fontSize: 12)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final p = plugins[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedGridView, color: accentToken, size: 20),
            title: Text(p.name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle:
                Text(p.version, style: const TextStyle(color: mutedToken, fontSize: 11)),
          ),
        );
      },
    );
  }
}
