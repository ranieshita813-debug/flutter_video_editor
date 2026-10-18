import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/core/widgets/caption_widgets.dart';

/// Sheet 2 of 2: caption styling. Text/timing lives in [CaptionsEditSheet].
class CaptionStyleSheet extends StatefulWidget {
  const CaptionStyleSheet({super.key, this.onOpenEdit});

  /// Called when the user taps "Edit". Wire this to open [CaptionsEditSheet].
  final VoidCallback? onOpenEdit;

  @override
  State<CaptionStyleSheet> createState() => _CaptionStyleSheetState();
}

class _CaptionStyleSheetState extends State<CaptionStyleSheet> {
  /// true = every caption, false = only the selected caption.
  bool? _scopeAll;

  static const List<Color> _swatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFFFD700),
    Color(0xFF00E5FF),
    Color(0xFF00FF66),
    Color(0xFFFF007F),
    Color(0xFFFF6600),
    Color(0xFFA855F7),
    Color(0xFF000000),
  ];

  static const List<_Preset> _presets = <_Preset>[
    _Preset('Classic', 'color', Color(0xFFFFD700), Colors.transparent, 28),
    _Preset('Bold', 'scale', Color(0xFFFFFFFF), Colors.transparent, 36),
    _Preset('Badge', 'badge', Color(0xFF000000), Color(0xFFFFFFFF), 30),
    _Preset('Glow', 'outline', Color(0xFF00E5FF), Colors.transparent, 32),
    _Preset('Marker', 'badge', Color(0xFF000000), Color(0xFFFFD700), 30),
    _Preset('Neon', 'outline', Color(0xFFFF007F), Colors.transparent, 32),
    _Preset('Cyberpunk', 'badge', Color(0xFF00FF66), Color(0xFF1A1A2E), 30),
    _Preset('Karaoke', 'scale', Color(0xFFFF3366), Colors.transparent, 34),
    _Preset('Gradient', 'color', Color(0xFF00C4D6), Colors.transparent, 30),
    _Preset('Minimal', 'color', Color(0xFFBDBDBD), Colors.transparent, 26),
    _Preset('Comic', 'badge', Color(0xFF000000), Color(0xFFFFCC00), 32),
    _Preset('Vlog', 'badge', Color(0xFFFFFFFF), Color(0xFFE63946), 28),
    _Preset('Retro', 'outline', Color(0xFFFF9900), Colors.transparent, 30),
  ];

  void _apply(EditorController editor, TextStyleProperties next, bool all) {
    if (all) {
      editor.applyCaptionStyleToAll(next);
    } else {
      editor.updateSelectedClipTextStyle(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final hasCaptionSelected = sel != null && sel.clipType == ClipType.caption;

    // No caption selected -> can only target all captions.
    final all = !hasCaptionSelected || (_scopeAll ?? false);
    final style = (hasCaptionSelected ? sel.textStyle : null) ??
        const TextStyleProperties();

    return Container(
      color: EditorTokens.surface,
      child: Column(
        children: [
          MonoSheetHeader(
            title: 'Caption style',
            trailing: widget.onOpenEdit == null
                ? null
                : MonoButton(
                    label: 'Edit',
                    icon: PhosphorIconsRegular.pencilSimple,
                    onTap: widget.onOpenEdit,
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                const MonoLabel('Apply to'),
                MonoSegmented<bool>(
                  options: const {true: 'All captions', false: 'Selected'},
                  value: all,
                  onChanged: (v) {
                    if (!v && !hasCaptionSelected) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                          content: Text('Select a caption on the timeline first'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ));
                      return;
                    }
                    tapFeedback();
                    setState(() => _scopeAll = v);
                  },
                ),

                const SizedBox(height: 22),
                const MonoLabel('Templates'),
                SizedBox(
                  height: 78,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final p = _presets[i];
                      final selected = style.highlightStyle == p.effect &&
                          style.highlightColor.toARGB32() ==
                              p.color.toARGB32() &&
                          style.highlightBackgroundColor.toARGB32() ==
                              p.badge.toARGB32();
                      return _PresetCard(
                        preset: p,
                        selected: selected,
                        onTap: () {
                          tapFeedback();
                          _apply(
                            editor,
                            style.copyWith(
                              enableHighlight: true,
                              highlightStyle: p.effect,
                              highlightColor: p.color,
                              highlightBackgroundColor: p.badge,
                              fontSize: p.size,
                            ),
                            all,
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 22),
                _toggleRow(
                  title: 'Highlight spoken word',
                  subtitle: 'Follows the speech, word by word',
                  value: style.enableHighlight,
                  onChanged: (v) =>
                      _apply(editor, style.copyWith(enableHighlight: v), all),
                ),

                const SizedBox(height: 22),
                const MonoLabel('Effect'),
                MonoSegmented<String>(
                  options: const {
                    'color': 'Color',
                    'badge': 'Badge',
                    'scale': 'Pop',
                    'outline': 'Glow',
                  },
                  value: style.highlightStyle,
                  onChanged: (v) {
                    tapFeedback();
                    _apply(editor, style.copyWith(highlightStyle: v), all);
                  },
                ),

                const SizedBox(height: 22),
                const MonoLabel('Highlight color'),
                _swatchRow(
                  selected: style.highlightColor,
                  onPick: (c) =>
                      _apply(editor, style.copyWith(highlightColor: c), all),
                ),

                const SizedBox(height: 22),
                const MonoLabel('Badge color'),
                _swatchRow(
                  selected: style.highlightBackgroundColor,
                  withNone: true,
                  onPick: (c) => _apply(
                      editor, style.copyWith(highlightBackgroundColor: c), all),
                ),

                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const MonoLabel('Size', bottom: 0),
                    Text('${style.fontSize.round()}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: CaptionMono.font)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: style.fontSize.clamp(14, 60).toDouble(),
                    min: 14,
                    max: 60,
                    activeColor: Colors.white,
                    inactiveColor: EditorTokens.border,
                    onChanged: (v) =>
                        _apply(editor, style.copyWith(fontSize: v), all),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: CaptionMono.font)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 12,
                      fontFamily: CaptionMono.font)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) {
            tapFeedback();
            onChanged(v);
          },
          activeThumbColor: Colors.black,
          activeTrackColor: Colors.white,
          inactiveThumbColor: EditorTokens.muted,
          inactiveTrackColor: EditorTokens.elevated,
          trackOutlineColor: WidgetStateProperty.all(EditorTokens.border),
        ),
      ],
    );
  }

  Widget _swatchRow({
    required Color selected,
    required ValueChanged<Color> onPick,
    bool withNone = false,
  }) {
    final items = <Color>[if (withNone) Colors.transparent, ..._swatches];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final none = c == Colors.transparent;
          final sel = selected.toARGB32() == c.toARGB32();
          return GestureDetector(
            onTap: () {
              tapFeedback();
              onPick(c);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: none ? null : c,
                borderRadius: BorderRadius.circular(CaptionMono.radius),
                border: Border.all(
                  color: sel ? Colors.white : EditorTokens.border,
                  width: sel ? 2 : 1,
                ),
              ),
              child: none
                  ? const Center(
                      child: PhosphorIcon(PhosphorIconsRegular.prohibit,
                          size: 16, color: Colors.white70))
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _Preset {
  const _Preset(this.name, this.effect, this.color, this.badge, this.size);
  final String name;
  final String effect;
  final Color color;
  final Color badge;
  final double size;
}

class _PresetCard extends StatelessWidget {
  const _PresetCard(
      {required this.preset, required this.selected, required this.onTap});
  final _Preset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(CaptionMono.radius),
          border: Border.all(
            color: selected ? Colors.white : EditorTokens.border,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: preset.badge == Colors.transparent ? null : preset.badge,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            preset.name,
            style: TextStyle(
              color: preset.color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              fontFamily: CaptionMono.font,
              shadows: preset.effect == 'outline'
                  ? [Shadow(color: preset.color, blurRadius: 10)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}