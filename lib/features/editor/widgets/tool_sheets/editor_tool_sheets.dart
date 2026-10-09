import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/skeleton_grid.dart';

// ============================================================================
// Design notes
// ----------------------------------------------------------------------------
// Visual language: CapCut-style docked panels on mobile (✕ title ✓ header,
// thumbnail tiles, thin sliders with a white thumb) with Premiere-style
// numeric readouts (tabular figures). Colors still come from the existing
// tokens in editor_helpers.dart: surfaceToken, cardToken, accentToken,
// mutedToken, dividerToken.
//
// Sheets are content only. To get the ✕ / ✓ header, wrap one in
// [ToolSheetFrame] from the host that shows it, for example:
//
//   ToolSheetFrame(
//     title: 'Color',
//     onClose: closePanel,
//     child: const ColorGradingSheet(),
//   )
//
// The frame needs a bounded height from its parent, like the sheets did.
// ============================================================================

// ----------------------------------------------------------------------------
// Public frame: header with cancel / apply, used by the host
// ----------------------------------------------------------------------------
class ToolSheetFrame extends StatelessWidget {
  const ToolSheetFrame({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.onApply,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;

  /// Defaults to [onClose] when null (edits are already live in the controller).
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SheetHeader(
          title: title,
          onClose: onClose,
          onApply: onApply ?? onClose,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.onClose,
    required this.onApply,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerToken)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Cancel',
            onPressed: () {
              tapFeedback();
              onClose();
            },
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Apply',
            onPressed: () {
              tapFeedback();
              onApply();
            },
            icon: Icon(Icons.check_rounded, color: accentToken, size: 24),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Transition picker
// ----------------------------------------------------------------------------
enum TransitionType { none, fade, slide, zoom, blur }

IconData _transitionIcon(TransitionType t) => switch (t) {
      TransitionType.none => Icons.block_rounded,
      TransitionType.fade => Icons.blur_on_rounded,
      TransitionType.slide => Icons.swipe_rounded,
      TransitionType.zoom => Icons.zoom_in_rounded,
      TransitionType.blur => Icons.blur_circular_rounded,
    };

/// Opens the transition sheet. Returns the chosen type when applied, or null
/// when cancelled. [onApply] receives the type and duration in seconds.
Future<TransitionType?> showTransitionSheet(
  BuildContext context, {
  TransitionType initial = TransitionType.none,
  double initialSeconds = 0.5,
  void Function(TransitionType type, double seconds)? onApply,
}) {
  return showModalBottomSheet<TransitionType>(
    context: context,
    backgroundColor: surfaceToken,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _TransitionPanel(
      initial: initial,
      initialSeconds: initialSeconds,
      onApply: onApply,
    ),
  );
}

class _TransitionPanel extends StatefulWidget {
  const _TransitionPanel({
    required this.initial,
    required this.initialSeconds,
    this.onApply,
  });

  final TransitionType initial;
  final double initialSeconds;
  final void Function(TransitionType type, double seconds)? onApply;

  @override
  State<_TransitionPanel> createState() => _TransitionPanelState();
}

class _TransitionPanelState extends State<_TransitionPanel> {
  late TransitionType _type = widget.initial;
  late double _seconds = widget.initialSeconds;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SheetHeader(
            title: 'Transition',
            onClose: () => Navigator.of(context).pop(),
            onApply: () {
              widget.onApply?.call(_type, _seconds);
              Navigator.of(context).pop(_type);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final t in TransitionType.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        height: 88,
                        child: _ThumbTile(
                          label: _cap(t.name),
                          icon: _transitionIcon(t),
                          selected: t == _type,
                          onTap: () => setState(() => _type = t),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: _SliderRow(
              label: 'Duration',
              value: _seconds,
              min: 0.1,
              max: 2.0,
              display: '${_seconds.toStringAsFixed(1)}s',
              // Nothing to time when there is no transition.
              onChanged: _type == TransitionType.none
                  ? null
                  : (v) => setState(() => _seconds = v),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Shared sheet widgets
// ----------------------------------------------------------------------------
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Gradient _thumbGradient(int i) {
  final double h = (i * 47 % 360).toDouble();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      HSLColor.fromAHSL(1, h, 0.45, 0.42).toColor(),
      HSLColor.fromAHSL(1, (h + 40) % 360, 0.5, 0.16).toColor(),
    ],
  );
}

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

/// Thin slider with a white thumb and a numeric readout (CapCut + Premiere).
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
    this.bipolar = false,
    this.minLabel,
    this.maxLabel,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final String? display;

  /// Draws a center tick and a neutral track, for values centered on zero.
  final bool bipolar;
  final String? minLabel;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              display ?? v.toStringAsFixed(2),
              style: TextStyle(
                color: accentToken,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: bipolar ? dividerToken : accentToken,
            inactiveTrackColor: dividerToken,
            disabledActiveTrackColor: dividerToken,
            disabledInactiveTrackColor: dividerToken,
            thumbColor: Colors.white,
            disabledThumbColor: mutedToken,
            overlayColor: accentToken.withValues(alpha: 0.15),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (bipolar) Container(width: 2, height: 12, color: mutedToken),
              Slider(value: v, min: min, max: max, onChanged: onChanged),
            ],
          ),
        ),
        if (minLabel != null && maxLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(minLabel!, style: TextStyle(color: mutedToken, fontSize: 10)),
                Text(maxLabel!, style: TextStyle(color: mutedToken, fontSize: 10)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pill button in the accent color.
Widget _primaryBtn(dynamic icon, String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentToken,
          foregroundColor: Colors.black,
          disabledBackgroundColor: cardToken,
          disabledForegroundColor: mutedToken,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                tapFeedback();
                onPressed();
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              HugeIcon(
                  icon: icon,
                  color: onPressed == null ? mutedToken : Colors.black,
                  size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );

/// Pill outline button for secondary actions.
Widget _outlineBtn(String label, VoidCallback? onPressed) => OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: dividerToken),
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(46),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed == null
          ? null
          : () {
              tapFeedback();
              onPressed();
            },
      child: Text(label),
    );

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerToken)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: InkWell(
                onTap: () {
                  tapFeedback();
                  onChanged(i);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: i == index ? accentToken : Colors.transparent,
                          width: 2),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == index ? Colors.white : mutedToken,
                      fontSize: 13,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Square thumbnail with a label underneath. Fills the height it is given.
class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.gradient,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Gradient? gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: () {
          tapFeedback();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: gradient == null ? cardToken : null,
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected ? accentToken : Colors.transparent,
                            width: 2),
                      ),
                      child: icon == null
                          ? null
                          : Center(
                              child: Icon(icon,
                                  size: 22,
                                  color: selected ? accentToken : Colors.white70),
                            ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration:
                            BoxDecoration(color: accentToken, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 12, color: Colors.black),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accentToken : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      final int cols = colsCount(c.maxWidth - 32, widget.minTile);
      if (_loading) {
        return SkeletonGrid(
            itemCount: math.min(widget.itemCount, cols * 2),
            crossAxisCount: cols,
            childAspectRatio: widget.aspect);
      }
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          childAspectRatio: widget.aspect,
        ),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    });
  }
}

/// Text-only chip tile, used for fonts, animation styles and emoji.
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
          color: selected ? accentToken.withValues(alpha: 0.18) : cardToken,
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentToken.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMusicNote01,
                      color: accentToken,
                      size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Add audio track',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Place a soundtrack clip on the timeline',
                        style: TextStyle(color: mutedToken, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: accentToken,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      tapFeedback();
                      editor.addAudioTrack(
                          'Track ${editor.clips.where((c) => c.clipType == ClipType.audio).length + 1}');
                    },
                    child: Tooltip(
                      message: 'Add audio track',
                      child: Center(
                        child: HugeIcon(
                            icon: HugeIcons.strokeRoundedAdd01,
                            color: Colors.black,
                            size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasAudio) ...<Widget>[
          const SizedBox(height: 20),
          _SliderRow(
            label: 'Volume',
            value: volume,
            min: 0,
            max: 2,
            display: '${(volume * 100).round()}%',
            minLabel: '0%',
            maxLabel: '200%',
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
  TextAnimationStyle _anim = TextAnimationStyle.fadeIn;
  int _tab = 0;

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
    final List<TextAnimationStyle> styles = TextAnimationStyle.values;

    return Column(
      children: <Widget>[
        _Tabs(
          labels: const <String>['Font', 'Animation'],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Text content',
              hintStyle: TextStyle(color: mutedToken),
              filled: true,
              fillColor: cardToken,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              suffixIcon: IconButton(
                tooltip: 'Clear text',
                icon: Icon(Icons.cancel_rounded, color: mutedToken, size: 18),
                onPressed: _ctrl.clear,
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _ResponsiveGrid(
                  key: const ValueKey<String>('fonts'),
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
                          fontFamily: font,
                          color: selected ? accentToken : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                )
              : _ResponsiveGrid(
                  key: const ValueKey<String>('animations'),
                  itemCount: styles.length,
                  minTile: 110,
                  aspect: 2.2,
                  itemBuilder: (context, i) {
                    final style = styles[i];
                    final bool selected = style == _anim;
                    return _tile(
                      selected: selected,
                      onTap: () => setState(() => _anim = style),
                      child: Text(
                        _cap(style.name),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _primaryBtn(
            null,
            editing ? 'Update selected text' : 'Add text clip',
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
        child: Text(_emojis[i], style: const TextStyle(fontSize: 26)),
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
      minTile: 76,
      aspect: 0.8,
      itemBuilder: (context, i) {
        final fx = VideoEffect.values[i];
        final bool selected = fx == currentEffect;
        final bool isNone = fx == VideoEffect.none;
        return _ThumbTile(
          label: _cap(fx.name),
          selected: selected,
          icon: isNone ? Icons.block_rounded : null,
          gradient: isNone ? null : _thumbGradient(i),
          onTap: () => editor.applyEffect(fx),
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
        _SliderRow(
            label: 'Brightness',
            value: b,
            min: -0.5,
            max: 0.5,
            bipolar: true,
            onChanged: (v) => push(v, c, s)),
        const SizedBox(height: 20),
        _SliderRow(
            label: 'Contrast',
            value: c,
            min: 0.5,
            max: 2.0,
            onChanged: (v) => push(b, v, s)),
        const SizedBox(height: 20),
        _SliderRow(
            label: 'Saturation',
            value: s,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => push(b, c, v)),
        const SizedBox(height: 24),
        _outlineBtn('Reset', () => push(0.0, 1.0, 1.0)),
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

class _RatioTile extends StatelessWidget {
  const _RatioTile({required this.ratio, required this.selected, required this.onTap});
  final CanvasRatio ratio;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const double box = 26;
    final double w = ratio.value >= 1 ? box : box * ratio.value;
    final double h = ratio.value >= 1 ? box / ratio.value : box;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Canvas ratio ${ratio.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: selected ? accentToken.withValues(alpha: 0.18) : cardToken,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? accentToken : Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                      color: selected ? accentToken : Colors.white70, width: 2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ratio.label,
                style: TextStyle(
                  color: selected ? accentToken : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CropSheet extends StatelessWidget {
  const CropSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final double scale = editor.selectedClip?.scale ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Canvas ratio',
            style: TextStyle(
                color: mutedToken, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ValueListenableBuilder<CanvasRatio>(
          valueListenable: canvasRatioNotifier,
          builder: (_, cur, __) => Row(
            children: <Widget>[
              for (final r in CanvasRatio.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _RatioTile(
                      ratio: r,
                      selected: r == cur,
                      onTap: () {
                        tapFeedback();
                        canvasRatioNotifier.value = r;
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SliderRow(
          label: 'Clip zoom',
          value: scale,
          min: 0.5,
          max: 3.0,
          display: '${(scale * 100).round()}%',
          minLabel: '50%',
          maxLabel: '300%',
          onChanged: editor.selectedClip == null
              ? null
              : (v) => editor.updateTranslation(scale: v),
        ),
      ],
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

  static const List<(Color, String)> _palette = <(Color, String)>[
    (Colors.cyanAccent, 'Cyan'),
    (Colors.redAccent, 'Red'),
    (Colors.greenAccent, 'Green'),
    (Colors.yellowAccent, 'Yellow'),
    (Colors.white, 'White'),
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SliderRow(
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
        const SizedBox(height: 20),
        Text('Color',
            style: TextStyle(
                color: mutedToken, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final (c, name) in _palette)
              Semantics(
                button: true,
                selected: _color == c,
                label: name,
                child: GestureDetector(
                  onTap: () {
                    tapFeedback();
                    setState(() => _color = c);
                    editor.setDrawingColor(c);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    color: Colors.transparent,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _color == c ? Colors.white : Colors.transparent,
                            width: 2),
                      ),
                      child: _color == c
                          ? const HugeIcon(
                              icon: HugeIcons.strokeRoundedTick01,
                              size: 16,
                              color: Colors.black)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: _outlineBtn('Clear', editor.clearActiveDrawing),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _primaryBtn(null, 'Save clip', editor.saveVectorDrawingAsClip),
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
      minTile: 76,
      aspect: 0.8,
      itemBuilder: (context, i) {
        final type = MaskType.values[i];
        return _ThumbTile(
          label: _cap(type.name),
          gradient: _thumbGradient(i + 3),
          onTap: () =>
              editor.updateMaskProperties(MaskProperties(type: type, feather: 10.0)),
        );
      },
    );
  }
}

class _Diamond extends StatelessWidget {
  const _Diamond({this.size = 8});
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: math.pi / 4,
        child: Container(width: size, height: size, color: accentToken),
      );
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
          'Add keyframe at playhead',
          editor.selectedClip == null
              ? null
              : () => editor.addKeyframe(Keyframe(
                    id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
                    time: editor.playhead,
                    property: KeyframeProperty.scale,
                    value: 1.0,
                  )),
        ),
        const SizedBox(height: 16),
        if (keyframes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                editor.selectedClip == null
                    ? 'Select a clip to add keyframes'
                    : 'No keyframes yet',
                style: TextStyle(color: mutedToken, fontSize: 12),
              ),
            ),
          ),
        ...keyframes.map((kf) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.only(left: 16),
              decoration:
                  BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: <Widget>[
                  const _Diamond(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _cap('${kf.property}'.split('.').last),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    '${secondsOf(kf.time).toStringAsFixed(1)}s',
                    style: TextStyle(
                      color: mutedToken,
                      fontSize: 12,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove keyframe',
                    icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedDelete02,
                        color: Color(0xFFFF6B6B),
                        size: 18),
                    onPressed: () => editor.removeKeyframe(kf.id),
                  ),
                ],
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
        _SliderRow(
          label: 'Focal length',
          value: props.focalLength,
          min: 10,
          max: 200,
          display: '${props.focalLength.round()} mm',
          minLabel: '10 mm',
          maxLabel: '200 mm',
          onChanged: editor.selectedClip == null
              ? null
              : (v) => editor.updateCameraProperties(props.copyWith(focalLength: v)),
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
              Icon(Icons.circle,
                  size: 10, color: active ? Colors.greenAccent : Colors.white24),
              const SizedBox(width: 10),
              Text('Tracking: ${active ? "active" : "off"}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _primaryBtn(
          HugeIcons.strokeRoundedTarget01,
          active ? 'Stop tracking' : 'Start auto-tracking',
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
      return Center(
        child: Text('No active plug-ins',
            style: TextStyle(color: mutedToken, fontSize: 12)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final p = plugins[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration:
              BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentToken.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: HugeIcon(
                      icon: HugeIcons.strokeRoundedGridView,
                      color: accentToken,
                      size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(p.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(p.version, style: TextStyle(color: mutedToken, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}