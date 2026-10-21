// sheets/chroma_key_sheet.dart
//
// Chroma-key panel, Premiere-style mobile layout.
//
//   Quick mode (default): Colour / Quick swatches / Intensity / Shadow
//                         + "Advanced controls" link
//   Advanced mode:        Ultra-Key inspector
//                         header (fx, enable switch, reset, done)
//                         Output (Composite / Matte / Source) + preset dropdown
//                         tabs: Key / Matte / Cleanup / Spill / Color
//                         scrolling parameter rows (label, slider, value, keyframe)
//
// Also exported in this file:
//   ChromaSampleSheet      - bottom sheet for the full-screen eyedropper
//                            (hex / RGB / HSV, Cancel / Use this colour)
//   ChromaBackgroundButton - 44px button for the preview overlay that cycles
//                            the preview background
//
// Usage:
//   ChromaKeySheet(
//     value: clip.chromaKey,
//     onChanged: (k) => provider.setChromaKey(clip.id, k),
//     background: _bg,
//     onBackgroundChanged: (b) => setState(() => _bg = b),
//     onPickColor: () => _startEyedropper(),   // returns sampled colour from preview
//     onClose: provider.closeTool,
//   )

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/chroma_key_preview.dart'
    show ChromaBackground;

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------
const _deep = Color(0xFF1A1A1A); // app background, segmented tracks
const _panel = Color(0xFF232323); // inspector background
const _raised = Color(0xFF2D2D2D); // pills, buttons
const _line = Color(0xFF3A3A3A); // dividers, inactive tracks
const _divider = Color(0xFF333333);
const _text = Color(0xFFF2F2F2);
const _dim = Color(0xFFA8A8A8);
const _blue = Color(0xFF4B9BFF); // active track, playhead, underline
const _blueText = Color(0xFF6FB1FF); // scrub values, links
const _action = Color(0xFF1F6FEB); // primary buttons
const _fx = Color(0xFFA5A5FF); // "fx" badge

const _tabFigures = [FontFeature.tabularFigures()];

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------
class ChromaKeySheet extends StatefulWidget {
  const ChromaKeySheet({
    super.key,
    required this.value,
    required this.onChanged,
    this.onClose,
    this.onPickColor,
    this.background = ChromaBackground.checker,
    this.onBackgroundChanged,
  });

  final ChromaKey value;
  final ValueChanged<ChromaKey> onChanged;
  final VoidCallback? onClose;
  final Future<Color?> Function()? onPickColor;
  final ChromaBackground background;
  final ValueChanged<ChromaBackground>? onBackgroundChanged;

  @override
  State<ChromaKeySheet> createState() => _ChromaKeySheetState();
}

class _ChromaKeySheetState extends State<ChromaKeySheet> {
  late ChromaKey _k = widget.value;
  bool _advanced = false;
  int _tab = 0; // advanced tabs
  ChromaPreset? _preset;

  /// Parameters whose keyframe stopwatch is switched on (UI state only;
  /// wire to your animation model when keyframes land).
  final Set<String> _keyframed = {};

  static const _tabs = ['Key', 'Matte', 'Cleanup', 'Spill', 'Color'];

  static const _presetNames = {
    ChromaPreset.defaultKey: 'Default',
    ChromaPreset.greenScreen: 'Green screen',
    ChromaPreset.blueScreen: 'Blue screen',
    ChromaPreset.aggressive: 'Aggressive',
    ChromaPreset.softEdges: 'Soft edges',
    ChromaPreset.relaxed: 'Relaxed',
  };

  @override
  void didUpdateWidget(covariant ChromaKeySheet old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _k = widget.value;
  }

  void _set(ChromaKey k, {bool keepPreset = false}) {
    setState(() {
      _k = k;
      if (!keepPreset) _preset = null;
    });
    widget.onChanged(k);
  }

  /// Any edit in quick mode switches the effect on.
  void _quickSet(ChromaKey k) => _set(k.copyWith(enabled: true));

  void _toggle(bool on) => _set(_k.copyWith(enabled: on), keepPreset: true);

  void _reset() {
    HapticFeedback.lightImpact();
    _set(_k.reset());
  }

  void _toggleKeyframe(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_keyframed.remove(id)) _keyframed.add(id);
    });
  }

  Future<void> _pick() async {
    HapticFeedback.selectionClick();
    final c = await widget.onPickColor?.call();
    if (c == null) return;
    // After sampling, tolerance jumps to a usable value.
    final needsTolerance = _k.similarity < 5;
    _set(_k.copyWith(
      keyColor: c,
      enabled: true,
      similarity: needsTolerance ? ChromaKey.dSimilarity : _k.similarity,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _divider)),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _advanced ? _advancedPanel() : _quickPanel(),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // QUICK
  // =====================================================================
  Widget _quickPanel() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            const _FxBadge(),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Chroma key',
                  style: TextStyle(
                      color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            _IconBtn(
              tooltip: 'Reset',
              icon: Icons.restart_alt_rounded,
              color: const Color(0xFFC8C8C8),
              onTap: _reset,
            ),
            _IconBtn(
              tooltip: 'Done',
              icon: PhosphorIconsRegular.check,
              color: _blueText,
              onTap: widget.onClose,
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: [
          _quickColourRow(),
          _quickSwatches(),
          _QuickSlider(
            label: 'Intensity',
            emphasised: true,
            value: _k.similarity,
            onChanged: (v) => _quickSet(_k.copyWith(similarity: v)),
          ),
          _QuickSlider(
            label: 'Shadow',
            emphasised: _k.shadow > 0.5,
            value: _k.shadow,
            onChanged: (v) => _quickSet(_k.copyWith(shadow: v)),
          ),
          const Divider(height: 1, color: _divider),
          InkWell(
            onTap: () => setState(() => _advanced = true),
            child: SizedBox(
              height: 52,
              child: Row(children: const [
                Icon(PhosphorIconsRegular.slidersHorizontal,
                    color: _blueText, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Advanced controls · Ultra Key',
                      style: TextStyle(
                          color: _blueText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
                Icon(Icons.chevron_right_rounded, color: _blueText, size: 20),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 4),
    ]);
  }

  Widget _quickColourRow() {
    return SizedBox(
      height: 52,
      child: Row(children: [
        const SizedBox(
          width: 88,
          child: Text('Colour',
              style: TextStyle(color: _text, fontSize: 13)),
        ),
        _Swatch(color: _k.keyColor, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_hex(_k.keyColor),
              style: const TextStyle(
                  color: _blueText,
                  fontSize: 12.5,
                  fontFeatures: _tabFigures)),
        ),
        GestureDetector(
          onTap: _pick,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _action,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(children: [
              Icon(PhosphorIconsRegular.eyedropper,
                  color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('Pick',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _quickSwatches() {
    const quick = [
      Color(0xFF00B140),
      Color(0xFF00FF00),
      Color(0xFF0047BB),
      Color(0xFF0000FF),
    ];
    const names = [
      'Green screen colour',
      'Bright green',
      'Blue screen colour',
      'Bright blue',
    ];
    return SizedBox(
      height: 44,
      child: Row(children: [
        const SizedBox(
          width: 88,
          child: Text('Quick', style: TextStyle(color: _dim, fontSize: 13)),
        ),
        for (int i = 0; i < quick.length; i++)
          Semantics(
            button: true,
            label: names[i],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _quickSet(_k.copyWith(keyColor: quick[i])),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: quick[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _k.keyColor.toARGB32() == quick[i].toARGB32()
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // =====================================================================
  // ADVANCED (Ultra Key inspector)
  // =====================================================================
  Widget _advancedPanel() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _header(),
      _outputRow(),
      _tabBar(),
      const Divider(height: 1, color: _divider),
      Opacity(
        opacity: _k.enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !_k.enabled,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 264),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              child: _content(),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            const _FxBadge(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Ultra Key',
                      style: TextStyle(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text('Selected clip',
                      style: TextStyle(color: _dim, fontSize: 11)),
                ],
              ),
            ),
            // Enable switch (44px hit area)
            Semantics(
              toggled: _k.enabled,
              label: 'Enable Ultra Key',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggle(!_k.enabled),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 38,
                      height: 22,
                      padding: const EdgeInsets.all(2),
                      alignment: _k.enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: _k.enabled ? _action : const Color(0xFF4A4A4A),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _IconBtn(
              tooltip: 'Reset effect',
              icon: Icons.restart_alt_rounded,
              color: const Color(0xFFC8C8C8),
              onTap: _reset,
            ),
            _IconBtn(
              tooltip: 'Done, back to quick mode',
              icon: PhosphorIconsRegular.check,
              color: _blueText,
              onTap: () => setState(() => _advanced = false),
            ),
          ]),
        ),
      );

  Widget _outputRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            Expanded(
              child: _Segmented<ChromaOutput>(
                value: _k.output,
                items: const {
                  ChromaOutput.composite: 'Composite',
                  ChromaOutput.matte: 'Alpha',
                  ChromaOutput.source: 'Source',
                },
                onChanged: (v) =>
                    _set(_k.copyWith(output: v), keepPreset: true),
              ),
            ),
            const SizedBox(width: 10),
            _presetMenu(),
          ]),
        ),
      );

  Widget _presetMenu() {
    return PopupMenuButton<ChromaPreset>(
      tooltip: 'Setting',
      color: _raised,
      position: PopupMenuPosition.under,
      onSelected: (p) {
        HapticFeedback.selectionClick();
        _set(_k.applyPreset(p).copyWith(enabled: true), keepPreset: true);
        setState(() => _preset = p);
      },
      itemBuilder: (_) => [
        for (final e in _presetNames.entries)
          PopupMenuItem<ChromaPreset>(
            value: e.key,
            height: 44,
            child: Text(
              e.value,
              style: TextStyle(
                color: _preset == e.key ? _blueText : _text,
                fontSize: 13.5,
                fontWeight:
                    _preset == e.key ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: _raised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_preset == null ? 'Custom' : _presetNames[_preset]!,
              style: const TextStyle(color: _text, fontSize: 12.5)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, color: _text, size: 18),
        ]),
      ),
    );
  }

  Widget _tabBar() => SizedBox(
        height: 40,
        child: Row(children: [
          for (int i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_tabs[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  _tab == i ? FontWeight.w600 : FontWeight.w400,
                              color: _tab == i ? Colors.white : _dim)),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 2,
                        width: _tab == i ? 24 : 0,
                        decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(1)),
                      ),
                    ]),
              ),
            ),
        ]),
      );

  // ---- parameter row factory -------------------------------------------
  Widget _p(
    String id,
    String label,
    double value,
    double min,
    double max,
    double def,
    ValueChanged<double> onChanged,
  ) =>
      _ParamRow(
        label: label,
        value: value,
        min: min,
        max: max,
        def: def,
        onChanged: onChanged,
        keyframed: _keyframed.contains(id),
        onKeyframe: () => _toggleKeyframe(id),
      );

  Widget _content() {
    switch (_tab) {
      case 0:
        return _keyTab();
      case 1:
        return Column(children: [
          _p('highlight', 'Highlight', _k.highlight, 0, 100, 0,
              (v) => _set(_k.copyWith(highlight: v))),
          _p('shadow', 'Shadow', _k.shadow, 0, 100, 0,
              (v) => _set(_k.copyWith(shadow: v))),
          _p('pedestal', 'Pedestal', _k.pedestal, 0, 100, 0,
              (v) => _set(_k.copyWith(pedestal: v))),
        ]);
      case 2:
        return Column(children: [
          _p('choke', 'Choke', _k.choke, -100, 100, 0,
              (v) => _set(_k.copyWith(choke: v))),
          _p('soften', 'Soften', _k.soften, 0, 100, 0,
              (v) => _set(_k.copyWith(soften: v))),
          _p('contrast', 'Contrast', _k.contrast, 0, 100, 0,
              (v) => _set(_k.copyWith(contrast: v))),
          _p('midPoint', 'Mid point', _k.midPoint, 0, 100, ChromaKey.dMidPoint,
              (v) => _set(_k.copyWith(midPoint: v))),
        ]);
      case 3:
        return Column(children: [
          _p('spill', 'Spill', _k.spill, 0, 100, ChromaKey.dSpill,
              (v) => _set(_k.copyWith(spill: v))),
          _p('spillRange', 'Range', _k.spillRange, 0, 100,
              ChromaKey.dSpillRange, (v) => _set(_k.copyWith(spillRange: v))),
          _p('desaturate', 'Desaturate', _k.desaturate, 0, 100, 0,
              (v) => _set(_k.copyWith(desaturate: v))),
          _p('spillLuma', 'Luma restore', _k.spillLuma, 0, 100, 0,
              (v) => _set(_k.copyWith(spillLuma: v))),
        ]);
      default:
        return Column(children: [
          _p('saturation', 'Saturation', _k.saturation, 0, 200,
              ChromaKey.dSaturation, (v) => _set(_k.copyWith(saturation: v))),
          _p('hue', 'Hue', _k.hue, -180, 180, 0,
              (v) => _set(_k.copyWith(hue: v))),
          _p('luminance', 'Luminance', _k.luminance, -100, 100, 0,
              (v) => _set(_k.copyWith(luminance: v))),
        ]);
    }
  }

  Widget _keyTab() {
    final hsv = HSVColor.fromColor(_k.keyColor);
    void setHsv(HSVColor c) => _set(_k.copyWith(keyColor: c.toColor()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Key colour row
      SizedBox(
        height: 52,
        child: Row(children: [
          const SizedBox(
            width: 88,
            child: Text('Key colour',
                style: TextStyle(color: _text, fontSize: 13)),
          ),
          _Swatch(color: _k.keyColor, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_hex(_k.keyColor),
                style: const TextStyle(
                    color: _blueText,
                    fontSize: 12.5,
                    fontFeatures: _tabFigures)),
          ),
          Tooltip(
            message: 'Pick key colour from preview',
            child: GestureDetector(
              onTap: _pick,
              child: Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _blue),
                ),
                child: const Icon(PhosphorIconsRegular.eyedropper,
                    color: _blueText, size: 19),
              ),
            ),
          ),
          _KeyframeBtn(
            on: _keyframed.contains('keyColor'),
            onTap: () => _toggleKeyframe('keyColor'),
          ),
        ]),
      ),
      _GradRow(
        label: 'Hue',
        value: hsv.hue,
        max: 360,
        colors: [
          for (int i = 0; i <= 6; i++)
            HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()
        ],
        onChanged: (v) => setHsv(hsv.withHue(v)),
      ),
      _GradRow(
        label: 'Saturation',
        value: hsv.saturation * 100,
        max: 100,
        colors: [
          HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(),
          HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor(),
        ],
        onChanged: (v) => setHsv(hsv.withSaturation(v / 100)),
      ),
      _GradRow(
        label: 'Value',
        value: hsv.value * 100,
        max: 100,
        colors: [
          Colors.black,
          HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
        ],
        onChanged: (v) => setHsv(hsv.withValue(v / 100)),
      ),
      _p('similarity', 'Tolerance', _k.similarity, 0, 100,
          ChromaKey.dSimilarity, (v) => _set(_k.copyWith(similarity: v))),
      _p('smoothness', 'Transparency', _k.smoothness, 0, 100,
          ChromaKey.dSmoothness, (v) => _set(_k.copyWith(smoothness: v))),
    ]);
  }
}

// ======================================================================
// Small pieces
// ======================================================================

class _FxBadge extends StatelessWidget {
  const _FxBadge();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        child: Text('fx',
            style: TextStyle(
                color: _fx,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600)),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: color, size: 21),
          onPressed: onTap,
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 26});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38, width: 2),
        ),
      );
}

class _KeyframeBtn extends StatelessWidget {
  const _KeyframeBtn({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 44,
        child: IconButton(
          tooltip: on ? 'Stop animating' : 'Toggle animation',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.timer_outlined,
              size: 18, color: on ? _blueText : const Color(0xFF8C8C8C)),
          onPressed: onTap,
        ),
      );
}

SliderThemeData _sliderTheme(BuildContext context,
        {double track = 4, double thumb = 9, Color? active, Color? inactive}) =>
    SliderTheme.of(context).copyWith(
      trackHeight: track,
      activeTrackColor: active ?? _blue,
      inactiveTrackColor: inactive ?? _line,
      thumbColor: Colors.white,
      overlayColor: _blue.withValues(alpha: 0.16),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumb),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      trackShape: const RoundedRectSliderTrackShape(),
    );

// ----------------------------------------------------------------------
// Parameter row: label · slider · blue scrub value · keyframe stopwatch.
// Double-tap the label to reset to default.
// ----------------------------------------------------------------------
class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.def,
    required this.onChanged,
    required this.keyframed,
    required this.onKeyframe,
  });
  final String label;
  final double value, min, max, def;
  final ValueChanged<double> onChanged;
  final bool keyframed;
  final VoidCallback onKeyframe;

  @override
  Widget build(BuildContext context) {
    final changed = (value - def).abs() > 0.5;
    return SizedBox(
      height: 44,
      child: Row(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () {
            HapticFeedback.lightImpact();
            onChanged(def);
          },
          child: SizedBox(
            width: 88,
            child: Text(label,
                style: TextStyle(
                    color: changed ? _text : _dim,
                    fontSize: 13,
                    fontWeight: changed ? FontWeight.w500 : FontWeight.w400)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: _blueText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: _tabFigures)),
        ),
        _KeyframeBtn(on: keyframed, onTap: onKeyframe),
      ]),
    );
  }
}

// Gradient-track slider row (hue / saturation / value).
class _GradRow extends StatelessWidget {
  const _GradRow({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
  });
  final String label;
  final double value, max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: Row(children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: const TextStyle(color: _dim, fontSize: 13)),
          ),
          Expanded(
            child: Stack(alignment: Alignment.center, children: [
              Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              SliderTheme(
                data: _sliderTheme(
                  context,
                  track: 6,
                  thumb: 9,
                  active: Colors.transparent,
                  inactive: Colors.transparent,
                ),
                child: Slider(
                  // clamp(0, max) with an int literal returns num -> use 0.0
                  value: value.clamp(0.0, max),
                  min: 0,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ]),
          ),
          SizedBox(
            width: 34,
            child: Text(value.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: _blueText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontFeatures: _tabFigures)),
          ),
          const SizedBox(width: 36),
        ]),
      );
}

// Quick-mode slider: bigger thumb, white value.
class _QuickSlider extends StatelessWidget {
  const _QuickSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.emphasised = true,
  });
  final String label;
  final double value;
  final bool emphasised;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: TextStyle(
                    color: emphasised ? _text : _dim, fontSize: 13)),
          ),
          Expanded(
            child: SliderTheme(
              data: _sliderTheme(context, track: 4, thumb: 10),
              child: Slider(
                value: value.clamp(0.0, 100.0),
                min: 0,
                max: 100,
                onChanged: onChanged,
                onChangeStart: (_) => HapticFeedback.selectionClick(),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(value.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabFigures)),
          ),
        ]),
      );
}

// Segmented control (dark track, raised selected segment).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _deep,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          for (final e in items.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == e.key ? _line : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: value == e.key ? Colors.white : _dim)),
                ),
              ),
            ),
        ]),
      );
}

// ======================================================================
// Preview overlay: cycles the preview background (44px hit area).
// Place it in a Stack on top of the program monitor, e.g.
//   Positioned(right: 4, top: 4, child: ChromaBackgroundButton(...))
// ======================================================================
class ChromaBackgroundButton extends StatelessWidget {
  const ChromaBackgroundButton({
    super.key,
    required this.background,
    required this.onChanged,
  });

  final ChromaBackground background;
  final ValueChanged<ChromaBackground> onChanged;

  @override
  Widget build(BuildContext context) {
    final all = ChromaBackground.values;
    final next = all[(background.index + 1) % all.length];
    return Semantics(
      button: true,
      label: 'Cycle preview background',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: switch (background) {
                  ChromaBackground.black => Colors.black,
                  ChromaBackground.white => Colors.white,
                  ChromaBackground.gray => const Color(0xFF7F7F7F),
                  ChromaBackground.checker => const Color(0xFF3A3A3D),
                },
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: background == ChromaBackground.checker
                  ? const Icon(PhosphorIconsRegular.gridNine,
                      size: 13, color: Colors.white54)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Eyedropper bottom sheet. Show it under the full-screen source frame
// while the user taps/drags to sample; pass the live sampled colour.
//
//   ChromaSampleSheet(
//     color: sampled,
//     onCancel: () => completer.complete(null),
//     onUse: () => completer.complete(sampled),
//   )
// ======================================================================
class ChromaSampleSheet extends StatelessWidget {
  const ChromaSampleSheet({
    super.key,
    required this.color,
    required this.onCancel,
    required this.onUse,
  });

  final Color color;
  final VoidCallback onCancel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final v = color.toARGB32();
    final r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
    final hsv = HSVColor.fromColor(color);

    return Material(
      color: _panel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white38, width: 2),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_hex(color),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                fontFeatures: _tabFigures)),
                        const SizedBox(height: 2),
                        Text('R $r · G $g · B $b',
                            style: const TextStyle(
                                color: _dim,
                                fontSize: 12.5,
                                fontFeatures: _tabFigures)),
                        Text(
                            'H ${hsv.hue.round()}° · '
                            'S ${(hsv.saturation * 100).round()}% · '
                            'V ${(hsv.value * 100).round()}%',
                            style: const TextStyle(
                                color: _dim,
                                fontSize: 12.5,
                                fontFeatures: _tabFigures)),
                      ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: const [
                _FxBadge(),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Tolerance jumps to a usable value after sampling.',
                      style: TextStyle(color: _dim, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _text,
                        side: const BorderSide(color: Color(0xFF4A4A4A)),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 14,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: onUse,
                      style: FilledButton.styleFrom(
                        backgroundColor: _action,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(PhosphorIconsRegular.eyedropper,
                          size: 18),
                      label: const Text('Use this colour',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}