// lib/features/editor/widgets/text_style_sheet.dart
//
// Text style tool, CapCut x Premiere Pro hybrid (same language as
// AdjustSheet / SpeedSheet).
//  - CapCut: underline tabs (Font / Effects / Color / Layout), visual
//    tiles for fonts and effect presets, round color swatches.
//  - Premiere: hairline section bars, boxed scrubbable value fields,
//    triangle-thumb sliders, joined icon segmented control.
// All editor calls and behaviour are unchanged; edits apply live.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

const Color _card = Color(0xFF232327);
const Color _field = Color(0xFF18181B);
const Color _line = Color(0xFF2C2C31);
const Color _track = Color(0xFF45454C);
const Color _accent = Color(0xFF2DE2E6);

enum _Tab {
  font('Font'),
  effects('Effects'),
  color('Color'),
  layout('Layout');

  const _Tab(this.label);
  final String label;
}

class TextStyleSheet extends StatefulWidget {
  const TextStyleSheet({super.key});

  @override
  State<TextStyleSheet> createState() => _TextStyleSheetState();
}

class _TextStyleSheetState extends State<TextStyleSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';
  _Tab _tab = _Tab.font;

  final List<Color> _colors = const [
    Colors.white,
    Colors.black,
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00E5FF),
    Color(0xFF007AFF),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
  ];

  final List<String> _textEffects = const [
    'none',
    'outline',
    'shadow',
    'glow',
    'neon',
    '3d',
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    if (clip == null || (clip.clipType != ClipType.text && clip.clipType != ClipType.caption)) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'Select a text clip to customize style',
          style: TextStyle(color: EditorTokens.muted, fontFamily: 'Poppins'),
        ),
      );
    }

    final ts = clip.textStyle;
    final fonts = editor.availableFonts
        .where((f) => f.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    final Widget body = switch (_tab) {
      _Tab.font => _fontTab(editor, clip, fonts),
      _Tab.effects => _effectsTab(editor, ts),
      _Tab.color => _colorTab(editor, ts),
      _Tab.layout => _layoutTab(editor, ts),
    };

    return Column(
      children: [
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() {
            _searchQuery = q;
            if (q.isNotEmpty) _tab = _Tab.font; // searching means fonts
          }),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search fonts & styles...',
        ),
        _tabBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: body,
          ),
        ),
      ],
    );
  }

  // ---- Tabs -----------------------------------------------------------------

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in _Tab.values)
            Semantics(
              button: true,
              selected: t == _tab,
              label: t.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tab = t);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.label,
                        style: TextStyle(
                          color: t == _tab ? EditorTokens.text : EditorTokens.muted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 7),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 2.5,
                        width: 22,
                        decoration: BoxDecoration(
                          color: t == _tab ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Premiere-style hairline section bar.
  Widget _bar(String title) => Container(
        height: 32,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: _card,
          border: Border(top: BorderSide(color: _line), bottom: BorderSide(color: _line)),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: EditorTokens.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
      );

  // ---- Font tab -------------------------------------------------------------

  Widget _fontTab(EditorController editor, dynamic clip, List<String> fonts) {
    if (fonts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text('No fonts match your search',
              style: TextStyle(color: EditorTokens.muted, fontSize: 12, fontFamily: 'Poppins')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: LayoutBuilder(builder: (context, box) {
        const int cols = 4;
        const double gap = 8;
        final double w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final font in fonts)
              _fontTile(font, w, clip.fontFamily == font, () => editor.updateSelectedClipFont(font)),
          ],
        );
      }),
    );
  }

  Widget _fontTile(String font, double w, bool on, VoidCallback f) {
    return Semantics(
      button: true,
      selected: on,
      label: font,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          f();
        },
        child: Container(
          width: w,
          height: 68,
          decoration: BoxDecoration(
            color: on ? _accent.withAlpha(28) : _card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? _accent : Colors.transparent, width: 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Aa',
                  style: TextStyle(
                      color: on ? _accent : EditorTokens.text,
                      fontSize: 22,
                      fontFamily: font)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(font,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: on ? _accent : EditorTokens.muted,
                        fontSize: 9.5,
                        fontFamily: 'Poppins')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Effects tab ----------------------------------------------------------

  Widget _effectsTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Presets'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _textEffects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _effectTile(editor, ts, _textEffects[i]),
            ),
          ),
        ),
        _bar('Stroke'),
        _ParamSlider(
          label: 'Width',
          value: ts.strokeWidth,
          min: 0,
          max: 10,
          resetTo: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              strokeWidth: val,
              strokeColor: val > 0 && ts.strokeColor == Colors.transparent
                  ? Colors.black
                  : ts.strokeColor,
            ),
          ),
        ),
        _swatches(
          ts.strokeColor,
          (c) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              strokeColor: c,
              strokeWidth: ts.strokeWidth == 0 ? 2.0 : ts.strokeWidth,
            ),
          ),
        ),
        _bar('Shadow'),
        _ParamSlider(
          label: 'Blur',
          value: ts.shadowBlurRadius,
          min: 0,
          max: 20,
          resetTo: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              shadowBlurRadius: val,
              shadowColor: val > 0 && ts.shadowColor == Colors.transparent
                  ? Colors.black87
                  : ts.shadowColor,
            ),
          ),
        ),
      ],
    );
  }

  /// Preview tile: "Ab" drawn with an approximation of the effect.
  Widget _effectTile(EditorController editor, TextStyleProperties ts, String effect) {
    final bool on = ts.textEffect == effect;
    const Color cyan = Color(0xFF00E5FF);
    final List<Shadow> shadows = switch (effect) {
      'outline' => const [
          Shadow(color: Colors.black, offset: Offset(-1.2, -1.2)),
          Shadow(color: Colors.black, offset: Offset(1.2, -1.2)),
          Shadow(color: Colors.black, offset: Offset(-1.2, 1.2)),
          Shadow(color: Colors.black, offset: Offset(1.2, 1.2)),
        ],
      'shadow' => const [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3)],
      'glow' => const [Shadow(color: cyan, blurRadius: 10)],
      'neon' => const [Shadow(color: cyan, blurRadius: 4), Shadow(color: cyan, blurRadius: 12)],
      '3d' => const [
          Shadow(color: Color(0xFF777777), offset: Offset(1, 1)),
          Shadow(color: Color(0xFF555555), offset: Offset(2, 2)),
          Shadow(color: Color(0xFF333333), offset: Offset(3, 3)),
        ],
      _ => const <Shadow>[],
    };
    return Semantics(
      button: true,
      selected: on,
      label: '$effect effect',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          TextStyleProperties updated = ts.copyWith(textEffect: effect);
          if (effect == 'outline') {
            updated = updated.copyWith(strokeColor: Colors.black, strokeWidth: 3.0);
          } else if (effect == 'shadow') {
            updated = updated.copyWith(
              shadowColor: Colors.black,
              shadowBlurRadius: 6.0,
              shadowOffsetX: 2.0,
              shadowOffsetY: 2.0,
            );
          } else if (effect == 'glow') {
            updated = updated.copyWith(
              shadowColor: const Color(0xFF00E5FF),
              shadowBlurRadius: 12.0,
            );
          } else if (effect == 'neon') {
            updated = updated.copyWith(
              textColor: const Color(0xFF00E5FF),
              shadowColor: const Color(0xFF00E5FF),
              shadowBlurRadius: 16.0,
            );
          }
          editor.updateSelectedClipTextStyle(updated);
        },
        child: Container(
          width: 66,
          decoration: BoxDecoration(
            color: _field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? _accent : _line, width: on ? 1.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                effect == 'none' ? 'Ab' : 'Ab',
                style: TextStyle(
                  color: effect == 'neon' ? cyan : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Poppins',
                  shadows: shadows,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                effect == 'none' ? 'None' : effect[0].toUpperCase() + effect.substring(1),
                style: TextStyle(
                  color: on ? _accent : EditorTokens.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Color tab ------------------------------------------------------------

  Widget _colorTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Text color'),
        _swatches(
          ts.textColor,
          (c) => editor.updateSelectedClipTextStyle(ts.copyWith(textColor: c)),
        ),
      ],
    );
  }

  Widget _swatches(Color selected, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in _colors)
            Semantics(
              button: true,
              selected: selected.toARGB32() == c.toARGB32(),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPick(c);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected.toARGB32() == c.toARGB32() ? _accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: EditorTokens.border),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Layout tab -----------------------------------------------------------

  Widget _layoutTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Alignment'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _alignSegments(editor, ts),
        ),
        _bar('Size & spacing'),
        _ParamSlider(
          label: 'Text size',
          value: ts.fontSize,
          min: 10,
          max: 100,
          step: 1,
          decimals: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(ts.copyWith(fontSize: val)),
        ),
        _ParamSlider(
          label: 'Line height',
          value: ts.lineHeight,
          min: 0.8,
          max: 3.0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(ts.copyWith(lineHeight: val)),
        ),
        _bar('Background'),
        _ParamSlider(
          label: 'Padding',
          value: ts.backgroundPadding,
          min: 0,
          max: 24,
          resetTo: 0,
          onChanged: (val) =>
              editor.updateSelectedClipTextStyle(ts.copyWith(backgroundPadding: val)),
        ),
      ],
    );
  }

  /// Joined icon segmented control, like Premiere's paragraph panel.
  Widget _alignSegments(EditorController editor, TextStyleProperties ts) {
    final items = <(TextAlign, dynamic, String)>[
      (TextAlign.left, HugeIcons.strokeRoundedTextAlignLeft, 'Align left'),
      (TextAlign.center, HugeIcons.strokeRoundedTextAlignCenter, 'Align center'),
      (TextAlign.right, HugeIcons.strokeRoundedTextAlignRight, 'Align right'),
    ];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: ts.textAlign == items[i].$1,
                label: items[i].$3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    editor.updateSelectedClipTextStyle(ts.copyWith(textAlign: items[i].$1));
                  },
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: ts.textAlign == items[i].$1 ? _accent.withAlpha(30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: ts.textAlign == items[i].$1 ? _accent : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: items[i].$2,
                        color: ts.textAlign == items[i].$1 ? _accent : EditorTokens.text,
                        size: 18.0,
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

// ---- Premiere-style parameter row ---------------------------------------------

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 0.1,
    this.decimals = 1,
    this.resetTo,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final double? resetTo;
  final ValueChanged<double> onChanged;

  double get _v => value.clamp(min, max).toDouble();

  double _snap(double v) =>
      ((v.clamp(min, max).toDouble()) / step).round() * step;

  @override
  Widget build(BuildContext context) {
    final bool changed = resetTo != null && (_v - resetTo!).abs() > 1e-6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      color: changed ? EditorTokens.text : EditorTokens.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins')),
              if (changed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(resetTo!);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.undo_rounded, size: 14, color: EditorTokens.muted),
                  ),
                ),
              const Spacer(),
              // Drag the box to scrub; double-tap resets (when a default exists).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: resetTo == null ? null : () => onChanged(resetTo!),
                onHorizontalDragUpdate: (d) =>
                    onChanged(_snap(_v + d.delta.dx * (max - min) / 200)),
                child: Container(
                  width: 64,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _field,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: changed ? _accent.withAlpha(120) : _line),
                  ),
                  child: Text(
                    _v.toStringAsFixed(decimals),
                    style: TextStyle(
                      color: changed ? _accent : EditorTokens.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          LayoutBuilder(builder: (context, box) {
            final double w = box.maxWidth;
            double fromDx(double dx) {
              final double t = ((dx - _pad) / (w - _pad * 2)).clamp(0.0, 1.0).toDouble();
              return _snap(min + (max - min) * t);
            }

            return Semantics(
              slider: true,
              label: label,
              value: _v.toStringAsFixed(decimals),
              increasedValue: _snap(_v + step).toStringAsFixed(decimals),
              decreasedValue: _snap(_v - step).toStringAsFixed(decimals),
              onIncrease: () => onChanged(_snap(_v + step)),
              onDecrease: () => onChanged(_snap(_v - step)),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => onChanged(fromDx(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) => onChanged(fromDx(d.localPosition.dx)),
                child: SizedBox(
                  height: 40,
                  width: w,
                  child: CustomPaint(painter: _SliderPainter((_v - min) / (max - min))),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static const double _pad = 10;
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.t);
  final double t; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = _ParamSlider._pad;
    final double w = size.width - pad * 2;
    const double y = 13;
    final double x = pad + t * w;

    final Rect bar = Rect.fromLTWH(pad, y - 2, w, 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = _track);
    if (t > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(pad, y - 2, x, y + 2), const Radius.circular(2)),
        Paint()..color = _accent,
      );
    }

    // Premiere triangle thumb, pointing up at the track.
    canvas.drawPath(
      Path()
        ..moveTo(x, y + 5)
        ..lineTo(x - 7.5, y + 18)
        ..lineTo(x + 7.5, y + 18)
        ..close(),
      Paint()..color = t > 0 ? _accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.t != t;
}