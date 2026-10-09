// sheets/chroma_key_sheet.dart
//
// Pro chroma-key panel (Ultra-Key style): Key / Matte / Cleanup / Spill / Color.
// Built as an inline tool panel (no modal) so preview + timeline stay visible.
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
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/chroma_key_preview.dart' show ChromaBackground;

const _bg = Color(0xFF16161A);
const _card = Color(0xFF1F1F25);
const _line = Color(0xFF2C2C34);
const _accent = Color(0xFF2EE6C5);
const _dim = Color(0xFF8A8A96);

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
  int _tab = 0;
  ChromaPreset? _preset;

  static const _tabs = ['Key', 'Matte', 'Cleanup', 'Spill', 'Color'];

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

  // Turning on for the first time should immediately show a keyed result.
  void _toggle(bool on) => _set(_k.copyWith(enabled: on), keepPreset: true);

  Future<void> _pick() async {
    HapticFeedback.selectionClick();
    final c = await widget.onPickColor?.call();
    if (c != null) _set(_k.copyWith(keyColor: c, enabled: true));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Material(
      color: _bg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            _outputRow(),
            _presetRow(),
            _tabBar(),
            const Divider(height: 1, color: _line),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: _k.enabled ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !_k.enabled,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + (bottom > 0 ? 0 : 4)),
                      child: _content(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ header
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
        child: Row(children: [
          const Text('Chroma key',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _k.enabled,
              activeColor: _accent,
              onChanged: _toggle,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt_rounded, color: _dim),
            onPressed: () {
              HapticFeedback.lightImpact();
              _set(_k.reset());
            },
          ),
          IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.check_rounded, color: _accent),
            onPressed: widget.onClose,
          ),
        ]),
      );

  // -------------------------------------------- output view + preview bg
  Widget _outputRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Row(children: [
          Expanded(
            child: _Segmented<ChromaOutput>(
              value: _k.output,
              items: const {
                ChromaOutput.composite: 'Composite',
                ChromaOutput.matte: 'Matte',
                ChromaOutput.source: 'Source',
              },
              onChanged: (v) => _set(_k.copyWith(output: v), keepPreset: true),
            ),
          ),
          const SizedBox(width: 10),
          for (final b in ChromaBackground.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => widget.onBackgroundChanged?.call(b),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: switch (b) {
                      ChromaBackground.black => Colors.black,
                      ChromaBackground.white => Colors.white,
                      ChromaBackground.gray => const Color(0xFF7F7F7F),
                      ChromaBackground.checker => const Color(0xFF3A3A3D),
                    },
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: widget.background == b ? _accent : _line,
                      width: widget.background == b ? 2 : 1,
                    ),
                  ),
                  child: b == ChromaBackground.checker
                      ? const Icon(Icons.grid_on_rounded, size: 13, color: Colors.white54)
                      : null,
                ),
              ),
            ),
        ]),
      );

  // ------------------------------------------------------------ presets
  Widget _presetRow() {
    const names = {
      ChromaPreset.defaultKey: 'Default',
      ChromaPreset.greenScreen: 'Green screen',
      ChromaPreset.blueScreen: 'Blue screen',
      ChromaPreset.aggressive: 'Aggressive',
      ChromaPreset.softEdges: 'Soft edges',
      ChromaPreset.relaxed: 'Relaxed',
    };
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final e in names.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _preset == e.key,
                showCheckmark: false,
                labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: _preset == e.key ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w500),
                backgroundColor: _card,
                selectedColor: _accent,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  _set(_k.applyPreset(e.key).copyWith(enabled: true), keepPreset: true);
                  setState(() => _preset = e.key);
                },
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- tabs
  Widget _tabBar() => SizedBox(
        height: 42,
        child: Row(children: [
          for (int i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_tabs[i],
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400,
                          color: _tab == i ? Colors.white : _dim)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 2.5,
                    width: _tab == i ? 22 : 0,
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ]),
              ),
            ),
        ]),
      );

  Widget _content() {
    switch (_tab) {
      case 0:
        return _keyTab();
      case 1:
        return Column(children: [
          _P('Highlight', _k.highlight, 0, 100, 0, (v) => _set(_k.copyWith(highlight: v))),
          _P('Shadow', _k.shadow, 0, 100, 0, (v) => _set(_k.copyWith(shadow: v))),
          _P('Pedestal', _k.pedestal, 0, 100, 0, (v) => _set(_k.copyWith(pedestal: v))),
        ]);
      case 2:
        return Column(children: [
          _P('Choke', _k.choke, -100, 100, 0, (v) => _set(_k.copyWith(choke: v))),
          _P('Soften', _k.soften, 0, 100, 0, (v) => _set(_k.copyWith(soften: v))),
          _P('Contrast', _k.contrast, 0, 100, 0, (v) => _set(_k.copyWith(contrast: v))),
          _P('Mid point', _k.midPoint, 0, 100, ChromaKey.dMidPoint, (v) => _set(_k.copyWith(midPoint: v))),
        ]);
      case 3:
        return Column(children: [
          _P('Spill', _k.spill, 0, 100, ChromaKey.dSpill, (v) => _set(_k.copyWith(spill: v))),
          _P('Range', _k.spillRange, 0, 100, ChromaKey.dSpillRange, (v) => _set(_k.copyWith(spillRange: v))),
          _P('Desaturate', _k.desaturate, 0, 100, 0, (v) => _set(_k.copyWith(desaturate: v))),
          _P('Luma restore', _k.spillLuma, 0, 100, 0, (v) => _set(_k.copyWith(spillLuma: v))),
        ]);
      default:
        return Column(children: [
          _P('Saturation', _k.saturation, 0, 200, ChromaKey.dSaturation, (v) => _set(_k.copyWith(saturation: v))),
          _P('Hue', _k.hue, -180, 180, 0, (v) => _set(_k.copyWith(hue: v))),
          _P('Luminance', _k.luminance, -100, 100, 0, (v) => _set(_k.copyWith(luminance: v))),
        ]);
    }
  }

  Widget _keyTab() {
    final hsv = HSVColor.fromColor(_k.keyColor);
    void setHsv(HSVColor c) => _set(_k.copyWith(keyColor: c.toColor()));

    const quick = [
      Color(0xFF00B140), // broadcast green
      Color(0xFF00FF00), // pure green
      Color(0xFF0047BB), // broadcast blue
      Color(0xFF0000FF), // pure blue
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Row(children: [
        // eyedropper
        GestureDetector(
          onTap: _pick,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _k.keyColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.colorize_rounded, color: _accent, size: 20),
              const SizedBox(width: 6),
              const Text('Pick', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Text('#${(_k.keyColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
            style: const TextStyle(color: _dim, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
        const Spacer(),
        for (final c in quick)
          GestureDetector(
            onTap: () => _set(_k.copyWith(keyColor: c)),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _k.keyColor.toARGB32() == c.toARGB32() ? Colors.white : Colors.transparent, width: 2),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      _GradSlider(
        label: 'Hue',
        value: hsv.hue,
        max: 360,
        colors: [for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()],
        onChanged: (v) => setHsv(hsv.withHue(v)),
      ),
      _GradSlider(
        label: 'Sat',
        value: hsv.saturation * 100,
        max: 100,
        colors: [HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(), HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor()],
        onChanged: (v) => setHsv(hsv.withSaturation(v / 100)),
      ),
      _GradSlider(
        label: 'Val',
        value: hsv.value * 100,
        max: 100,
        colors: [Colors.black, HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor()],
        onChanged: (v) => setHsv(hsv.withValue(v / 100)),
      ),
      const SizedBox(height: 4),
      _P('Tolerance', _k.similarity, 0, 100, ChromaKey.dSimilarity, (v) => _set(_k.copyWith(similarity: v))),
      _P('Transparency', _k.smoothness, 0, 100, ChromaKey.dSmoothness, (v) => _set(_k.copyWith(smoothness: v))),
    ]);
  }
}

// ======================================================================
// Parameter slider row. Double-tap the label/value to reset to default.
// ======================================================================
class _P extends StatelessWidget {
  const _P(this.label, this.value, this.min, this.max, this.def, this.onChanged);
  final String label;
  final double value, min, max, def;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = (value - def).abs() > 0.5;
    return SizedBox(
      height: 42,
      child: Row(children: [
        GestureDetector(
          onDoubleTap: () {
            HapticFeedback.lightImpact();
            onChanged(def);
          },
          child: SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(
                    color: changed ? Colors.white : Colors.white70,
                    fontSize: 13.5,
                    fontWeight: changed ? FontWeight.w600 : FontWeight.w400)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _accent,
              inactiveTrackColor: _line,
              thumbColor: Colors.white,
              overlayColor: _accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(color: _dim, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

// Slider with a gradient track (for hue / saturation / value).
class _GradSlider extends StatelessWidget {
  const _GradSlider({
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
        height: 34,
        child: Row(children: [
          SizedBox(width: 40, child: Text(label, style: const TextStyle(color: _dim, fontSize: 12.5))),
          Expanded(
            child: Stack(alignment: Alignment.center, children: [
              Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2),
                ),
                child: Slider(value: value.clamp(0, max), min: 0, max: max, onChanged: onChanged),
              ),
            ]),
          ),
        ]),
      );
}

// Small segmented control.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
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