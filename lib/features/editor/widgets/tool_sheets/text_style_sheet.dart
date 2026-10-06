import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

class TextStyleSheet extends StatefulWidget {
  const TextStyleSheet({super.key});

  @override
  State<TextStyleSheet> createState() => _TextStyleSheetState();
}

class _TextStyleSheetState extends State<TextStyleSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';

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

    return Column(
      children: [
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search fonts & styles...',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text Effects Preset
                const Text(
                  'Text Effects',
                  style: TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _textEffects.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final effect = _textEffects[index];
                      final isSelected = ts.textEffect == effect;
                      return ChoiceChip(
                        label: Text(effect.toUpperCase()),
                        selected: isSelected,
                        onSelected: (_) {
                          TextStyleProperties updated = ts.copyWith(textEffect: effect);
                          if (effect == 'outline') {
                            updated = updated.copyWith(
                              strokeColor: Colors.black,
                              strokeWidth: 3.0,
                            );
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
                        selectedColor: EditorTokens.text,
                        backgroundColor: EditorTokens.elevated,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: isSelected ? EditorTokens.bg : EditorTokens.text,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                // Font Family List
                const Text(
                  'Font Family',
                  style: TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: fonts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final font = fonts[index];
                      final isSelected = clip.fontFamily == font;
                      return ChoiceChip(
                        label: Text(font),
                        selected: isSelected,
                        onSelected: (_) => editor.updateSelectedClipFont(font),
                        selectedColor: EditorTokens.text,
                        backgroundColor: EditorTokens.elevated,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: isSelected ? EditorTokens.bg : EditorTokens.text,
                          fontSize: 12,
                          fontFamily: font,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                // Font Size Slider
                _buildSliderRow(
                  label: 'Text Size',
                  value: ts.fontSize,
                  min: 10.0,
                  max: 100.0,
                  onChanged: (val) {
                    editor.updateSelectedClipTextStyle(ts.copyWith(fontSize: val));
                  },
                ),

                // Line Height Slider
                _buildSliderRow(
                  label: 'Line Height',
                  value: ts.lineHeight,
                  min: 0.8,
                  max: 3.0,
                  onChanged: (val) {
                    editor.updateSelectedClipTextStyle(ts.copyWith(lineHeight: val));
                  },
                ),

                // Stroke Width Slider
                _buildSliderRow(
                  label: 'Stroke Width',
                  value: ts.strokeWidth,
                  min: 0.0,
                  max: 10.0,
                  onChanged: (val) {
                    editor.updateSelectedClipTextStyle(
                      ts.copyWith(
                        strokeWidth: val,
                        strokeColor: val > 0 && ts.strokeColor == Colors.transparent
                            ? Colors.black
                            : ts.strokeColor,
                      ),
                    );
                  },
                ),

                // Shadow Blur Slider
                _buildSliderRow(
                  label: 'Shadow Blur',
                  value: ts.shadowBlurRadius,
                  min: 0.0,
                  max: 20.0,
                  onChanged: (val) {
                    editor.updateSelectedClipTextStyle(
                      ts.copyWith(
                        shadowBlurRadius: val,
                        shadowColor: val > 0 && ts.shadowColor == Colors.transparent
                            ? Colors.black87
                            : ts.shadowColor,
                      ),
                    );
                  },
                ),

                // Background Padding Slider
                _buildSliderRow(
                  label: 'Background Padding',
                  value: ts.backgroundPadding,
                  min: 0.0,
                  max: 24.0,
                  onChanged: (val) {
                    editor.updateSelectedClipTextStyle(ts.copyWith(backgroundPadding: val));
                  },
                ),

                const SizedBox(height: 12),
                // Text Colors Palette
                const Text(
                  'Text Color',
                  style: TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _colors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final c = _colors[index];
                      final isSelected = ts.textColor.toARGB32() == c.toARGB32();
                      return GestureDetector(
                        onTap: () => editor.updateSelectedClipTextStyle(ts.copyWith(textColor: c)),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? EditorTokens.text : EditorTokens.border,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                // Stroke Color Palette
                const Text(
                  'Stroke Color',
                  style: TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _colors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final c = _colors[index];
                      final isSelected = ts.strokeColor.toARGB32() == c.toARGB32();
                      return GestureDetector(
                        onTap: () => editor.updateSelectedClipTextStyle(
                          ts.copyWith(
                            strokeColor: c,
                            strokeWidth: ts.strokeWidth == 0 ? 2.0 : ts.strokeWidth,
                          ),
                        ),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? EditorTokens.text : EditorTokens.border,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                // Text Alignment Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Alignment',
                      style: TextStyle(
                        color: EditorTokens.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Row(
                      children: [
                        _buildAlignButton(
                          context,
                          editor,
                          ts,
                          TextAlign.left,
                          HugeIcons.strokeRoundedTextAlignLeft,
                        ),
                        const SizedBox(width: 8),
                        _buildAlignButton(
                          context,
                          editor,
                          ts,
                          TextAlign.center,
                          HugeIcons.strokeRoundedTextAlignCenter,
                        ),
                        const SizedBox(width: 8),
                        _buildAlignButton(
                          context,
                          editor,
                          ts,
                          TextAlign.right,
                          HugeIcons.strokeRoundedTextAlignRight,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: EditorTokens.muted,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: EditorTokens.text,
                inactiveTrackColor: EditorTokens.border,
                thumbColor: EditorTokens.text,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: EditorTokens.text,
                fontSize: 11,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlignButton(
    BuildContext context,
    EditorController editor,
    TextStyleProperties ts,
    TextAlign align,
    dynamic iconData,
  ) {
    final isSelected = ts.textAlign == align;
    return GestureDetector(
      onTap: () => editor.updateSelectedClipTextStyle(ts.copyWith(textAlign: align)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? EditorTokens.text : EditorTokens.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EditorTokens.border),
        ),
        child: HugeIcon(
          icon: iconData,
          color: isSelected ? EditorTokens.bg : EditorTokens.text,
          size: 18.0,
        ),
      ),
    );
  }
}
