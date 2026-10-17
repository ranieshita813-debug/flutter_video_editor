import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
export 'keyframes_sheet.dart';

// ============================================================================
// Design notes
// ----------------------------------------------------------------------------
// CapCut-style docked panels (✕ title ✓ header, thumbnail tiles, thin sliders
// with a white thumb) with Premiere-style numeric readouts (tabular figures).
// Colors come from the tokens in editor_helpers.dart: surfaceToken, cardToken,
// accentToken, mutedToken, dividerToken.
//
// Sheets are content only. To get the ✕ / ✓ header, wrap one in
// [ToolSheetFrame] from the host that shows it:
//
//   ToolSheetFrame(title: 'Color', onClose: closePanel, child: const ColorGradingSheet())
//
// The frame needs a bounded height from its parent.
// ============================================================================

const Color _canvasDark = Color(0xFF1B1B20);
const double _pad = 16;

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
    // The sheets use InkWell / ChoiceChip, which need a Material ancestor.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: <Widget>[
          _SheetHeader(title: title, onClose: onClose, onApply: onApply ?? onClose),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onClose, required this.onApply});

  final String title;
  final VoidCallback onClose;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: dividerToken))),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Cancel',
            onPressed: () {
              tapFeedback();
              onClose();
            },
            icon: const Icon(PhosphorIconsRegular.x, color: Colors.white, size: 22),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Apply',
            onPressed: () {
              tapFeedback();
              onApply();
            },
            icon: const Icon(PhosphorIconsRegular.check, color: accentToken, size: 24),
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

PhosphorIconData _transitionIcon(TransitionType t) => switch (t) {
      TransitionType.none => PhosphorIconsRegular.prohibit,
      TransitionType.fade => PhosphorIconsRegular.dotsSix,
      TransitionType.slide => PhosphorIconsRegular.sliders,
      TransitionType.zoom => PhosphorIconsRegular.magnifyingGlassPlus,
      TransitionType.blur => PhosphorIconsRegular.circle,
    };

/// Opens the transition sheet. Returns the chosen type when applied, or null
/// when cancelled. [onApply] receives the type and duration in seconds.
///
/// Pass [onApply] — without it, applying only returns the type and nothing is
/// written to the project.
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
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _TransitionPanel(initial: initial, initialSeconds: initialSeconds, onApply: onApply),
  );
}

class _TransitionPanel extends StatefulWidget {
  const _TransitionPanel({required this.initial, required this.initialSeconds, this.onApply});

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
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
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
              padding: const EdgeInsets.fromLTRB(_pad, 4, _pad, 20),
              child: _SliderRow(
                label: 'Duration',
                value: _seconds,
                min: 0.1,
                max: 2.0,
                display: '${_seconds.toStringAsFixed(1)}s',
                // Nothing to time when there is no transition.
                onChanged: _type == TransitionType.none ? null : (v) => setState(() => _seconds = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Shared widgets
// ----------------------------------------------------------------------------
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

EdgeInsets _listPad(BuildContext context) =>
    EdgeInsets.fromLTRB(_pad, _pad, _pad, _pad + MediaQuery.paddingOf(context).bottom);

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
        decoration: BoxDecoration(color: cardToken, borderRadius: BorderRadius.circular(12)),
        child: child,
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: const TextStyle(color: mutedToken, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, this.icon = PhosphorIconsRegular.handPointing});
  final String text;
  final PhosphorIconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PhosphorIcon(icon, color: Colors.white24, size: 28),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: mutedToken, fontSize: 12)),
          ],
        ),
      );
}

/// Horizontal row of single-select chips.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.options, required this.selected, required this.onSelected});
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o),
                selected: o == selected,
                showCheckmark: false,
                selectedColor: accentToken,
                backgroundColor: cardToken,
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: o == selected ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  tapFeedback();
                  onSelected(o);
                },
              ),
            ),
        ],
      ),
    );
  }
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
    final String shown = display ?? v.toStringAsFixed(2);
    final bool enabled = onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label,
                style: TextStyle(
                    color: enabled ? Colors.white : mutedToken, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              shown,
              style: TextStyle(
                color: enabled ? accentToken : mutedToken,
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
              Slider(
                value: v,
                min: min,
                max: max,
                semanticFormatterCallback: (_) => '$label $shown',
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (minLabel != null && maxLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(minLabel!, style: const TextStyle(color: mutedToken, fontSize: 10)),
                Text(maxLabel!, style: const TextStyle(color: mutedToken, fontSize: 10)),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _primaryBtn(PhosphorIconData? icon, String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentToken,
          foregroundColor: Colors.black,
          disabledBackgroundColor: cardToken,
          disabledForegroundColor: mutedToken,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              PhosphorIcon(icon, color: onPressed == null ? mutedToken : Colors.black, size: 16),
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
        side: const BorderSide(color: dividerToken),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size.fromHeight(46),
        foregroundColor: Colors.white,
        disabledForegroundColor: mutedToken,
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
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: dividerToken))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Semantics(
                button: true,
                selected: i == index,
                child: InkWell(
                  onTap: () {
                    tapFeedback();
                    onChanged(i);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: i == index ? accentToken : Colors.transparent, width: 2),
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
  final PhosphorIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
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
                        border: Border.all(color: selected ? accentToken : Colors.transparent, width: 2),
                      ),
                      child: icon == null
                          ? null
                          : Center(child: PhosphorIcon(icon!, size: 22, color: selected ? accentToken : Colors.white70)),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(color: accentToken, shape: BoxShape.circle),
                        child: const PhosphorIcon(PhosphorIconsRegular.check, size: 10, color: Colors.black),
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

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minTile = 100,
    this.aspect = 1,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minTile;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final int cols = colsCount(c.maxWidth - 2 * _pad, minTile);
      return GridView.builder(
        padding: _listPad(context),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          childAspectRatio: aspect,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    });
  }
}

/// Text-only chip tile, used for fonts and emoji.
Widget _tile({required Widget child, required VoidCallback onTap, bool selected = false}) => InkWell(
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
// Audio
// ----------------------------------------------------------------------------
class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  static const List<String> _voiceEffects = ['Normal', 'Deep', 'Robot', 'Chipmunk', 'Echo'];
  static const List<String> _eqPresets = ['Flat', 'Bass boost', 'Treble boost', 'Vocal', 'Pop', 'Rock'];

  Future<void> _pickAudio(BuildContext context, EditorController editor) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null) {
        messenger?.showSnackBar(const SnackBar(content: Text('Couldn’t read that file. Try another.')));
        return;
      }
      editor.addAudioTrack(file.path!, trackName: file.name);
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('Couldn’t open the file picker. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final bool hasAudio = clip != null && (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final bool isVideo = clip?.clipType == ClipType.video;
    final ap = clip?.audioProperties ?? const AudioProperties();
    // The volume slider writes to audioProperties, so it must read from there too.
    final double volume = ap.volume;

    return ListView(
      padding: _listPad(context),
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
                child: const Center(
                  child: PhosphorIcon(PhosphorIconsRegular.musicNote, color: accentToken, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Add audio track',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Place a soundtrack on the timeline', style: TextStyle(color: mutedToken, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add audio track',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Material(
                    color: accentToken,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        tapFeedback();
                        _pickAudio(context, editor);
                      },
                      child: const Center(
                        child: PhosphorIcon(PhosphorIconsRegular.plus, color: Colors.black, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isVideo) ...<Widget>[
          const SizedBox(height: 12),
          _outlineBtn('Extract audio from video', editor.extractAudioFromSelectedClip),
        ],
        if (!hasAudio)
          const _EmptyHint(text: 'Select an audio or video clip to adjust its sound.')
        else ...<Widget>[
          const _SectionLabel('Levels'),
          _Card(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: <Widget>[
                _SliderRow(
                  label: 'Volume',
                  value: volume,
                  min: 0,
                  max: 2,
                  display: '${(volume * 100).round()}%',
                  minLabel: '0%',
                  maxLabel: '200%',
                  onChanged: (v) => editor.updateAudioProperties(ap.copyWith(volume: v)),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: 'Fade in',
                  value: ap.fadeIn.inMilliseconds / 1000.0,
                  min: 0,
                  max: 5,
                  display: '${(ap.fadeIn.inMilliseconds / 1000.0).toStringAsFixed(1)}s',
                  onChanged: (v) => editor.updateAudioProperties(
                    ap.copyWith(fadeIn: Duration(milliseconds: (v * 1000).round())),
                  ),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: 'Fade out',
                  value: ap.fadeOut.inMilliseconds / 1000.0,
                  min: 0,
                  max: 5,
                  display: '${(ap.fadeOut.inMilliseconds / 1000.0).toStringAsFixed(1)}s',
                  onChanged: (v) => editor.updateAudioProperties(
                    ap.copyWith(fadeOut: Duration(milliseconds: (v * 1000).round())),
                  ),
                ),
              ],
            ),
          ),
          const _SectionLabel('Voice'),
          _Card(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: <Widget>[
                _SliderRow(
                  label: 'Pitch',
                  value: ap.pitch,
                  min: 0.5,
                  max: 2.0,
                  display: '${ap.pitch.toStringAsFixed(2)}x',
                  onChanged: (v) => editor.updateAudioProperties(ap.copyWith(pitch: v)),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: 'Noise reduction',
                  value: ap.noiseReduction,
                  min: 0,
                  max: 1.0,
                  display: '${(ap.noiseReduction * 100).round()}%',
                  onChanged: (v) => editor.updateAudioProperties(ap.copyWith(noiseReduction: v)),
                ),
              ],
            ),
          ),
          const _SectionLabel('Voice effect'),
          _ChipRow(
            options: _voiceEffects,
            selected: _matchOption(_voiceEffects, ap.voiceEffect),
            onSelected: (v) => editor.updateAudioProperties(ap.copyWith(voiceEffect: v)),
          ),
          const _SectionLabel('Equalizer preset'),
          _ChipRow(
            options: _eqPresets,
            selected: _matchOption(_eqPresets, ap.equalizerPreset),
            onSelected: (v) => editor.updateAudioProperties(ap.copyWith(equalizerPreset: v)),
          ),
        ],
      ],
    );
  }

  /// Matches a stored value to a chip label, ignoring case, so values saved as
  /// "Bass Boost" still highlight the "Bass boost" chip.
  static String _matchOption(List<String> options, String stored) => options.firstWhere(
        (o) => o.toLowerCase() == stored.toLowerCase(),
        orElse: () => '',
      );
}

// ----------------------------------------------------------------------------
// Text and animation
// ----------------------------------------------------------------------------
class _AnimatedTextTile extends StatelessWidget {
  const _AnimatedTextTile({
    required this.style,
    required this.selected,
    required this.onTap,
    required this.animation,
  });

  final TextAnimationStyle style;
  final bool selected;
  final VoidCallback onTap;

  /// One controller shared by every tile, instead of one ticker per tile.
  final Animation<double> animation;

  static const TextStyle _sample = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold);

  Widget _sampleFor(double val) {
    switch (style) {
      case TextAnimationStyle.fadeIn:
        return Opacity(opacity: val, child: const Text('Aa', style: _sample));
      case TextAnimationStyle.typewriter:
        final int count = (val * 4).round().clamp(1, 4);
        return Text('Text'.substring(0, count), style: _sample.copyWith(fontSize: 16));
      case TextAnimationStyle.slideUp:
        return Transform.translate(offset: Offset(0, (1 - val) * 12), child: const Text('Aa', style: _sample));
      case TextAnimationStyle.bounce:
        return Transform.scale(
            scale: 0.6 + 0.5 * Curves.elasticOut.transform(val), child: const Text('Aa', style: _sample));
      case TextAnimationStyle.scaleUp:
        return Transform.scale(scale: 0.6 + 0.5 * val, child: const Text('Aa', style: _sample));
      case TextAnimationStyle.rotateIn:
        return Transform.rotate(angle: (1 - val) * math.pi / 2, child: const Text('Aa', style: _sample));
      case TextAnimationStyle.glowPulse:
      case TextAnimationStyle.neonFlicker:
        return Text('Aa',
            style: _sample.copyWith(shadows: <Shadow>[Shadow(color: const Color(0xFF00E5FF), blurRadius: val * 12)]));
      default:
        return Text('Aa', style: _sample.copyWith(color: selected ? accentToken : Colors.white70));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: _cap(style.name),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: cardToken,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? accentToken : Colors.transparent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Container(
                  color: _canvasDark,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (_, __) => _sampleFor(animation.value),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                color: selected ? accentToken : cardToken,
                alignment: Alignment.center,
                child: Text(
                  _cap(style.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TextAnimationSheet extends StatefulWidget {
  const TextAnimationSheet({super.key});

  @override
  State<TextAnimationSheet> createState() => _TextAnimationSheetState();
}

class _TextAnimationSheetState extends State<TextAnimationSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController(text: 'Sample text');
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  String _selectedFont = 'Ubuntu Sans';
  TextAnimationStyle _anim = TextAnimationStyle.fadeIn;
  int _tab = 0;
  String? _syncedId;

  static const List<String> _fonts = <String>['Ubuntu Sans', 'Ubuntu', 'Unbounded', 'Roboto', 'Arial', 'Montserrat', 'Inter'];

  @override
  void dispose() {
    _pulse.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  /// When a different text clip is selected, load its text into the field so
  /// "Update" never overwrites it with the placeholder.
  void _syncFrom(TimelineClip? clip) {
    if (clip?.id == _syncedId) return;
    _syncedId = clip?.id;
    if (clip != null && (clip.clipType == ClipType.text || clip.clipType == ClipType.caption)) {
      _selectedFont = clip.fontFamily;
      _anim = clip.textAnimationStyle;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ctrl.text = clip.label;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    _syncFrom(selectedClip);
    final bool editing = selectedClip?.clipType == ClipType.text;
    const styles = TextAnimationStyle.values;

    return Column(
      children: <Widget>[
        _Tabs(
          labels: const <String>['Font', 'Animation'],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 14, _pad, 0),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.done,
            onChanged: (val) {
              if (editing) {
                final String text = val.trim().isEmpty ? 'Text' : val;
                editor.updateSelectedTextProperties(
                    text: text, fontFamily: _selectedFont, textAnimationStyle: _anim);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Text content',
              hintStyle: const TextStyle(color: mutedToken),
              filled: true,
              fillColor: cardToken,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              suffixIcon: IconButton(
                tooltip: 'Clear text',
                icon: const Icon(PhosphorIconsRegular.xCircle, color: mutedToken, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  if (editing) {
                    editor.updateSelectedTextProperties(
                        text: 'Text', fontFamily: _selectedFont, textAnimationStyle: _anim);
                  }
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _ResponsiveGrid(
                  key: const ValueKey<String>('fonts'),
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
                  minTile: 100,
                  aspect: 0.85,
                  itemBuilder: (context, i) {
                    final style = styles[i];
                    return _AnimatedTextTile(
                      style: style,
                      selected: style == _anim,
                      animation: _pulse,
                      onTap: () {
                        tapFeedback();
                        setState(() => _anim = style);
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(_pad, 4, _pad, _pad + MediaQuery.paddingOf(context).bottom),
          child: _primaryBtn(
            null,
            editing ? 'Update selected text' : 'Add text clip',
            () {
              final String text = _ctrl.text.trim().isEmpty ? 'Text' : _ctrl.text;
              if (editing) {
                editor.updateSelectedTextProperties(
                    text: text, fontFamily: _selectedFont, textAnimationStyle: _anim);
              } else {
                editor.addTextOverlay(text, fontFamily: _selectedFont, animationStyle: _anim);
              }
            },
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Stickers
// ----------------------------------------------------------------------------
class StickersSheet extends StatelessWidget {
  const StickersSheet({super.key});

  static const List<String> _emojis = <String>[
    '🔥', '✨', '⚡', '🎉', '❤️', '🌟', '🎬', '👏', '🚀', '💯', '💥', '⭐', '🎈', '🏆', '💎'
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      itemCount: _emojis.length,
      minTile: 64,
      itemBuilder: (context, i) => _tile(
        onTap: () => editor.addTextOverlay(_emojis[i], fontFamily: 'Ubuntu Sans'),
        child: Text(_emojis[i], style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Effects and filters
// ----------------------------------------------------------------------------
class EffectsSheet extends StatelessWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final currentEffect = selectedClip?.effect ?? VideoEffect.none;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 14, _pad, 0),
          child: Row(
            children: <Widget>[
              Text(isFilterMode ? 'Filters' : 'Effects',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (selectedClip == null)
                const Text('Select a clip to apply', style: TextStyle(color: mutedToken, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: _ResponsiveGrid(
            itemCount: VideoEffect.values.length,
            minTile: 76,
            aspect: 0.8,
            itemBuilder: (context, i) {
              final fx = VideoEffect.values[i];
              final bool isNone = fx == VideoEffect.none;
              return _ThumbTile(
                label: _cap(fx.name),
                selected: fx == currentEffect,
                icon: isNone ? PhosphorIconsRegular.prohibit : null,
                gradient: isNone ? null : _thumbGradient(i),
                onTap: () => editor.applyEffect(fx),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Color grading
// ----------------------------------------------------------------------------
class ColorGradingSheet extends StatelessWidget {
  const ColorGradingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final hasClip = context.select<EditorController, bool>((e) => e.selectedClip != null);
    final cg = context.select<EditorController, ColorGradingSettings?>((e) => e.selectedClip?.colorGrading);
    final double b = cg?.brightness ?? 0.0;
    final double c = cg?.contrast ?? 1.0;
    final double s = cg?.saturation ?? 1.0;
    final bool isDefault = b.abs() < 0.005 && (c - 1).abs() < 0.005 && (s - 1).abs() < 0.005;

    void push(double nb, double nc, double ns) =>
        editor.updateColorGrading(ColorGradingSettings(brightness: nb, contrast: nc, saturation: ns));

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        if (!hasClip) const _EmptyHint(text: 'Select a clip to grade its color.'),
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            children: <Widget>[
              _SliderRow(
                label: 'Brightness',
                value: b,
                min: -0.5,
                max: 0.5,
                bipolar: true,
                display: '${b >= 0 ? '+' : '−'}${b.abs().toStringAsFixed(2)}',
                onChanged: hasClip ? (v) => push(v, c, s) : null,
              ),
              const SizedBox(height: 8),
              _SliderRow(
                label: 'Contrast',
                value: c,
                min: 0.5,
                max: 2.0,
                display: '${(c * 100).round()}%',
                onChanged: hasClip ? (v) => push(b, v, s) : null,
              ),
              const SizedBox(height: 8),
              _SliderRow(
                label: 'Saturation',
                value: s,
                min: 0.0,
                max: 2.0,
                display: '${(s * 100).round()}%',
                onChanged: hasClip ? (v) => push(b, c, v) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _outlineBtn('Reset', hasClip && !isDefault ? () => push(0.0, 1.0, 1.0) : null),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Canvas and crop
// ----------------------------------------------------------------------------
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

final ValueNotifier<CanvasRatio> canvasRatioNotifier = ValueNotifier<CanvasRatio>(CanvasRatio.r16x9);

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
      excludeSemantics: true,
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
                  border: Border.all(color: selected ? accentToken : Colors.white70, width: 2),
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
    final editor = context.read<EditorController>();
    final scale = context.select<EditorController, double>((e) => e.selectedClip?.scale ?? 1.0);
    final hasClip = context.select<EditorController, bool>((e) => e.selectedClip != null);

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        const Text('Canvas ratio', style: TextStyle(color: mutedToken, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ValueListenableBuilder<CanvasRatio>(
          valueListenable: canvasRatioNotifier,
          builder: (_, cur, __) => Row(
            children: <Widget>[
              for (final r in CanvasRatio.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
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
        const _SectionLabel('Clip'),
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: _SliderRow(
            label: 'Zoom',
            value: scale,
            min: 0.5,
            max: 3.0,
            display: '${(scale * 100).round()}%',
            minLabel: '50%',
            maxLabel: '300%',
            onChanged: hasClip ? (v) => editor.updateTranslation(scale: v) : null,
          ),
        ),
        if (!hasClip) const _EmptyHint(text: 'Select a clip to zoom it.'),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Vector drawing
// ----------------------------------------------------------------------------
class VectorDrawingSheet extends StatefulWidget {
  const VectorDrawingSheet({super.key});

  @override
  State<VectorDrawingSheet> createState() => _VectorDrawingSheetState();
}

class _VectorDrawingSheetState extends State<VectorDrawingSheet> {
  Color _color = Colors.cyanAccent;
  double _width = 4.0;

  static const _palette = <(Color, String)>[
    (Colors.cyanAccent, 'Cyan'),
    (Colors.redAccent, 'Red'),
    (Colors.greenAccent, 'Green'),
    (Colors.yellowAccent, 'Yellow'),
    (Colors.orangeAccent, 'Orange'),
    (Colors.pinkAccent, 'Pink'),
    (Colors.white, 'White'),
  ];

  @override
  void initState() {
    super.initState();
    // Make the editor agree with what this sheet shows on first open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editor = context.read<EditorController>();
      editor.setStrokeWidth(_width);
      editor.setDrawingColor(_color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        // Live stroke preview.
        Container(
          height: 56,
          decoration: BoxDecoration(color: _canvasDark, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Container(
            width: 140,
            height: _width,
            decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(_width / 2)),
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: _SliderRow(
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
        ),
        const _SectionLabel('Color'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final (c, name) in _palette)
              Semantics(
                button: true,
                selected: _color == c,
                label: name,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    tapFeedback();
                    setState(() => _color = c);
                    editor.setDrawingColor(c);
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 2),
                        ),
                        child: _color == c
                            ? const PhosphorIcon(PhosphorIconsRegular.check, size: 14, color: Colors.black)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(child: _outlineBtn('Clear', editor.clearActiveDrawing)),
            const SizedBox(width: 12),
            Expanded(child: _primaryBtn(null, 'Save clip', editor.saveVectorDrawingAsClip)),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Mask
// ----------------------------------------------------------------------------
class MaskSheet extends StatefulWidget {
  const MaskSheet({super.key});

  @override
  State<MaskSheet> createState() => _MaskSheetState();
}

class _MaskSheetState extends State<MaskSheet> {
  MaskType? _type;
  double _feather = 10.0;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return Column(
      children: <Widget>[
        Expanded(
          child: _ResponsiveGrid(
            itemCount: MaskType.values.length,
            minTile: 76,
            aspect: 0.8,
            itemBuilder: (context, i) {
              final type = MaskType.values[i];
              return _ThumbTile(
                label: _cap(type.name),
                selected: type == _type,
                gradient: _thumbGradient(i + 3),
                onTap: () {
                  setState(() => _type = type);
                  editor.updateMaskProperties(MaskProperties(type: type, feather: _feather));
                },
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(_pad, 0, _pad, _pad + MediaQuery.paddingOf(context).bottom),
          child: _SliderRow(
            label: 'Feather',
            value: _feather,
            min: 0,
            max: 50,
            display: _feather.round().toString(),
            // Needs a shape to feather.
            onChanged: _type == null
                ? null
                : (v) {
                    setState(() => _feather = v);
                    editor.updateMaskProperties(MaskProperties(type: _type!, feather: v));
                  },
          ),
        ),
      ],
    );
  }
}


// ----------------------------------------------------------------------------
// Camera
// ----------------------------------------------------------------------------
class CameraSettingsSheet extends StatelessWidget {
  const CameraSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final props = selectedClip?.cameraProperties ?? const CameraProperties();

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        if (selectedClip == null) const _EmptyHint(text: 'Select a clip to change its camera.'),
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: _SliderRow(
            label: 'Focal length',
            value: props.focalLength,
            min: 10,
            max: 200,
            display: '${props.focalLength.round()} mm',
            minLabel: '10 mm',
            maxLabel: '200 mm',
            onChanged: selectedClip == null
                ? null
                : (v) => editor.updateCameraProperties(props.copyWith(focalLength: v)),
          ),
        ),
        const SizedBox(height: 16),
        _outlineBtn(
          'Reset',
          selectedClip == null ? null : () => editor.updateCameraProperties(const CameraProperties()),
        ),
      ],
    );
  }
}

class CameraTrackingPanel extends StatelessWidget {
  const CameraTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final bool active = selectedClip?.trackingData.isEnabled == true;

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        _Card(
          child: Row(
            children: <Widget>[
              Icon(PhosphorIconsRegular.circle, size: 10, color: active ? Colors.greenAccent : Colors.white24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(active ? 'Tracking is on' : 'Tracking is off',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _primaryBtn(
          PhosphorIconsRegular.crosshair,
          active ? 'Stop tracking' : 'Start auto-tracking',
          selectedClip == null
              ? null
              : () => editor.updateTrackingData(TrackingData(
                    isEnabled: !active,
                    targetName: 'Subject',
                    rect: const Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
                  )),
        ),
        if (selectedClip == null) const _EmptyHint(text: 'Select a clip to track a subject.'),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Plug-ins
// ----------------------------------------------------------------------------
class PluginsSheet extends StatelessWidget {
  const PluginsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = PluginManager().activePlugins;

    if (plugins.isEmpty) {
      return const Center(child: _EmptyHint(icon: PhosphorIconsRegular.plug, text: 'No active plug-ins.'));
    }

    return ListView.builder(
      padding: _listPad(context),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final p = plugins[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Card(
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentToken.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: PhosphorIcon(PhosphorIconsRegular.gridFour, color: accentToken, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(p.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(p.version, style: const TextStyle(color: mutedToken, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}